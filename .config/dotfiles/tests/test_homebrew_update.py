import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/homebrew-update.sh'

class HomebrewUpdateTest(unittest.TestCase):
    def run_update(self, failure='', outdated='amical\nstablyai/orca/orca', orca_running=False, mise_hangs=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            brew = root / 'brew'
            brew.write_text('#!/bin/bash\necho "$*" >> "$CALLS"\n[[ "$*" != "$FAILURE" ]] || exit 1\n[[ "$1" == outdated ]] && printf "%b" "$OUTDATED"\nexit 0\n')
            brew.chmod(0o755)
            ps = root / 'ps'
            ps.write_text('#!/bin/bash\necho /usr/bin/login\n[[ "$ORCA_RUNNING" == 1 ]] && echo /Applications/Orca.app/Contents/MacOS/Orca\nexit 0\n')
            ps.chmod(0o755)
            mise = root / 'mise'
            mise.write_text('#!/bin/bash\necho "mise $*" >> "$CALLS"\n[[ "$MISE_HANGS" == 1 ]] && sleep 60\n[[ "mise $*" != "$FAILURE" ]]\n')
            mise.chmod(0o755)
            script = root / 'update.sh'
            script.write_text(SCRIPT.read_text().replace('export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"', 'export PATH="' + directory + ':/usr/bin:/bin"'))
            result = subprocess.run(['bash', str(script)], env={**os.environ, 'CALLS':str(root/'calls'), 'FAILURE':failure, 'OUTDATED':outdated, 'MISE_HANGS':'1' if mise_hangs else '0', 'HOMEBREW_UPDATE_STEP_TIMEOUT':'2', 'HOMEBREW_UPDATE_KILL_GRACE':'1', 'ORCA_RUNNING':'1' if orca_running else '0'}, capture_output=True, timeout=30)
            self.output = result.stdout.decode()
            return result.returncode, (root/'calls').read_text().splitlines()

    def test_normal(self):
        code, calls = self.run_update()
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['update', 'upgrade --formula', 'outdated --cask --greedy --quiet', 'upgrade --cask --greedy --no-quit amical stablyai/orca/orca', 'mise upgrade --global --yes --no-prune'])

    def test_update_failure_stops_upgrades(self):
        code, calls = self.run_update('update')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, ['update', 'mise upgrade --global --yes --no-prune'])

    def test_formula_failure_still_checks_apps_and_reports_failure(self):
        code, calls = self.run_update('upgrade --formula')
        self.assertNotEqual(code, 0)
        self.assertIn('upgrade --cask --greedy --no-quit amical stablyai/orca/orca', calls)
        self.assertEqual(calls[-1], 'mise upgrade --global --yes --no-prune')

    def test_app_failure_still_updates_mise(self):
        code, calls = self.run_update('upgrade --cask --greedy --no-quit amical stablyai/orca/orca')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls[-1], 'mise upgrade --global --yes --no-prune')

    def test_mise_failure_is_reported(self):
        code, calls = self.run_update('mise upgrade --global --yes --no-prune')
        self.assertNotEqual(code, 0)

    def test_running_orca_is_not_replaced(self):
        code, calls = self.run_update(orca_running=True)
        self.assertEqual(code, 0)
        self.assertIn('upgrade --cask --greedy --no-quit amical', calls)
        self.assertFalse(any('orca' in c for c in calls if c.startswith('upgrade --cask')))

    def test_only_running_orca_outdated_skips_cask_upgrade(self):
        code, calls = self.run_update(outdated='stablyai/orca/orca', orca_running=True)
        self.assertEqual(code, 0)
        self.assertFalse(any(c.startswith('upgrade --cask') for c in calls))

    def test_outdated_failure_is_reported(self):
        code, calls = self.run_update('outdated --cask --greedy --quiet')
        self.assertNotEqual(code, 0)
        self.assertFalse(any(c.startswith('upgrade --cask') for c in calls))
        self.assertEqual(calls[-1], 'mise upgrade --global --yes --no-prune')

    def test_hung_step_is_stopped_and_reported(self):
        code, calls = self.run_update(mise_hangs=True)
        self.assertNotEqual(code, 0)
        self.assertIn('Step timed out after 2s: mise upgrade', self.output)
        self.assertIn('Homebrew maintenance exit=1', self.output)
