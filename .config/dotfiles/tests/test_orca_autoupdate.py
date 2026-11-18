import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updater', Path(__file__).resolve().parents[1] / 'scripts/orca-autoupdate.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


def status(state, version=None, app='1.4.261'):
    return {'appVersion': app, 'status': {'state': state, 'version': version}}


class FakeOrca:
    """Answers RPCs from a scripted list of updater.getStatus replies."""

    def __init__(self, statuses, accepted=True):
        self.statuses = list(statuses)
        self.accepted = accepted
        self.calls = []

    def __call__(self, method, params=None):
        self.calls.append((method, params))
        if method == 'updater.getStatus':
            return self.statuses.pop(0) if len(self.statuses) > 1 else self.statuses[0]
        if method == 'updater.install':
            return {'accepted': self.accepted}
        return None

    def methods(self):
        return [method for method, _ in self.calls]


class RunTests(unittest.TestCase):
    def run_with(self, orca):
        with patch.object(u, 'rpc', orca), patch.object(u.time, 'sleep'):
            u.run()

    def test_up_to_date_does_nothing(self):
        orca = FakeOrca([status('not-available')])
        self.run_with(orca)
        self.assertEqual(orca.methods(), ['updater.check', 'updater.getStatus'])

    def test_checks_stable_releases_only(self):
        orca = FakeOrca([status('not-available')])
        self.run_with(orca)
        self.assertEqual(orca.calls[0][1], {'includePrerelease': False, 'includePerfPrerelease': False})

    def test_available_update_is_downloaded_once_then_installed(self):
        orca = FakeOrca([status('checking'), status('available', '1.4.262'),
                         status('downloading', '1.4.262'), status('available', '1.4.262'),
                         status('downloaded', '1.4.262')])
        self.run_with(orca)
        self.assertEqual(orca.methods().count('updater.download'), 1)
        self.assertEqual(orca.methods()[-1], 'updater.install')

    def test_never_stops_the_app_itself(self):
        orca = FakeOrca([status('downloaded', '1.4.262')])
        with patch.object(u.os, 'kill') as kill, patch.object(u, 'rpc', orca), patch.object(u.time, 'sleep'):
            u.run()
        kill.assert_not_called()

    def test_updater_error_raises(self):
        with self.assertRaises(RuntimeError):
            self.run_with(FakeOrca([status('error')]))

    def test_rejected_install_raises(self):
        with self.assertRaises(RuntimeError):
            self.run_with(FakeOrca([status('downloaded', '1.4.262')], accepted=False))

    def test_gives_up_after_deadline(self):
        clock = iter(range(0, 10 ** 6, 100))
        with patch.object(u.time, 'monotonic', lambda: next(clock)), self.assertRaises(RuntimeError):
            self.run_with(FakeOrca([status('downloading', '1.4.262')]))


if __name__ == '__main__':
    unittest.main()
