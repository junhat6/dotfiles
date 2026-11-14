from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import converge  # noqa: E402

DONE = subprocess.CompletedProcess([], 0, '', '')


class NotifyTest(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(converge, 'host', return_value='mini')
        patcher.start()
        self.addCleanup(patcher.stop)
        self.sent = []

    def notify(self, state, issues, now):
        return converge.notify(state, issues, self.sent.append, now=now)

    def test_new_issue_once_then_daily(self):
        state = {}
        self.assertTrue(self.notify(state, {'a': 'sudo needed'}, 1000))
        self.assertFalse(self.notify(state, {'a': 'sudo needed'}, 1000 + 3600))
        self.assertTrue(self.notify(state, {'a': 'sudo needed'}, 1000 + converge.DAY))
        self.assertEqual(len(self.sent), 2)
        self.assertIn('人の操作が必要です', self.sent[0])

    def test_changed_text_is_resent(self):
        state = {}
        self.notify(state, {'a': 'x'}, 1000)
        self.assertTrue(self.notify(state, {'a': 'y'}, 1001))

    def test_resolved_is_announced_once(self):
        state = {}
        self.notify(state, {'a': 'x'}, 1000)
        self.assertTrue(self.notify(state, {}, 1001))
        self.assertIn('解消しました', self.sent[-1])
        self.assertFalse(self.notify(state, {}, 1002))

    def test_failed_send_keeps_issue_due(self):
        state = {}
        with self.assertRaises(OSError):
            converge.notify(state, {'a': 'x'}, mock.Mock(side_effect=OSError('down')), now=1000)
        self.assertTrue(self.notify(state, {'a': 'x'}, 1001))


class HomebrewLogTest(unittest.TestCase):
    def issues(self, text, now=None):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'log'
            log.write_text(text)
            found = {}
            converge.homebrew_issues(found, log, now)
            return found

    def test_sudo_casks_are_listed(self):
        found = self.issues('[2026-11-14T04:00:05+0900] Homebrew maintenance started\n'
                            'Error: capsomnia: Failure while executing; `/usr/bin/sudo -u root`\n'
                            'Error: tailscale-app: Failure while executing; `/usr/bin/sudo -u root`\n'
                            '[2026-11-14T05:00:05+0900] Homebrew maintenance exit=1\n')
        self.assertIn('brew upgrade --cask capsomnia tailscale-app', found['homebrew:sudo'])

    def test_only_latest_run_counts(self):
        found = self.issues('[2026-11-13T04:00:05+0900] Homebrew maintenance started\n'
                            'Error: zoom: Failure while executing; `/usr/bin/sudo`\n'
                            '[2026-11-13T05:00:05+0900] Homebrew maintenance exit=1\n'
                            '[2026-11-14T04:00:05+0900] Homebrew maintenance started\n'
                            '[2026-11-14T05:00:05+0900] Homebrew maintenance exit=0\n')
        self.assertEqual(found, {})

    def test_unfinished_run_is_hung_after_six_hours(self):
        text = '[2026-11-13T04:00:02+0900] Homebrew maintenance started\nmise installing\n'
        started = 1794510002  # 2026-11-13T04:00:02+0900
        self.assertEqual(self.issues(text, started + 3600), {})
        self.assertIn('32 時間', self.issues(text, started + 32 * 3600)['homebrew:hung'])

    def test_timeout_is_reported(self):
        found = self.issues('[2026-11-14T04:00:05+0900] Homebrew maintenance started\n'
                            'Step timed out after 3600s: mise upgrade --global\n'
                            '[2026-11-14T05:00:05+0900] Homebrew maintenance exit=1\n')
        self.assertIn('mise upgrade', found['homebrew:timeout'])


class ServicesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.agents = root / 'LaunchAgents'
        self.agents.mkdir()
        self.app = root / 'Orca.app'
        self.app.mkdir()
        self.source = root / 'orca-autoupdate.py'
        self.source.write_text('new')
        self.copy = root / 'installed.py'
        services = [{'label': 'a.plain'},
                    {'label': 'b.orca', 'installer': 'install.py', 'installed_copy': self.copy,
                     'source': self.source, 'requires': self.app}]
        for target, value in (('AGENTS', self.agents), ('SERVICES', services)):
            patcher = mock.patch.object(converge, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        (self.agents / 'a.plain.plist').write_text('v1')
        self.calls = []

    def run_converge(self, state, loaded=(), disabled=()):
        issues = {}

        def run(*cmd):
            self.calls.append(cmd)
            return DONE
        converge.converge_services(state, issues, set(disabled), lambda label: label in loaded, run)
        return issues

    def test_missing_jobs_are_registered(self):
        issues = self.run_converge({})
        self.assertEqual(issues, {})
        self.assertTrue(any(c[:2] == ('launchctl', 'bootstrap') for c in self.calls))
        self.assertTrue(any(c[-1].endswith('install.py') for c in self.calls))

    def test_loaded_jobs_are_left_alone(self):
        self.copy.write_text('new')
        self.run_converge({}, loaded={'a.plain', 'b.orca'})
        self.assertEqual(self.calls, [])

    def test_stale_installed_copy_is_refreshed_without_restart(self):
        self.copy.write_text('old')
        self.run_converge({}, loaded={'a.plain', 'b.orca'})
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(self.calls[0][-1].endswith('install.py'))

    def test_disabled_and_absent_app_are_skipped(self):
        self.app.rmdir()
        self.run_converge({}, disabled={'a.plain'})
        self.assertEqual(self.calls, [])

    def test_changed_plist_asks_for_reload(self):
        state = {}
        self.copy.write_text('new')
        self.run_converge(state, loaded={'a.plain', 'b.orca'})
        (self.agents / 'a.plain.plist').write_text('v2')
        issues = self.run_converge(state, loaded={'a.plain', 'b.orca'})
        self.assertIn('dotfiles services reload a.plain', issues['a.plain:reload'])
        self.assertEqual(self.calls, [])

    def test_registration_failure_is_an_issue(self):
        issues = {}
        failed = subprocess.CompletedProcess([], 5, '', 'Bootstrap failed: 5')
        converge.converge_services({}, issues, {'b.orca'}, lambda label: False, lambda *cmd: failed)
        self.assertIn('Bootstrap failed', issues['a.plain:register'])


if __name__ == '__main__':
    unittest.main()
