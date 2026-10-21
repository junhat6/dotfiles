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


if __name__ == '__main__':
    unittest.main()
