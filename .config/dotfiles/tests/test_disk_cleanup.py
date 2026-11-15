import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/disk-cleanup.sh'
PATH_LINE = 'export PATH="$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"'
OLD = time.time() - 3 * 86400


class DiskCleanupTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.calls = self.root / 'calls'
        self.clones = self.root / 'X/com.google.Chrome.code_sign_clone'
        self.clones.mkdir(parents=True)
        self.tracked = self.root / 'state/tracked-configs'
        self.tracked.mkdir(parents=True)
        (self.tracked / 'docs').symlink_to(Path.home() / 'Documents/x/mise.toml')
        (self.tracked / 'repo').symlink_to(Path.home() / 'ghq/x/mise.toml')
        for tool in ('brew', 'mise', 'npm', 'uv', 'docker'):
            self.fake(tool, 'echo "%s $*" >> "$CALLS"\n[[ "%s $*" != "$FAILURE" ]] || exit 1\n'
                            '[[ "%s $1" != "docker info" || "$DOCKER_UP" == 1 ]]\n' % (tool, tool, tool))
        # Real lsof: `-t -p PID` prints PID; `-t -- FILE...` prints processes that map them.
        self.fake('lsof', '[[ "$2" == -p ]] && { echo "$3"; exit 0; }\n'
                          'for f in "${@:3}"; do [[ -n "$IN_USE" && "$f" -ef "$IN_USE" ]] && { echo 42; exit 0; }; done\nexit 1\n')
        self.fake('df', 'printf "Filesystem Size Used Avail\\n/dev/x 1Ti 1Gi 9Gi\\n"\n')

    def fake(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def clone(self, name, old=True):
        path = self.clones / ('code_sign_clone.' + name)
        (path / 'Google Chrome.app.bundle/Contents/MacOS').mkdir(parents=True)
        (path / 'Google Chrome.app.bundle/Contents/MacOS/Google Chrome').write_text(name)
        if old:
            os.utime(path, (OLD, OLD))
        return path

    def run_cleanup(self, failure='', docker_up=False, in_use='', lsof_works=True):
        if not lsof_works:
            self.fake('lsof', 'exit 1\n')
        script = self.root / 'cleanup.sh'
        source = SCRIPT.read_text()
        self.assertIn(PATH_LINE, source)
        script.write_text(source.replace(PATH_LINE, 'export PATH="%s:/usr/bin:/bin"' % self.bin))
        env = {**os.environ, 'CALLS': str(self.calls), 'FAILURE': failure, 'DOCKER_UP': '1' if docker_up else '0',
               'IN_USE': in_use, 'MISE_STATE_DIR': str(self.root / 'state'),
               'DISK_CLEANUP_CHROME_ROOT': str(getattr(self, 'chrome_root', self.root / 'X')), 'DISK_CLEANUP_STEP_TIMEOUT': '20'}
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True, timeout=60)
        self.output = result.stdout
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return result.returncode, calls

    def test_normal_run_cleans_caches_without_touching_docker_when_stopped(self):
        code, calls = self.run_cleanup()
        self.assertEqual(code, 0, self.output)
        self.assertEqual(calls, ['brew cleanup -s --prune=all', 'mise cache clear', 'mise prune --yes',
                                 'npm cache clean --force', 'uv cache prune', 'docker info'])
        self.assertIn('Disk cleanup exit=0 free=9Gi', self.output)

    def test_running_docker_drops_only_dangling_images_and_old_build_cache(self):
        code, calls = self.run_cleanup(docker_up=True)
        self.assertEqual(code, 0)
        self.assertEqual(calls[-2:], ['docker image prune -f', 'docker builder prune -f --filter until=720h'])
        self.assertFalse(any('volume' in c or 'system prune' in c for c in calls))

    def test_stale_chrome_copies_go_but_running_and_recent_ones_stay(self):
        stale = self.clone('stale')
        running = self.clone('running')
        recent = self.clone('recent', old=False)
        code, _ = self.run_cleanup(in_use=str(running / 'Google Chrome.app.bundle/Contents/MacOS/Google Chrome'))
        self.assertEqual(code, 0)
        self.assertFalse(stale.exists())
        self.assertTrue(running.exists())
        self.assertTrue(recent.exists())

    def test_copy_hard_linked_to_running_chrome_is_kept(self):
        # Copies share the running executable by hard link; match by file, not by path.
        installed = self.root / 'Google Chrome'
        installed.write_text('chrome')
        older = self.clone('older')
        linked = self.clone('linked')
        exe = linked / 'Google Chrome.app.bundle/Contents/MacOS/Google Chrome'
        exe.unlink()
        os.link(installed, exe)
        code, _ = self.run_cleanup(in_use=str(installed))
        self.assertEqual(code, 0)
        self.assertTrue(linked.exists())
        self.assertFalse(older.exists())

    def test_unknown_layout_is_left_alone(self):
        odd = self.clones / 'code_sign_clone.odd'
        odd.mkdir()
        os.utime(odd, (OLD, OLD))
        self.run_cleanup()
        self.assertTrue(odd.exists())

    def test_unknown_open_files_keep_every_chrome_copy(self):
        stale = self.clone('stale')
        code, calls = self.run_cleanup(lsof_works=False)
        self.assertNotEqual(code, 0)
        self.assertTrue(stale.exists())
        self.assertIn('brew cleanup -s --prune=all', calls)

    def test_one_failure_does_not_stop_later_steps(self):
        code, calls = self.run_cleanup(failure='mise cache clear')
        self.assertNotEqual(code, 0)
        self.assertIn('Step failed: mise cache clear', self.output)
        self.assertIn('npm cache clean --force', calls)
        self.assertIn('Disk cleanup exit=1', self.output)

    def test_protected_mise_configs_are_forgotten_before_prune(self):
        self.run_cleanup()
        self.assertEqual(sorted(x.name for x in self.tracked.iterdir()), ['repo'])


if __name__ == '__main__':
    unittest.main()
