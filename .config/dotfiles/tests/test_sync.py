import json
from pathlib import Path
import subprocess
import unittest

import test_dotfiles


class RemoteFollowing(unittest.TestCase):
    setUp = test_dotfiles.OwnershipIntegration.setUp
    tearDown = test_dotfiles.OwnershipIntegration.tearDown
    git = test_dotfiles.OwnershipIntegration.git
    cli = test_dotfiles.OwnershipIntegration.cli

    def remote(self):
        self.upstream = self.root.parent / 'upstream'
        subprocess.run(['git', 'clone', '-q', str(self.root), str(self.upstream)], check=True)
        self.git('remote', 'add', 'origin', str(self.upstream))
        self.git('branch', '-M', 'main')
        subprocess.run(['git', '-C', str(self.upstream), 'branch', '-M', 'main'], check=True)

    def change(self, path='.tmux.conf', data=None):
        target = self.upstream / path
        target.write_bytes(data if data is not None else target.read_bytes() + b'\n# remote change\n')
        for args in [('add', '--', path), ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'remote change')]:
            subprocess.run(['git', '-C', str(self.upstream), *args], check=True, capture_output=True)

    def test_updates_and_preserves_unrelated_local_edit(self):
        self.remote()
        local = self.root / '.zprofile'
        local.write_bytes(local.read_bytes() + b'\n# unsaved local edit\n')
        original = local.read_bytes()
        self.change()
        self.cli('update')
        self.assertIn(b'remote change', (self.root / '.tmux.conf').read_bytes())
        self.assertEqual(local.read_bytes(), original)
        self.cli('update')
        state = json.loads((self.root / 'Library/Application Support/dotfiles/last-update.json').read_text())
        self.assertEqual(state['status'], 'current')

    def test_conflicting_edits_are_not_stashed_or_overwritten(self):
        self.remote()
        local = self.root / '.tmux.conf'
        local.write_bytes(local.read_bytes() + b'\n# local edit\n')
        original = local.read_bytes()
        head = self.git('rev-parse', 'HEAD').stdout
        self.change()
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertEqual(local.read_bytes(), original)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, head)
        self.assertEqual(self.git('stash', 'list').stdout, b'')

    def test_divergence_and_staged_changes_block(self):
        self.remote()
        self.change()
        local = self.root / '.zprofile'
        local.write_bytes(local.read_bytes() + b'\n# local commit\n')
        self.git('add', '.zprofile')
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.git('commit', '-qm', 'local commit')
        head = self.git('rev-parse', 'HEAD').stdout
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, head)

    def test_non_main_is_untouched(self):
        self.remote()
        self.git('checkout', '-qb', 'feature')
        self.change()
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertNotIn(b'remote change', (self.root / '.tmux.conf').read_bytes())

    def test_invalid_remote_is_not_applied(self):
        self.remote()
        self.change('.claude/settings.json', b'{"hooks":{}}')
        head = self.git('rev-parse', 'HEAD').stdout
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, head)

    def test_untracked_collision_preserved(self):
        self.remote()
        target = self.root / '.config/zsh/new.zsh'
        target.write_text('# local\n')
        other = self.upstream / '.config/zsh/new.zsh'
        other.write_text('# remote\n')
        manifest = self.upstream / '.config/dotfiles/ownership.json'
        m = json.loads(manifest.read_text())
        m['shared'].append('.config/zsh/new.zsh')
        manifest.write_text(json.dumps(m))
        subprocess.run(['git', '-C', str(self.upstream), 'add', '-f', str(other), str(manifest)], check=True)
        subprocess.run(['git', '-C', str(self.upstream), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'new config'], check=True)
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertEqual(target.read_text(), '# local\n')

    def test_lock_prevents_concurrent_updates(self):
        import fcntl
        directory = self.root / 'Library/Application Support/dotfiles'
        directory.mkdir(parents=True)
        with (directory / 'update.lock').open('a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.cli('update')
            self.assertIn(b'another update is running', result.stdout)

    def test_portable_scheduler_and_disable_survives_render(self):
        import plistlib
        template = '.config/dotfiles/templates/com.junhat6.dotfiles-update.plist'
        data = self.repo.rendered({'template': template}, self.root)
        obj = plistlib.loads(data)
        self.assertEqual(obj['StartInterval'], 900)
        self.assertIn(str(self.root), obj['ProgramArguments'][1])
        self.cli('render')
        self.assertFalse((self.root / 'Library/LaunchAgents/com.junhat6.dotfiles-update.plist').exists())


    def test_enable_disable_and_status(self):
        import importlib.util
        import sys
        from unittest.mock import patch
        scripts = str(self.root / '.config/dotfiles/scripts')
        sys.path.insert(0, scripts)
        try:
            spec = importlib.util.spec_from_file_location('sync_under_test', Path(scripts) / 'sync.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        finally:
            sys.path.remove(scripts)
        repo = module.Repository(self.root, 'yadm')
        loaded = [False]
        commands = []
        def invoke(repo, *args):
            commands.append(args)
            if args[1] == 'bootstrap':
                loaded[0] = True
            elif args[1] == 'bootout':
                loaded[0] = False
            return ''
        def inspect(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0 if loaded[0] else 1)
        with patch.object(module.platform, 'system', return_value='Darwin'), patch.object(module.Path, 'home', return_value=self.root), patch.object(module, 'command', side_effect=invoke), patch.object(module.subprocess, 'run', side_effect=inspect):
            module.auto_update(repo, 'enable')
            module.auto_update(repo, 'enable')
            self.assertEqual(sum(c[1] == 'bootstrap' for c in commands), 1)
            self.assertTrue((self.root / module.PLIST).exists())
            module.auto_update(repo, 'status')
            module.auto_update(repo, 'disable')
            module.auto_update(repo, 'disable')
            self.assertFalse(loaded[0])
            self.assertFalse((self.root / module.PLIST).exists())
        self.cli('render')
        self.assertFalse((self.root / module.PLIST).exists())

    def test_merge_in_progress_is_untouched(self):
        self.remote()
        self.change()
        (self.root / '.git/MERGE_HEAD').write_bytes(self.git('rev-parse', 'HEAD').stdout)
        result = self.cli('update', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('進行中', result.stdout.decode())


    def test_remote_symlink_is_rejected(self):
        self.remote()
        target = self.upstream / '.tmux.conf'
        target.unlink()
        target.symlink_to('README.md')
        self.change('.zprofile')
        subprocess.run(['git', '-C', str(self.upstream), 'add', '.tmux.conf'], check=True)
        subprocess.run(['git', '-C', str(self.upstream), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'symlink'], check=True)
        head = self.git('rev-parse', 'HEAD').stdout
        self.assertNotEqual(self.cli('update', success=False).returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, head)
        self.assertFalse((self.root / '.tmux.conf').is_symlink())


if __name__ == '__main__':
    unittest.main()
