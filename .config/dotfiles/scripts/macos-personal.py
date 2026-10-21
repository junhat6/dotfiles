#!/usr/bin/env python3
"""Apply the shared Dock/keyboard profile, preserving only the affected keys."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

KEYS = {'NSGlobalDomain': ('KeyRepeat', 'InitialKeyRepeat'),
        'com.apple.dock': ('persistent-apps', 'autohide', 'show-recents')}


def read_domain(domain):
    result = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True)
    if result.returncode:
        raise RuntimeError('Cannot export preferences: ' + domain)
    return plistlib.loads(result.stdout)


def write_value(domain, key, value):
    # defaults accepts an XML property-list element, including nested Dock tiles.
    element = ET.fromstring(plistlib.dumps(value))[0]
    subprocess.run(['defaults', 'write', domain, key,
                    ET.tostring(element, encoding='unicode')], check=True)


def desired():
    apps = []
    for name in ('Launchpad', 'System Settings'):
        path = Path('/System/Applications') / (name + '.app')
        if not path.is_dir():
            print('利用できないアプリをスキップ: ' + str(path))
            continue
        apps.append({'tile-type': 'file-tile', 'tile-data': {
            'file-data': {'_CFURLString': path.as_uri() + '/', '_CFURLStringType': 15}}})
    # Finder is provided by Dock itself; do not add a duplicate persistent tile.
    return {'NSGlobalDomain': {'KeyRepeat': 1, 'InitialKeyRepeat': 15},
            'com.apple.dock': {'persistent-apps': apps, 'autohide': True,
                               'show-recents': False}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('apply', 'restore', 'status'), default='apply', nargs='?')
    args = parser.parse_args()
    if sys.platform != 'darwin' or os.geteuid() == 0:
        parser.error('Run on macOS as the logged-in user, without sudo.')
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dotfiles/macos-personal'
    backup = state / 'before.plist'
    if args.action == 'restore':
        if not backup.is_file():
            parser.error('No saved settings to restore.')
        saved = plistlib.loads(backup.read_bytes())
        for domain, keys in KEYS.items():
            current = read_domain(domain)
            for key in keys:
                if key in saved[domain]:
                    write_value(domain, key, saved[domain][key])
                elif key in current:
                    subprocess.run(['defaults', 'delete', domain, key], check=True)
    else:
        current = {domain: read_domain(domain) for domain in KEYS}
        if args.action == 'status':
            for domain, keys in KEYS.items():
                for key in keys:
                    value = current[domain].get(key, '(unset)')
                    if key == 'persistent-apps' and isinstance(value, list):
                        value = [tile.get('tile-data', {}).get('file-label') or
                                 tile.get('tile-data', {}).get('file-data', {}).get('_CFURLString', '(unknown)')
                                 for tile in value]
                    print(f'{domain}/{key}: {value}')
            print('復元用バックアップ: ' + str(backup))
            return
        if not backup.exists():
            state.mkdir(parents=True, exist_ok=True, mode=0o700)
            saved = {domain: {key: current[domain][key] for key in keys if key in current[domain]}
                     for domain, keys in KEYS.items()}
            # Exclusive create: a repeat apply never replaces the original snapshot.
            with backup.open('xb') as stream:
                os.chmod(backup, 0o600)
                plistlib.dump(saved, stream)
        for domain, values in desired().items():
            for key, value in values.items():
                write_value(domain, key, value)
    # Restart only this user's Dock, without closing their applications.
    subprocess.run(['killall', '-u', str(os.getuid()), 'Dock'], check=False)
    print('Mac設定を適用しました。Dockは再起動済みです。' if args.action == 'apply' else '保存したMac設定へ戻しました。')
    print('キーリピートの反映を確実にするため、作業終了後にログアウト／ログイン、またはMacを再起動してください。自動再起動はしません。')


if __name__ == '__main__':
    main()
