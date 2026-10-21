"""Exercise the real Bash runner in a PTY, with OS/package boundaries replaced.

No real sudo, Homebrew, downloads, app launches or HOME settings are touched.
"""
import json
import os
from pathlib import Path
import pty
import select
import signal
import shlex
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[3]

STUB = r'''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
name=Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps([name, *args])+'\n')
if name == 'sudo':
    if args == ['-n', '-v'] and os.environ.get('LOSE_AUTH'):
        sys.exit(1)
elif name == 'brew':
    assert os.environ['HOMEBREW_SUDO_CHECKED']=='1'
    assert Path(os.environ['SUDO_ASKPASS']).is_file()
    if args == ['install', 'yadm', 'mise']:
        time.sleep(0.25)
        if os.environ.get('FAIL_FOUNDATION'): sys.exit(17)
elif name == 'yadm':
    if args == ['rev-parse', '--git-dir']: print('.git')
    elif args == ['rev-parse', '--show-toplevel']: print(os.environ['HOME'])
    elif args == ['branch', '--show-current']: print('main')
    elif args == ['remote', 'get-url', 'origin']: print('https://github.com/junhat6/dotfiles.git')
    elif args[0] == 'show': print('import sys\nprint("local helper: " + sys.argv[1])')
elif name == 'mise':
    if args == ['which', 'gh']: print(Path(sys.argv[0]).with_name('gh'))
'''


@unittest.skipUnless(os.uname().sysname == 'Darwin' and os.geteuid() != 0, 'macOS non-root PTY runner')
class SetupSession(unittest.TestCase):
    def invoke(self, stop_signal=None, **extra):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / 'home'
            home.mkdir()
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            for name in ('sudo', 'brew', 'yadm', 'mise', 'gh', 'open'):
                target = bin_dir / name
                target.write_text(STUB)
                target.chmod(0o700)
            local = home / '.local/bin/dotfiles'
            local.parent.mkdir(parents=True)
            local.write_text('#!/bin/bash\nexit 0\n')
            local.chmod(0o700)
            install = home / '.config/dotfiles/install.sh'
            install.parent.mkdir(parents=True)
            install.write_text('#!/bin/bash\nexit 0\n')
            # Substitute platform boundaries and accelerate only the timer.
            source = (SOURCE / 'setup.sh').read_text()
            source = source.replace('/usr/bin/sudo', shlex.quote(str(bin_dir / 'sudo')))
            source = source.replace('/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:', '')
            source = source.replace('sleep 30', 'sleep 0.05')
            script = root / 'setup.sh'
            script.write_text(source)
            calls = root / 'calls.jsonl'
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'),
                       PATH=str(bin_dir) + ':/usr/bin:/bin:/usr/sbin:/sbin', CALLS=str(calls), **extra)
            master, slave = pty.openpty()
            process = subprocess.Popen(['bash', str(script), '--profile', 'none', '--no-ui'],
                                       stdin=slave, stdout=slave, stderr=slave, env=env)
            os.close(slave)
            try:
                os.set_blocking(master, False)
                chunks = []
                started = time.monotonic()
                deadline = time.monotonic() + 20
                while process.poll() is None or select.select([master], [], [], 0)[0]:
                    if stop_signal and time.monotonic() - started > 0.15:
                        process.send_signal(stop_signal)
                        stop_signal = None
                    if time.monotonic() > deadline:
                        self.fail('PTY runner timed out:\n' + b''.join(chunks).decode(errors='replace') + '\nCalls:\n' + calls.read_text())
                    if not select.select([master], [], [], 0.1)[0]:
                        continue
                    try:
                        chunk = os.read(master, 65536)
                        if not chunk: break
                        chunks.append(chunk)
                    except BlockingIOError:
                        continue
                    except OSError:
                        break
                code = process.wait(timeout=2)
                stdout = b''.join(chunks).decode(errors='replace')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                os.close(master)
            records = [json.loads(line) for line in calls.read_text().splitlines()]
            state = home / 'state/dotfiles/setup'
            current = (state / 'current').read_text()
            self.assertFalse((state / 'lock').exists(), stdout)
            sudo = [row[1:] for row in records if row[0] == 'sudo']
            self.assertEqual(sudo.count(['-v']), 1, stdout)
            self.assertIn(['-k'], sudo, stdout)
            return code, stdout, records, current

    def test_whole_runner_renews_and_revokes_without_late_auth_prompts(self):
        code, stdout, records, current = self.invoke()
        self.assertEqual(code, 2, stdout)  # --no-ui explicitly leaves an action outstanding
        self.assertIn(['sudo', '-n', '-v'], records)
        self.assertIn('app-permissions', current)
        self.assertTrue(any(row[:3] == ['brew', 'bundle', 'install'] for row in records))

    def test_package_failure_preserves_exit_code_and_revokes_auth(self):
        code, stdout, records, current = self.invoke(FAIL_FOUNDATION='1')
        self.assertEqual(code, 17, stdout)
        self.assertIn('stopped:17', current)
        self.assertFalse(any(row[0] == 'gh' for row in records))

    def test_lost_auth_stops_before_later_packages_instead_of_prompting(self):
        code, stdout, records, current = self.invoke(LOSE_AUTH='1')
        self.assertEqual(code, 1, stdout)
        self.assertIn('Authentication renewal failed', stdout)
        self.assertFalse(any(row[:3] == ['brew', 'install', '--cask'] for row in records))

    def test_termination_revokes_auth_and_releases_the_lock(self):
        code, stdout, records, current = self.invoke(stop_signal=signal.SIGTERM)
        self.assertEqual(code, 143, stdout)
        self.assertIn('stopped:143', current)


if __name__ == '__main__':
    unittest.main()
