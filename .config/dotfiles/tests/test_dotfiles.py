import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('dotfiles', SOURCE / '.config/dotfiles/scripts/dotfiles.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class OwnershipIntegration(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = (Path(self.temporary.name) / 'home space & symbol').resolve()
        self.root.mkdir()
        for rel in json.loads((SOURCE / MODULE.MANIFEST).read_text())['shared']:
            dest = self.root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / rel, dest)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'core.hooksPath', str(self.root / '.config/dotfiles/git-hooks'))
        self.git('add', '.')
        self.cli('render')
        self.git('commit', '-qm', 'fixture')
        self.repo = MODULE.Repository(self.root, 'git')

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args, success=True):
        result = subprocess.run(['git', '-C', str(self.root), *args], capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result

    def cli(self, *args, success=True):
        result = subprocess.run([os.sys.executable, str(self.root / '.config/dotfiles/scripts/dotfiles.py'), '--root', str(self.root), '--backend', 'git', *args], capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result

    def test_atomic_replacement_stays_tracked(self):
        path = self.root / '.tmux.conf'
        replacement = path.with_suffix('.new')
        replacement.write_bytes(path.read_bytes() + b'\n# atomic edit\n')
        replacement.replace(path)
        self.assertIn('.tmux.conf', self.git('diff', '--name-only').stdout.decode())
        self.assertIn('.tmux.conf', self.repo.tracked())

    def test_new_config_candidate_detected(self):
        p = self.root / '.config/zsh/new.zsh'
        p.write_text('# candidate\n')
        result = self.cli('check', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('new candidate', result.stderr.decode())
        self.assertNotEqual(self.cli('add', str(p), success=False).returncode, 0)

    def test_forced_local_file_cannot_commit(self):
        path = self.root / '.claude/settings.local.json'
        path.write_text('{"permissions":{"allow":["private"]}}')
        self.git('add', '-f', str(path))
        self.assertNotEqual(self.git('commit', '-qm', 'forbidden', success=False).returncode, 0)

    def test_index_content_checked_when_worktree_valid(self):
        path = self.root / '.claude/settings.json'
        original = path.read_bytes()
        path.write_text('{"permissions":{"defaultMode":"bypassPermissions"}}')
        self.git('add', str(path))
        path.write_bytes(original)
        self.assertNotEqual(self.git('commit', '-qm', 'invalid staged mode', success=False).returncode, 0)

    def test_staged_keymap_drift_rejected_with_valid_worktree(self):
        path = self.root / '.config/karabiner/karabiner.json'
        original = path.read_bytes()
        data = json.loads(original)
        data['profiles'][0]['name'] = 'Changed profile'
        path.write_text(json.dumps(data))
        self.git('add', str(path))
        path.write_bytes(original)
        result = self.git('commit', '-qm', 'stale staged keymap', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale keymap', result.stderr.decode())

    def test_committed_keymap_drift_rejected(self):
        path = self.root / '.config/karabiner/keymap.svg'
        path.write_text(path.read_text() + '\n')
        self.git('add', str(path))
        # The fixture bypasses its hook to model an old/inconsistent pushed tree.
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture drift')
        result = self.cli('check', '--revision', 'HEAD', '--source', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale keymap', result.stderr.decode())

    def test_invalid_shell_index_rejected_with_valid_worktree(self):
        path = self.root / '.zshrc'
        original = path.read_bytes()
        path.write_text('if then invalid syntax')
        self.git('add', str(path))
        path.write_bytes(original)
        result = self.git('commit', '-qm', 'invalid staged shell', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid shell syntax', result.stderr.decode())

    def test_staged_manifest_cannot_allow_forbidden(self):
        path = self.root / MODULE.MANIFEST
        original = path.read_bytes()
        m = json.loads(original)
        m['shared'].append('.claude/settings.local.json')
        path.write_text(json.dumps(m))
        self.git('add', str(path))
        path.write_bytes(original)
        self.assertNotEqual(self.cli('check', '--index', success=False).returncode, 0)

    def test_generated_drift_and_portable_xml(self):
        import plistlib
        target = self.root / 'Library/LaunchAgents/com.claude.brewfile-sync.plist'
        obj = plistlib.loads(target.read_bytes())
        self.assertEqual(obj['ProgramArguments'][1], str(self.root / '.claude/hooks/brewfile-sync.sh'))
        target.write_bytes(target.read_bytes() + b'\n')
        self.assertNotEqual(self.cli('check', success=False).returncode, 0)
        self.cli('render')
        self.cli('check')

    def test_local_mode_preserved_and_invalid_not_overwritten(self):
        target = self.root / '.claude/settings.local.json'
        target.write_text('{"permissions":{"defaultMode":"plan","allow":["existing"]},"hooks":{}}')
        original = target.read_bytes()
        self.cli('bootstrap-local')
        self.assertEqual(target.read_bytes(), original)
        target.write_text('{invalid')
        self.assertNotEqual(self.cli('bootstrap-local', success=False).returncode, 0)
        self.assertEqual(target.read_text(), '{invalid')

    def test_local_initialization_and_idempotence(self):
        managed = self.root / 'corporate-managed.json'
        managed.write_text('{}')
        self.cli('bootstrap-local', '--managed-settings', str(managed))
        target = self.root / '.claude/settings.local.json'
        self.assertEqual(json.loads(target.read_text())['permissions']['defaultMode'], 'auto')
        original = target.read_bytes()
        self.cli('bootstrap-local', '--managed-settings', str(self.root / 'absent'))
        self.cli('render')
        self.cli('render')
        self.assertEqual(target.read_bytes(), original)
        self.cli('check')

    def test_source_check_does_not_write_or_require_generated(self):
        shutil.rmtree(self.root / 'Library')
        self.cli('check', '--source')
        self.assertFalse((self.root / 'Library').exists())
        self.assertFalse((self.root / '.claude/settings.local.json').exists())

    def test_isolated_yadm_clone_bootstrap_idempotent(self):
        if shutil.which('yadm') is None:
            self.skipTest('yadm unavailable')
        home = self.root.parent / 'fresh-home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_DATA_HOME=str(home / '.local/share'))
        env.pop('GIT_DIR', None)
        env.pop('GIT_WORK_TREE', None)
        def yadm(*args):
            result = subprocess.run(['yadm', *args], cwd=home, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode() + result.stdout.decode())
            return result.stdout
        for key in ('auto-private-dirs', 'auto-perms', 'auto-alt'):
            yadm('config', 'yadm.' + key, 'false')
        yadm('clone', '--no-bootstrap', str(self.root))
        yadm('bootstrap')
        local = home / '.claude/settings.local.json'
        first = local.read_bytes()
        yadm('bootstrap')
        self.assertEqual(local.read_bytes(), first)
        self.assertEqual(yadm('gitconfig', 'core.hooksPath').decode().strip(), str(home / '.config/dotfiles/git-hooks'))
        self.assertNotIn('.claude/settings.local.json', yadm('ls-files').decode().splitlines())
        self.assertFalse((home / '.ssh').exists())
        self.assertFalse((home / '.gnupg').exists())
        result = subprocess.run([str(home / '.local/bin/dotfiles'), 'check'], cwd=home, env=env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_unknown_config_dir_reported_without_blocking(self):
        (self.root / '.config/new-app').mkdir()
        (self.root / '.config/new-app/config').write_text('new local app')
        result = self.cli('status', '--json')
        self.assertIn('.config/new-app', json.loads(result.stdout)['unknown_config_directories'])
        self.cli('check')

    def test_invalid_committed_tip_cannot_push(self):
        path = self.root / '.claude/settings.json'
        path.write_text('{"hooks":{}}')
        self.git('add', str(path))
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'invalid')
        bad = self.git('rev-parse', 'HEAD').stdout.decode().strip()
        self.git('reset', '--hard', 'HEAD~1')
        line = 'refs/heads/bad ' + bad + ' refs/heads/bad ' + '0' * 40 + '\n'
        result = subprocess.run([str(self.root / '.config/dotfiles/git-hooks/pre-push')], input=line.encode(), cwd=self.root, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_pre_push_checks_index_and_drift(self):
        path = self.root / '.claude/settings.local.json'
        path.write_text('{}')
        self.git('add', '-f', str(path))
        result = subprocess.run([str(self.root / '.config/dotfiles/git-hooks/pre-push')], cwd=self.root, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
