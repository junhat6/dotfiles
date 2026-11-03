#!/usr/bin/python3
"""Use Orca's own authenticated local updater; never replace/kill the app ourselves."""
import argparse
import fcntl
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import socket
import subprocess
import time
import uuid

BASE = Path(__file__).resolve().parent
DATA = Path.home() / 'Library/Application Support/orca'
LOG = Path.home() / 'Library/Logs/OrcaAutoUpdate'


def rpc(method, params=None):
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
            for _ in range(100):
                line = stream.readline(4 * 1024 * 1024)
                if not line:
                    raise RuntimeError('RPC connection closed')
                response = json.loads(line)
                if response.get('id') == request_id:
                    if response.get('ok') is not True:
                        raise RuntimeError('Orca rejected ' + method)
                    return response['result']
    raise RuntimeError('No matching RPC response')


def process_identity(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'lstart=', '-o', 'command='],
                            capture_output=True, text=True, timeout=10)
    return result.stdout.strip() if result.returncode == 0 else None


def daemon_snapshot():
    found = {}
    for path in (DATA / 'daemon').glob('daemon-v*.pid'):
        record = json.loads(path.read_text())
        pid = record['pid']
        identity = process_identity(pid)
        if identity and 'daemon-entry.js' in identity:
            found[pid] = identity
    if not found:
        raise RuntimeError('No live session daemon; update deferred')
    return found


def terminal_snapshot():
    response = rpc('terminal.list', {})
    if response.get('truncated'):
        raise RuntimeError('Terminal inventory truncated; update deferred')
    return {t['ptyId']: t.get('incarnationId') for t in response['terminals']
            if t.get('executionHostId') == 'local'}


def stable_version(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+\.\d+\.\d+', value):
        raise RuntimeError('Only stable numeric releases are eligible')
    return tuple(map(int, value.split('.')))


def eligible(snapshot):
    support = snapshot.get('support', {})
    if support.get('automatic') is not True or support.get('installMode') != 'interactive':
        raise RuntimeError('Standard desktop updater unavailable; deferred')
    if snapshot['status'].get('source', 'release') != 'release':
        raise RuntimeError('Local or pinned build selected; deferred')


def save(name, value):
    destination = BASE / name
    temporary = destination.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(destination)


def run(inspect_only=False):
    if (BASE / 'PAUSED').exists():
        logging.warning('Paused: remove PAUSED after reviewing the log')
        return
    snapshot = rpc('updater.getStatus')
    eligible(snapshot)
    logging.info('Orca %s; updater=%s target=%s', snapshot['appVersion'],
                 snapshot['status']['state'], snapshot['status'].get('version'))
    if inspect_only:
        print(json.dumps({'updater': snapshot, 'daemonPids': list(daemon_snapshot()),
                          'localTerminals': len(terminal_snapshot())}, indent=2))
        return
    # Reconcile an interrupted install without claiming old sessions survived.
    pending = BASE / 'last-update.json'
    previous = json.loads(pending.read_text()) if pending.exists() else {}
    if previous.get('state') == 'install-requested':
        if stable_version(snapshot['appVersion']) >= stable_version(previous['target']):
            previous.update(state='version-confirmed', confirmedAt=time.time(),
                            observedVersion=snapshot['appVersion'])
            save('last-update.json', previous)
            logging.warning('Recovered interrupted verification: version %s confirmed; historical session survival unknown', snapshot['appVersion'])
        elif time.time() - previous['at'] < 10800:
            logging.info('Previous install still within three-hour cooldown; deferred')
            return
        else:
            previous.update(state='retry-due', reconciledAt=time.time())
            save('last-update.json', previous)
            logging.warning('Previous install incomplete; retrying through standard updater')
    attempt = BASE / 'last-attempt.json'
    if attempt.exists() and time.time() - json.loads(attempt.read_text())['at'] < 10800:
        logging.info('Three-hour attempt cooldown active')
        return
    save('last-attempt.json', {'at': time.time()})
    rpc('updater.check', {'includePrerelease': False, 'includePerfPrerelease': False})
    deadline = time.monotonic() + 900
    download_requested = False
    while time.monotonic() < deadline:
        snapshot = rpc('updater.getStatus')
        eligible(snapshot)
        status = snapshot['status']
        state = status['state']
        if state == 'not-available':
            logging.info('No update available')
            return
        if state == 'error':
            raise RuntimeError('Built-in updater reported an error; retry after cooldown')
        if state in ('available', 'downloaded'):
            if stable_version(status['version']) <= stable_version(snapshot['appVersion']):
                logging.info('No newer stable version selected')
                return
            if state == 'available' and not download_requested:
                logging.info('Downloading %s through built-in updater', status['version'])
                rpc('updater.download')
                download_requested = True
            elif state == 'downloaded':
                break
        time.sleep(5)
    else:
        raise RuntimeError('Check/download deadline exceeded; no forced action')
    before_daemons = daemon_snapshot()
    before_terminals = terminal_snapshot()
    target = status['version']
    save('last-update.json', {'at': time.time(), 'from': snapshot['appVersion'],
                             'target': target, 'state': 'install-requested',
                             'daemonPids': list(before_daemons), 'terminals': before_terminals})
    logging.info('Installing %s through standard updater; preserving %d local terminals',
                 target, len(before_terminals))
    receipt = rpc('updater.install')
    if receipt.get('accepted') is not True:
        raise RuntimeError('Install not accepted')
    install_started = time.monotonic()
    deadline = install_started + 240
    while time.monotonic() < deadline:
        time.sleep(5)
        try:
            after = rpc('updater.getStatus')
            if after['appVersion'] != target:
                continue
            surviving = all(process_identity(pid) == identity
                            for pid, identity in before_daemons.items())
            after_terminals = terminal_snapshot()
            missing = [pty for pty, incarnation in before_terminals.items()
                       if after_terminals.get(pty) != incarnation]
            if missing:
                # The renderer may still be reattaching. Wait within the same deadline.
                continue
            if not surviving:
                logging.warning('Daemon inventory changed, but all recorded terminal incarnations survived')
            save('last-update.json', {'at': time.time(), 'target': target, 'state': 'verified',
                                     'sameDaemons': surviving,
                                     'daemonPids': list(before_daemons),
                                     'preservedLocalTerminals': len(before_terminals)})
            logging.info('Verified Orca %s; preserved %d terminal incarnations',
                         target, len(before_terminals))
            return
        except (OSError, ValueError, KeyError, StopIteration):
            continue
    raise RuntimeError('Update/reconnection not verified within four minutes')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inspect', action='store_true', help='Read-only preflight')
    args = parser.parse_args()
    LOG.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(LOG / 'update.log', maxBytes=1048576, backupCount=3)
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
    logging.basicConfig(level=logging.INFO, handlers=[handler, logging.StreamHandler()])
    with (BASE / 'run.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        try:
            run(args.inspect)
        except Exception as error:
            # Never log credentials, raw RPC responses, or terminal contents.
            logging.error('%s: %s', type(error).__name__, str(error))
            # Retry next scheduled run; PAUSED is reserved for an explicit manual pause.
            raise SystemExit(1)


if __name__ == '__main__':
    main()
