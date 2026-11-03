import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updater', Path(__file__).resolve().parents[1] / 'scripts/orca-autoupdate.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


def snapshot(version='1.4.245', state='not-available'):
    return {'appVersion': version, 'support': {'automatic': True, 'installMode': 'interactive'},
            'status': {'state': state, 'source': 'release'}}


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.p = patch.object(u, 'BASE', self.base)
        self.p.start()
        self.addCleanup(self.p.stop)

    def pending(self, at=0):
        u.save('last-update.json', {'state': 'install-requested', 'target': '1.4.230', 'at': at})

    def test_interrupted_update_recovers_without_claiming_session_survival(self):
        self.pending()
        with patch.object(u, 'rpc', return_value=snapshot()) as rpc:
            u.run()
        saved = json.loads((self.base / 'last-update.json').read_text())
        self.assertEqual(saved['state'], 'version-confirmed')
        self.assertNotIn('preservedLocalTerminals', saved)
        self.assertIn('updater.check', [c.args[0] for c in rpc.call_args_list])

    def test_recent_pending_install_does_not_repeat_install(self):
        self.pending(at=u.time.time())
        with patch.object(u, 'rpc', return_value=snapshot('1.4.229')) as rpc:
            u.run()
        self.assertEqual(rpc.call_count, 1)

    def test_old_failed_install_retries(self):
        self.pending()
        with patch.object(u, 'rpc', return_value=snapshot('1.4.229')) as rpc:
            u.run()
        self.assertIn('updater.check', [c.args[0] for c in rpc.call_args_list])
        self.assertFalse((self.base / 'PAUSED').exists())

    def test_inspect_does_not_change_pending_record(self):
        self.pending()
        before = (self.base / 'last-update.json').read_bytes()
        with patch.object(u, 'rpc', return_value=snapshot()), patch.object(u, 'daemon_snapshot', return_value={}), patch.object(u, 'terminal_snapshot', return_value={}):
            with patch('builtins.print'):
                u.run(inspect_only=True)
        self.assertEqual((self.base / 'last-update.json').read_bytes(), before)
        self.assertFalse((self.base / 'last-attempt.json').exists())

    def test_manual_pause_is_respected(self):
        (self.base / 'PAUSED').touch()
        with patch.object(u, 'rpc') as rpc:
            u.run()
        rpc.assert_not_called()

    def test_changed_daemon_inventory_with_surviving_terminals_succeeds(self):
        downloaded = snapshot('1.4.245', 'downloaded')
        downloaded['status']['version'] = '1.4.247'
        replies = [snapshot(), None, downloaded, {'accepted': True}, snapshot('1.4.247')]
        with patch.object(u, 'rpc', side_effect=replies), patch.object(u, 'daemon_snapshot', return_value={123: 'old daemon'}), patch.object(u, 'process_identity', return_value=None), patch.object(u, 'terminal_snapshot', return_value={'pty': 'same-incarnation'}), patch.object(u.time, 'sleep'):
            u.run()
        result = json.loads((self.base / 'last-update.json').read_text())
        self.assertEqual(result['state'], 'verified')
        self.assertFalse(result['sameDaemons'])
        self.assertEqual(result['preservedLocalTerminals'], 1)
        self.assertFalse((self.base / 'PAUSED').exists())

    def test_prereleases_are_refused(self):
        with self.assertRaises(RuntimeError):
            u.stable_version('1.4.246-rc.1')


if __name__ == '__main__':
    unittest.main()
