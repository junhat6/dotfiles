import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('setup_machine', SOURCE / '.config/dotfiles/scripts/setup_machine.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MachineSetup(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / 'home space & quote\'s'
        self.home.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def test_new_agent_permissions_are_not_elevated_and_existing_modes_survive(self):
        MODULE.prepare_local(self.home)
        target = self.home / '.claude/settings.local.json'
        self.assertEqual(json.loads(target.read_text())['permissions']['defaultMode'], 'default')
        target.write_text('{"permissions":{"defaultMode":"plan"},"other":true}')
        before = target.read_bytes()
        MODULE.prepare_local(self.home)
        self.assertEqual(target.read_bytes(), before)

    def test_invalid_local_settings_and_symlink_are_not_overwritten(self):
        target = self.home / '.claude/settings.local.json'
        target.parent.mkdir()
        target.write_text('{bad json')
        with self.assertRaises(ValueError):
            MODULE.prepare_local(self.home)
        self.assertEqual(target.read_text(), '{bad json')
        target.unlink()
        other = self.root / 'private.json'
        other.write_text('{}')
        target.symlink_to(other)
        with self.assertRaises(ValueError):
            MODULE.prepare_local(self.home)
        self.assertEqual(other.read_text(), '{}')

    def make_tree(self):
        repo = self.root / 'source'
        repo.mkdir()
        paths = ['.zshrc', '.config/example/settings.json', '.config/dotfiles/ownership.json']
        for rel in paths:
            dest = repo / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(json.dumps({'shared': paths}) if rel.endswith('ownership.json') else 'remote\n')
        for args in [('init', '-q'), ('add', '-f', '.'), ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')]:
            subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)

        def command(args):
            return ['git', '--git-dir=' + str(repo / '.git'), '--work-tree=' + str(self.home), *args[1:]] if args[0] == 'yadm' else list(args)

        def output(*args):
            return subprocess.check_output(command(args))

        def run(*args, **kwargs):
            return subprocess.run(command(args), check=True, capture_output=True, **kwargs)

        return repo, output, run

    def test_initial_checkout_backs_up_conflicts_and_resumes_without_reset(self):
        _, output, run = self.make_tree()
        old = self.home / '.zshrc'
        old.write_text('my local shell\n')
        backup = self.root / 'backups'
        with patch.object(MODULE, 'output', output), patch.object(MODULE, 'run', run):
            MODULE.checkout(self.home, backup)
            MODULE.checkout(self.home, backup)
        self.assertEqual((backup / '.zshrc').read_text(), 'my local shell\n')
        self.assertEqual(old.read_text(), 'remote\n')

    def test_symlink_ancestor_rejected_before_any_checkout_or_backup(self):
        _, output, run = self.make_tree()
        old = self.home / '.zshrc'
        old.write_text('keep this\n')
        elsewhere = self.root / 'elsewhere'
        elsewhere.mkdir()
        (self.home / '.config').symlink_to(elsewhere, target_is_directory=True)
        with patch.object(MODULE, 'output', output), patch.object(MODULE, 'run', run):
            with self.assertRaises(ValueError):
                MODULE.checkout(self.home, self.root / 'backup')
        self.assertEqual(old.read_text(), 'keep this\n')
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_credential_helper_is_local_idempotent_and_handles_quoted_home(self):
        shared = self.home / '.gitconfig'
        shared.write_text('[include]\n path = ~/.gitconfig.local\n')
        local = self.home / '.gitconfig.local'
        local.write_text('[user]\n name = Keep Me\n')
        shim = self.home / '.local/share/mise/shims/gh'
        shim.parent.mkdir(parents=True)
        shim.write_text('#!/bin/sh\nexit 0\n')

        def run(*args, **kwargs):
            if args[0] != 'mise':
                return subprocess.run(args, check=True, capture_output=True, **kwargs)

        with patch.object(MODULE, 'run', run), patch.object(MODULE.shutil, 'which', return_value='/opt/homebrew/bin/mise'):
            MODULE.credentials(self.home)
            MODULE.credentials(self.home)
        self.assertEqual(shared.read_text(), '[include]\n path = ~/.gitconfig.local\n')
        self.assertIn('Keep Me', local.read_text())
        helpers = subprocess.check_output(['git', 'config', '--file', str(local), '--get-all', 'credential.https://github.com.helper']).decode().splitlines()
        self.assertEqual(len(helpers), 2)
        import shlex
        command = shlex.split(helpers[1][1:])
        self.assertEqual(command[:5], ['/opt/homebrew/bin/mise', '--cd', str(self.home), 'exec', 'gh'])
        self.assertNotIn('versioned', helpers[1])
        self.assertEqual(local.stat().st_mode & 0o777, 0o600)

    def test_resume_keeps_open_vault_roles_and_never_pushes(self):
        calls = []
        for kind in ('personal', 'work'):
            vault = self.home / f'ghq/github.com/junhat6/my-vault-{kind}'
            settings = vault / '.obsidian/plugins/obsidian-git/data.json'
            settings.parent.mkdir(parents=True)
            settings.write_text(json.dumps({'disablePush': kind != 'personal'}))
            (vault / '.obsidian/community-plugins.json').write_text('[]')

        def output(*args):
            return ('https://github.com/junhat6/' + Path(args[2]).name + '.git\n').encode()

        with patch.object(MODULE, 'output', output), patch.object(MODULE, 'run', lambda *args: calls.append(args)):
            MODULE.vaults(self.home, 'personal')
        self.assertFalse(any('obsidian-git-role.py' in str(args) for args in calls))
        self.assertFalse(any('push' in args for args in calls))
        self.assertTrue(any('--check-destination' in args for args in calls))

    def test_wrong_vault_origin_is_not_modified(self):
        directory = self.home / 'ghq/github.com/junhat6/my-vault-personal'
        directory.mkdir(parents=True)
        with patch.object(MODULE, 'output', return_value=b'https://github.com/someone/else.git\n'), patch.object(MODULE, 'run') as run:
            with self.assertRaises(ValueError):
                MODULE.vaults(self.home, 'personal')
            run.assert_not_called()

    def test_plan_and_status_do_not_create_home_or_invoke_auth(self):
        home = self.root / 'does-not-exist'
        env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'))
        script = SOURCE / 'setup.sh'
        for args in [('--profile', 'personal', '--dry-run'), ('--status',)]:
            result = subprocess.run(['bash', str(script), *args], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(home.exists())
        result = subprocess.run(['bash', str(script), '--profile', 'wrong'], env=env, capture_output=True)
        self.assertEqual(result.returncode, 2)


class AppVerification(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.appdir = self.home / 'Applications'
        self.appdir.mkdir()
        self.app = self.appdir / 'Example.app'
        self.app.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def result(self, stdout='', stderr='', code=0):
        return subprocess.CompletedProcess([], code, stdout, stderr)

    def test_only_literal_brewfile_casks_and_fully_qualified_orca(self):
        p = self.home / 'Brewfile'
        p.write_text('tap "stablyai/orca"\ncask "stablyai/orca/orca"\n# cask "unlisted"\n')
        self.assertEqual(MODULE.brewfile_casks(p), ['stablyai/orca/orca'])
        p.write_text('cask ENV["APP"]\n')
        with self.assertRaises(ValueError):
            MODULE.brewfile_casks(p)
        metadata = dict(full_token='orca', installed='1', artifacts=[{'app':['Example.app'], 'target':str(self.app)}])
        with self.assertRaises(ValueError):
            MODULE.app_targets('stablyai/orca/orca', metadata, self.appdir)

    def test_targets_reject_external_paths_and_symlinks(self):
        metadata = dict(full_token='example', installed='1', artifacts=[{'app':['Example.app'], 'target':str(self.app)}])
        self.assertEqual(MODULE.app_targets('example', metadata, self.appdir), [self.app])
        metadata['artifacts'][0]['target'] = str(self.home / 'Other.app')
        with self.assertRaises(ValueError):
            MODULE.app_targets('example', metadata, self.appdir)
        link = self.appdir / 'Link.app'
        link.symlink_to(self.app)
        metadata['artifacts'][0]['target'] = str(link)
        with self.assertRaises(ValueError):
            MODULE.app_targets('example', metadata, self.appdir)

    def test_signature_and_explicit_notarization_are_both_required(self):
        with patch.object(MODULE.subprocess, 'run', side_effect=[self.result(), self.result(stderr='accepted\nsource=Notarized Developer ID\n')]) as call:
            MODULE.check_app(self.app)
            self.assertEqual(call.call_args_list[0].args[0][0], '/usr/bin/codesign')
            self.assertIn('--strict', call.call_args_list[0].args[0])
            self.assertEqual(call.call_args_list[1].args[0][0], '/usr/sbin/spctl')
        with patch.object(MODULE.subprocess, 'run', side_effect=[self.result(), self.result(stderr='source=Developer ID')]):
            with self.assertRaises(ValueError):
                MODULE.check_app(self.app)
        with patch.object(MODULE.subprocess, 'run', return_value=self.result(code=1)) as call:
            with self.assertRaises(ValueError):
                MODULE.check_app(self.app)
            self.assertEqual(call.call_count, 1)

    @unittest.skipUnless(os.uname().sysname == 'Darwin', 'macOS xattr integration')
    def test_only_quarantine_removed_without_following_bundle_symlinks(self):
        binary = self.app / 'binary'
        binary.write_text('test')
        outside = self.home / 'private'
        outside.mkdir()
        (self.app / 'external').symlink_to(outside, target_is_directory=True)
        for path in [self.app, binary, outside]:
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', 'test', str(path)], check=True)
        subprocess.run(['/usr/bin/xattr', '-w', 'test.keep', 'preserved', str(self.app)], check=True)
        self.assertEqual(MODULE.clear_app_quarantine(self.app), 2)
        self.assertEqual(subprocess.check_output(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(outside)], text=True).strip(), 'test')
        self.assertEqual(subprocess.check_output(['/usr/bin/xattr', '-p', 'test.keep', str(self.app)], text=True).strip(), 'preserved')
        self.assertEqual(MODULE.clear_app_quarantine(self.app), 0)

    def setup_brewfile(self):
        p = self.home / '.config/dotfiles/Brewfile'
        p.parent.mkdir(parents=True)
        p.write_text('cask "example"\n')
        return dict(casks=[dict(full_token='example', installed='1', artifacts=[{'app':['Example.app'], 'target':str(self.app)}])])

    def test_failed_verification_never_removes_attributes_and_is_reported(self):
        metadata = self.setup_brewfile()
        report = self.home / 'report.json'
        with patch('platform.system', return_value='Darwin'), patch.object(MODULE.subprocess, 'run', side_effect=[self.result('assessments enabled\n'), self.result(json.dumps(metadata))]), patch.object(MODULE, 'check_app', side_effect=ValueError('not notarized')), patch.object(MODULE, 'clear_app_quarantine') as clear:
            MODULE.prepare_apps(self.home, report, appdir=self.appdir)
            clear.assert_not_called()
        self.assertEqual(json.loads(report.read_text())['apps'][0]['status'], 'deferred')

    def test_gatekeeper_disabled_and_unlisted_selection_fail_before_mutation(self):
        self.setup_brewfile()
        with patch('platform.system', return_value='Darwin'), patch.object(MODULE.subprocess, 'run', return_value=self.result('assessments disabled\n')), patch.object(MODULE, 'clear_app_quarantine') as clear:
            with self.assertRaises(ValueError):
                MODULE.prepare_apps(self.home, self.home / 'report.json', appdir=self.appdir)
            with self.assertRaises(ValueError):
                MODULE.prepare_apps(self.home, self.home / 'report.json', selected=['unlisted'], appdir=self.appdir)
            clear.assert_not_called()

    def test_changed_bundle_during_verification_is_deferred(self):
        metadata = self.setup_brewfile()
        report = self.home / 'report.json'
        def change(app):
            (app / 'new-file').write_text('changed')
            os.utime(app, ns=(1, 1))
        with patch('platform.system', return_value='Darwin'), patch.object(MODULE.subprocess, 'run', side_effect=[self.result('assessments enabled\n'), self.result(json.dumps(metadata))]), patch.object(MODULE, 'check_app', side_effect=change), patch.object(MODULE, 'clear_app_quarantine') as clear:
            MODULE.prepare_apps(self.home, report, appdir=self.appdir)
            clear.assert_not_called()
        self.assertEqual(json.loads(report.read_text())['apps'][0]['status'], 'deferred')

    def test_check_only_verifies_without_mutation(self):
        metadata = self.setup_brewfile()
        report = self.home / 'report.json'
        with patch('platform.system', return_value='Darwin'), patch.object(MODULE.subprocess, 'run', side_effect=[self.result('assessments enabled\n'), self.result(json.dumps(metadata))]), patch.object(MODULE, 'check_app'), patch.object(MODULE, 'clear_app_quarantine') as clear:
            MODULE.prepare_apps(self.home, report, check_only=True, appdir=self.appdir)
            clear.assert_not_called()
        self.assertEqual(json.loads(report.read_text())['apps'][0]['status'], 'verified')


if __name__ == '__main__':
    unittest.main()
