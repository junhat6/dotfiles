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
                patch.object(mac, 'write_value', side_effect=write), patch.object(mac.subprocess, 'run', side_effect=run):
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
