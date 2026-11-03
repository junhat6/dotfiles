import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/homebrew-update.sh'

class HomebrewUpdateTest(unittest.TestCase):
    def run_update(self, failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            brew = root / 'brew'
            brew.write_text('#!/bin/bash\necho "$*" >> "$CALLS"\n[[ "$*" != "$FAILURE" ]]\n')
            brew.chmod(0o755)
            mise = root / 'mise'
            mise.write_text('#!/bin/bash\necho "mise $*" >> "$CALLS"\n[[ "mise $*" != "$FAILURE" ]]\n')
            mise.chmod(0o755)
            script = root / 'update.sh'
            script.write_text(SCRIPT.read_text().replace('export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"', 'export PATH="' + directory + ':/usr/bin:/bin"'))
            result = subprocess.run(['bash', str(script)], env={**os.environ, 'CALLS':str(root/'calls'), 'FAILURE':failure}, capture_output=True)
            return result.returncode, (root/'calls').read_text().splitlines()

    def test_normal(self):
        code, calls = self.run_update()
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['update', 'upgrade --formula', 'upgrade --cask --greedy --no-quit', 'mise upgrade --global --yes --no-prune'])

    def test_update_failure_stops_upgrades(self):
        code, calls = self.run_update('update')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, ['update', 'mise upgrade --global --yes --no-prune'])

    def test_formula_failure_still_checks_apps_and_reports_failure(self):
        code, calls = self.run_update('upgrade --formula')
        self.assertNotEqual(code, 0)
        self.assertIn('upgrade --cask --greedy --no-quit', calls)
        self.assertEqual(calls[-1], 'mise upgrade --global --yes --no-prune')

    def test_app_failure_still_updates_mise(self):
        code, calls = self.run_update('upgrade --cask --greedy --no-quit')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls[-1], 'mise upgrade --global --yes --no-prune')

    def test_mise_failure_is_reported(self):
        code, calls = self.run_update('mise upgrade --global --yes --no-prune')
        self.assertNotEqual(code, 0)
