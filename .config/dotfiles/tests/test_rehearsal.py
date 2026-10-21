import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('rehearsal', ROOT / '.config/dotfiles/scripts/rehearse_setup.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RehearsalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = {name: MODULE.rehearse(ROOT / 'setup.sh', name) for name in
                       ('fresh', 'existing', 'auth-loss', 'late-input', 'package-failure')}

    def test_initial_user_attention_is_grouped_before_bulk(self):
        result = self.results['fresh']
        self.assertEqual((result['exit_code'], result['user_operations'], result['attention_groups']), (0, 5, 2))
        self.assertEqual(result['user_operations_after_bulk'], 0)

    def test_existing_install_needs_no_synthetic_approval(self):
        result = self.results['existing']
        self.assertEqual((result['exit_code'], result['user_operations']), (0, 0))

    def test_lost_authentication_stops_without_late_prompt(self):
        result = self.results['auth-loss']
        self.assertNotEqual(result['exit_code'], 0)
        self.assertEqual(result['user_operations_after_bulk'], 0)

    def test_unexpected_stdin_fails_instead_of_waiting(self):
        result = self.results['late-input']
        self.assertEqual(result['exit_code'], 23)
        self.assertEqual(result['user_operations_after_bulk'], 0)

    def test_installer_failure_is_preserved(self):
        self.assertEqual(self.results['package-failure']['exit_code'], 17)

    def test_all_paths_revoke_authentication_and_release_lock(self):
        for result in self.results.values():
            with self.subTest(scenario=result['scenario']):
                self.assertTrue(result['auth_revoked'])
                self.assertTrue(result['lock_released'])
