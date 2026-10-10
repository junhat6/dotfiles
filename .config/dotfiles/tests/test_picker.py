#!/usr/bin/env python3
"""Shared-file picker behavior against isolated Git worktrees."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import picker
from dotfiles import Repository


class PickerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.names = ['plain.txt', 'space and quote\' $(touch OWNED);.txt', 'gone.txt']
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        self.manifest(self.names)
        for name in self.names:
            (self.root / name).write_text('initial\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.repo = Repository(self.root, 'git')

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)

    def manifest(self, shared):
        file = self.root / '.config/dotfiles/ownership.json'
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(json.dumps({'version': 1, 'shared': shared, 'local': ['private.txt'],
                                   'excluded': [], 'generated': [], 'discovery_roots': []}))

    def item(self, name):
        return next(x for x in picker.entries(self.repo) if x['path'] == name)

    def test_staged_and_unstaged_are_both_previewed(self):
        file = self.root / 'plain.txt'
        file.write_text('staged value\n')
        self.git('add', 'plain.txt')
        file.write_text('unstaged value\n')
        text = picker.preview(self.repo, self.item('plain.txt')['key'])
        self.assertIn('STAGED', text)
        self.assertIn('+staged value', text)
        self.assertIn('UNSTAGED', text)
        self.assertIn('+unstaged value', text)
        self.assertEqual(['plain.txt'], [x['path'] for x in picker.entries(self.repo, True)])

    def test_special_filename_is_literal(self):
        name = self.names[1]
        (self.root / name).write_text('changed\n')
        text = picker.preview(self.repo, self.item(name)['key'])
        self.assertIn('+changed', text)
        self.assertFalse((self.root / 'OWNED').exists())
        row = picker.rows(self.repo)
        self.assertIn('\t' + name + '\n', row)

    def test_private_files_and_invalid_keys_are_rejected(self):
        (self.root / 'private.txt').write_text('secret')
        self.git('add', 'private.txt')
        self.assertNotIn('private.txt', picker.rows(self.repo))
        for key in ['../private.txt', 'private.txt', '/etc/passwd', '$(touch OWNED)']:
            with self.assertRaises(ValueError):
                picker.resolve(self.repo, key)

    def test_symlink_and_symlink_parent_are_rejected(self):
        key = self.item('plain.txt')['key']
        (self.root / 'plain.txt').unlink()
        (self.root / 'plain.txt').symlink_to(self.root / 'gone.txt')
        with self.assertRaises(ValueError):
            picker.resolve(self.repo, key)
        (self.root / 'linked').symlink_to(self.root, target_is_directory=True)
        self.manifest(['linked/gone.txt'])
        self.assertEqual([], picker.entries(self.repo))

    def test_new_and_binary_and_large_content(self):
        self.manifest(self.names + ['new.txt'])
        (self.root / 'new.txt').write_text('fresh\n')
        self.assertIn('fresh', picker.preview(self.repo, self.item('new.txt')['key']))
        (self.root / 'plain.txt').write_bytes(b'\0binary')
        self.assertIn('Binary files', picker.preview(self.repo, self.item('plain.txt')['key']))
        (self.root / 'new.txt').write_bytes(b'x' * (picker.LIMIT + 100))
        self.assertIn('truncated', picker.preview(self.repo, self.item('new.txt')['key']))

    def run_edit(self, selection='', code=0, changed=False, query=None):
        real_run = subprocess.run
        calls = []
        def fake(command, **kwargs):
            if command[0] in ('fzf', 'nvim'):
                calls.append((command, kwargs))
                return subprocess.CompletedProcess(command, code if command[0] == 'fzf' else 0,
                                                   stdout=selection)
            return real_run(command, **kwargs)
        with patch.object(picker.subprocess, 'run', side_effect=fake):
            result = picker.edit(self.repo, changed, query)
        return result, calls

    def test_cancel_and_empty_changed_never_launch_editor(self):
        for code in (1, 130):
            result, calls = self.run_edit(code=code)
            self.assertEqual(0, result)
            self.assertEqual(['fzf'], [x[0][0] for x in calls])
        result, calls = self.run_edit(changed=True)
        self.assertEqual([], calls)

    def test_deleted_file_is_inspectable_and_not_recreated(self):
        (self.root / 'gone.txt').unlink()
        item = self.item('gone.txt')
        self.assertIn('-initial', picker.preview(self.repo, item['key']))
        result, calls = self.run_edit(item['key'] + '\t D\tgone.txt\n')
        self.assertEqual(['fzf'], [x[0][0] for x in calls])
        self.assertFalse((self.root / 'gone.txt').exists())

    def test_changed_query_and_editor_argv_are_safe(self):
        name = self.names[1]
        (self.root / name).write_text('change\n')
        item = self.item(name)
        with patch.dict(os.environ, {'GIT_DIR': '/wrong', 'GIT_WORK_TREE': '/wrong'}):
            # Git itself must see fixture environment, so isolate only editor-env assertions.
            env = picker.editor_env()
        self.assertNotIn('GIT_DIR', env)
        result, calls = self.run_edit(item['key'] + '\t M\t' + name + '\n', changed=True,
                                      query='$(touch OWNED)')
        fzf, kwargs = calls[0]
        self.assertEqual('$(touch OWNED)', fzf[fzf.index('--query') + 1])
        self.assertNotIn('plain.txt', kwargs['input'])
        self.assertEqual(['nvim', '--', str(self.repo.root / name)], calls[1][0])
        preview = next(x for x in fzf if x.startswith('--preview='))
        self.assertIn('preview {1}', preview)
        self.assertNotIn(name, preview)
        self.assertFalse((self.root / 'OWNED').exists())

    def test_rename_preserves_old_shared_deletion(self):
        self.git('mv', 'gone.txt', 'renamed.txt')
        item = self.item('gone.txt')
        self.assertTrue(item['changed'])
        self.assertTrue(item['deleted'])
        self.assertNotIn('renamed.txt', picker.rows(self.repo))

    def test_control_character_filename_not_emitted(self):
        self.manifest(['bad\nname'])
        (self.root / 'bad\nname').write_text('x')
        self.assertEqual('', picker.rows(self.repo))

    @unittest.skipUnless(shutil.which('fzf'), 'fzf unavailable')
    def test_real_fzf_search_uses_path_not_hidden_key(self):
        # fzf applies --nth to the text transformed by --with-nth.
        # Exercise the real binary so a selector which looks fine but finds
        # no filenames cannot pass through editor-launch test doubles.
        _, calls = self.run_edit(code=130)
        command = calls[0][0] + ['--filter=quote']
        result = subprocess.run(command, input=picker.rows(self.repo), text=True,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.names[1], result.stdout)
        self.assertFalse((self.root / 'OWNED').exists())

    def test_plain_preview_has_no_terminal_colors(self):
        (self.root / 'plain.txt').write_text('changed\n')
        key = self.item('plain.txt')['key']
        plain = picker.preview(self.repo, key, plain=True)
        self.assertIn('+changed', plain)
        self.assertNotIn('\x1b', plain)
        self.assertIn('\x1b', picker.preview(self.repo, key))


class ShortcutIntegrationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('zsh'), 'zsh is required')
    def test_reload_replaces_legacy_binding(self):
        navigation = SCRIPTS.parents[2] / '.config/zsh/navigation.zsh'
        result = subprocess.run(
            ['zsh', '-f', '-ic',
             'zoxide(){ :; }; bindkey -e; bindkey "^X^D" old-widget; '
             'source "$1"; source "$1"; bindkey "^]"; bindkey "^X^D"',
             'shortcut-check', str(navigation)],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"^]" dotfiles-edit-widget', result.stdout)
        self.assertIn('"^X^D" undefined-key', result.stdout)

    @unittest.skipUnless(shutil.which('wezterm'), 'WezTerm is required')
    def test_wezterm_effective_binding_sends_matching_control_byte(self):
        config = SCRIPTS.parents[2] / '.config/wezterm/wezterm.lua'
        result = subprocess.run(
            ['wezterm', '--config-file', str(config), 'show-keys', '--lua'],
            capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        main_keys = result.stdout.split('key_tables =', 1)[0]
        bindings = [line for line in main_keys.splitlines()
                    if "key = ']'" in line and "mods = 'CTRL'" in line]
        self.assertEqual(len(bindings), 1, result.stdout)
        self.assertIn(r"act.SendString '\u{1d}'", bindings[0])

    @unittest.skipUnless(shutil.which('wezterm'), 'WezTerm is required')
    def test_wezterm_word_arrows_send_shell_word_motion(self):
        config = SCRIPTS.parents[2] / '.config/wezterm/wezterm.lua'
        result = subprocess.run(['wezterm', '--config-file', str(config), 'show-keys', '--lua'],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        main_keys = result.stdout.split('key_tables =', 1)[0]
        for key, sequence in [('LeftArrow', r'\u{1b}b'), ('RightArrow', r'\u{1b}f')]:
            bindings = [line for line in main_keys.splitlines()
                        if "key = '" + key + "'" in line and "mods = 'ALT'" in line]
            self.assertEqual(len(bindings), 1)
            self.assertIn(sequence, bindings[0])
        self.assertIn('config.leader = { key = ";", mods = "CTRL",', config.read_text())


if __name__ == '__main__':
    unittest.main()
