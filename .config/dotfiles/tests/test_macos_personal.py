import copy
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/macos-personal.py'
spec = importlib.util.spec_from_file_location('macos_personal', SCRIPT)
mac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mac)


class ProfileTests(unittest.TestCase):
    def test_repeat_apply_and_restore(self):
        initial = {'NSGlobalDomain': {'KeyRepeat': 6, 'unrelated': 'keep'},
                   'com.apple.dock': {'persistent-apps': [{'tile-data': {'custom': b'bytes'}}],
                                      'autohide': False, 'persistent-others': ['Downloads']}}
        current = copy.deepcopy(initial)
        def write(domain, key, value):
            current[domain][key] = copy.deepcopy(value)
        def run(args, **kwargs):
            if args[0:2] == ['defaults', 'delete']:
                del current[args[2]][args[3]]
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as state, patch.dict(os.environ, {'XDG_STATE_HOME': state}), \
                patch.object(mac.sys, 'platform', 'darwin'), patch.object(mac.os, 'geteuid', return_value=501), \
                patch.object(mac, 'read_domain', side_effect=lambda d: copy.deepcopy(current[d])), \
                patch.object(mac, 'power_settings'), patch.object(mac, 'ac_sleep_settings'), patch.object(mac, 'write_value', side_effect=write), patch.object(mac.subprocess, 'run', side_effect=run):
            for action in ('apply', 'apply'):
                with patch.object(sys, 'argv', ['profile', action]):
                    mac.main()
            self.assertEqual(current['NSGlobalDomain']['KeyRepeat'], 1)
            self.assertEqual(current['NSGlobalDomain']['InitialKeyRepeat'], 15)
            self.assertFalse(current['com.apple.dock']['show-recents'])
            self.assertEqual(current['com.apple.dock']['persistent-others'], ['Downloads'])
            with patch.object(sys, 'argv', ['profile', 'restore']):
                mac.main()
            self.assertEqual(current, initial)

    @unittest.skipUnless(sys.platform == 'darwin', 'real macOS defaults serialization')
    def test_defaults_roundtrip_nested_dock_and_scalar_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            domain = str(Path(temporary) / 'preferences')
            values = {'tiles': [{'tile-data': {'file-data': {'_CFURLString': 'file:///System/Applications/Launchpad.app/', '_CFURLStringType': 15}}, 'tile-type': 'file-tile'}], 'bool': False, 'integer': 15}
            for key, value in values.items():
                mac.write_value(domain, key, value)
            self.assertEqual(mac.read_domain(domain), values)


class PowerTests(unittest.TestCase):
    def test_source_parser_handles_desktop_without_battery(self):
        with patch.object(mac.subprocess, 'check_output', return_value='AC Power:\n displaysleep 15\n sleep 1\n'):
            self.assertEqual(mac.read_power(), {'AC Power': 15})

    def test_apply_repeat_restore_and_noninteractive_auth(self):
        current = {'Battery Power': 2, 'AC Power': 10}
        commands = []
        def run(args, **kwargs):
            commands.append(args)
            source = next(source for source, flag in mac.POWER_FLAGS.items() if flag in args)
            current[source] = int(args[-1])
        with tempfile.TemporaryDirectory() as temporary, patch.object(mac, 'read_power', side_effect=lambda: dict(current)), \
                patch.object(mac.subprocess, 'run', side_effect=run), patch.dict(os.environ, {'DOTFILES_SETUP_NONINTERACTIVE': '1'}):
            state = Path(temporary)
            mac.power_settings('apply', state)
            self.assertEqual(current, {'Battery Power': 10, 'AC Power': 0})
            self.assertEqual(len(commands), 2)
            self.assertTrue(all(command[1] == '-n' for command in commands))
            mac.power_settings('apply', state)
            self.assertEqual(len(commands), 2)
            mac.power_settings('restore', state)
            self.assertEqual(current, {'Battery Power': 2, 'AC Power': 10})
            self.assertTrue(all(command[-2] == 'displaysleep' for command in commands))

    def test_legacy_backup_restore_does_not_touch_power(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(mac, 'read_power', return_value={'AC Power': 0}), patch.object(mac.subprocess, 'run') as run:
            mac.power_settings('restore', Path(temporary))
            run.assert_not_called()


class ACSleepTests(unittest.TestCase):
    def test_apply_restore_is_ac_only_and_preserves_first_backup(self):
        current = {'Battery Power': 1, 'AC Power': 15}
        commands = []
        def run(args, **kwargs):
            commands.append(args)
            self.assertEqual(args[1:5], ['-n', '/usr/bin/pmset', '-c', 'sleep'])
            current['AC Power'] = int(args[-1])
        with tempfile.TemporaryDirectory() as temporary, patch.object(mac, 'read_power', side_effect=lambda setting: dict(current)), patch.object(mac.subprocess, 'run', side_effect=run), patch.dict(os.environ, {'DOTFILES_SETUP_NONINTERACTIVE': '1'}):
            state = Path(temporary)
            mac.ac_sleep_settings('apply', state)
            mac.ac_sleep_settings('apply', state)
            self.assertEqual(current, {'Battery Power': 1, 'AC Power': 0})
            self.assertEqual(len(commands), 1)
            mac.ac_sleep_settings('restore', state)
            self.assertEqual(current, {'Battery Power': 1, 'AC Power': 15})

    def test_old_backups_do_not_restore_unmanaged_sleep(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(mac, 'read_power', return_value={'AC Power': 0}), patch.object(mac.subprocess, 'run') as run:
            mac.ac_sleep_settings('restore', Path(temporary))
            run.assert_not_called()
