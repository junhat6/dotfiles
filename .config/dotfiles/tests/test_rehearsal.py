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
                       ('fresh', 'existing', 'auth-loss', 'late-input', 'package-failure', 'macos-auth-loss', 'macos-write-failure')}

    def test_only_permission_apps_block_early_user_operations(self):
        source = (ROOT / 'setup.sh').read_text()
        apps = source.index('run permission-apps brew install --cask karabiner-elements hammerspoon')
        foundation = source.index('run foundation brew install yadm mise')
        checkpoint = source.index('    read -r _confirmation')
        vaults = source.index('then run vaults ')
        packages = source.index('run packages brew bundle')
        self.assertLess(apps, foundation)
        self.assertLess(checkpoint, vaults)
        self.assertLess(vaults, packages)
        self.assertNotIn('brew install --cask google-chrome', source)
        verification = source.index('run early-app-verification ')
        launch = source.index('open -a "$app"')
        self.assertLess(foundation, verification)
        self.assertLess(verification, launch)
        self.assertLess(launch, source.index('run github-tool '))
        self.assertLess(packages, source.index('run app-verification '))

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


    def test_real_profile_applies_all_settings_without_late_input(self):
        for name in ('fresh', 'existing'):
            result = self.results[name]
            with self.subTest(scenario=name):
                self.assertEqual(result['exit_code'], 0)
                self.assertEqual(result['settings']['NSGlobalDomain'], {'KeyRepeat': 1, 'InitialKeyRepeat': 15})
                dock = result['settings']['com.apple.dock']
                self.assertTrue(dock['autohide'])
                self.assertFalse(dock['show-recents'])
                self.assertEqual(dock['persistent-others'], ['Downloads'])
                urls = [tile['tile-data']['file-data']['_CFURLString'] for tile in dock['persistent-apps']]
                self.assertTrue(any('System%20Settings.app' in url for url in urls))
                self.assertEqual(result['power'], {'Battery Power': 10, 'AC Power': 0})
                calls = result['calls']
                writes = [call for call in calls if call[0] == 'sudo' and any('pmset' in arg for arg in call[2])]
                self.assertEqual(len(writes), 3)
                self.assertEqual(result['sleep'], {'Battery Power': 1, 'AC Power': 0})
                self.assertTrue(all(call[2][0] == '-n' for call in writes))
                self.assertEqual(result['user_operations_after_bulk'], 0)
                text = result['transcript']
                self.assertEqual(text.count('FINAL_RESTART:'), 1)
                self.assertLess(text.index('DONE report'), text.index('FINAL_RESTART:'))
                self.assertFalse(any(call[0] in ('reboot', 'shutdown', 'osascript') for call in calls))

    def test_profile_failures_stop_without_late_password_or_reboot_message(self):
        for name in ('macos-auth-loss', 'macos-write-failure'):
            result = self.results[name]
            with self.subTest(scenario=name):
                self.assertNotEqual(result['exit_code'], 0)
                self.assertEqual(result['user_operations_after_bulk'], 0)
                self.assertNotIn('FINAL_RESTART:', result['transcript'])


    def test_browser_preference_runs_after_app_installation_without_more_input(self):
        text = self.results['fresh']['transcript']
        self.assertLess(text.index('DONE packages'), text.index('START browser-preference'))
        self.assertLess(text.index('DONE app-verification'), text.index('START browser-preference'))
        self.assertLess(text.index('DONE browser-preference'), text.index('FINAL_RESTART:'))
        self.assertEqual(self.results['fresh']['user_operations_after_bulk'], 0)
