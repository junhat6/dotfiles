#!/usr/bin/python3
"""Update Orca to the latest stable release through Orca's own built-in updater.

Run every three hours by the LaunchAgent com.junhat6.orca-autoupdate on the
always-on Mac mini, where nobody presses "Restart to update". This only does
what that button does: check, download, then ask Orca to install. Quitting,
replacing and relaunching the app are left entirely to Orca.
"""
import json
import logging
import os
from pathlib import Path
import socket
import time
import uuid

DATA = Path.home() / 'Library/Application Support/orca'
POLL_SECONDS = 5
DEADLINE_SECONDS = 900


def rpc(method, params=None):
    """Call Orca's local runtime socket (the same one the orca CLI uses)."""
    runtime = json.loads((DATA / 'orca-runtime.json').read_text())
    endpoint = next(t['endpoint'] for t in runtime['transports'] if t['kind'] == 'unix')
    if Path(endpoint).stat().st_uid != os.getuid():
        raise RuntimeError('Unexpected socket owner')
    request_id = str(uuid.uuid4())
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(30)
        client.connect(endpoint)
        client.sendall((json.dumps({'id': request_id, 'authToken': runtime['authToken'],
                                    'method': method, 'params': params}) + '\n').encode())
        with client.makefile('rb') as stream:
            for line in stream:
                response = json.loads(line)
                if response.get('id') == request_id:
                    if response.get('ok') is not True:
                        raise RuntimeError('Orca rejected ' + method)
                    return response['result']
    raise RuntimeError('No response to ' + method)


def run():
    rpc('updater.check', {'includePrerelease': False, 'includePerfPrerelease': False})
    download_requested = False
    deadline = time.monotonic() + DEADLINE_SECONDS
    while time.monotonic() < deadline:
        snapshot = rpc('updater.getStatus')
        status = snapshot['status']
        state = status['state']
        if state == 'not-available':
            logging.info('Orca %s is up to date', snapshot['appVersion'])
            return
        if state == 'error':
            raise RuntimeError('Built-in updater reported an error')
        if state == 'available' and not download_requested:
            logging.info('Downloading Orca %s', status.get('version'))
            rpc('updater.download')
            download_requested = True
        elif state == 'downloaded':
            logging.info('Installing Orca %s (was %s)', status.get('version'), snapshot['appVersion'])
            if rpc('updater.install').get('accepted') is not True:
                raise RuntimeError('Install not accepted')
            return
        time.sleep(POLL_SECONDS)
    raise RuntimeError('Update not ready within %d seconds' % DEADLINE_SECONDS)


def main():
    # launchd sends stdout/stderr to ~/Library/Logs/OrcaAutoUpdate/launchd.log.
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    try:
        run()
    except Exception as error:
        # Never log credentials or raw RPC responses. The next scheduled run retries.
        logging.error('%s: %s', type(error).__name__, error)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
