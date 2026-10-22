#!/usr/bin/env python3
"""Local-only setup operations. Never add/commit/push files or store tokens."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess


def run(*args, **kwargs):
    return subprocess.run(list(args), check=True, **kwargs)


def output(*args):
    return subprocess.check_output(list(args))


def no_symlinks(path, root):
    path.relative_to(root)
    for candidate in (path, *path.parents):
        if candidate.is_symlink():
            raise ValueError(f'refusing symlink: {candidate}')
        if candidate == root:
            break


def write_json(path, document, home):
    no_symlinks(path, home)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.setup-tmp')
    # Exclusive creation prevents following a pre-existing temporary symlink.
    with temporary.open('x') as stream:
        json.dump(document, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    temporary.chmod(0o600)
    temporary.replace(path)


def checkout(home, backup):
    manifest = json.loads(output('yadm', 'show', 'HEAD:.config/dotfiles/ownership.json'))
    entries = output('yadm', 'ls-tree', '-rz', 'HEAD').split(b'\0')
    files = []
    for entry in filter(None, entries):
        metadata, raw_path = entry.split(b'\t', 1)
        relative = raw_path.decode()
        path = PurePosixPath(relative)
        if (metadata.split()[0] not in (b'100644', b'100755') or
                path.is_absolute() or '..' in path.parts or
                str(path) != relative or relative not in manifest['shared']):
            raise ValueError(f'unsafe/unapproved tree entry: {relative}')
        target = home / relative
        no_symlinks(target, home)
        if target.exists() and not target.is_file():
            raise ValueError(f'not a regular file: {target}')
        files.append((relative, target))
    # Preflight the complete tree before moving any file.
    for relative, target in files:
        expected = output('yadm', 'show', 'HEAD:' + relative)
        if target.exists() and target.read_bytes() != expected:
            saved = backup / relative
            no_symlinks(saved, backup)
            saved.parent.mkdir(parents=True, exist_ok=True)
            if saved.exists():
                raise ValueError(f'backup already exists: {saved}')
            shutil.copy2(target, saved)
            target.unlink()
            print(f'Backed up {relative}')
        run('yadm', 'checkout', 'HEAD', '--', relative)


def prepare_local(home):
    target = home / '.claude/settings.local.json'
    no_symlinks(target, home)
    document = json.loads(target.read_text()) if target.exists() else {}
    if not isinstance(document, dict) or not isinstance(document.get('permissions', {}), dict):
        raise ValueError('invalid Claude local permissions; leaving them untouched')
    permissions = document.setdefault('permissions', {})
    if 'defaultMode' not in permissions:
        permissions['defaultMode'] = 'default'
        write_json(target, document, home)


def credentials(home):
    local = home / '.gitconfig.local'
    no_symlinks(local, home)
    local.parent.mkdir(parents=True, exist_ok=True)
    # Keep the original local file for review/recovery, without replacing old backups.
    backup = local.with_suffix('.local.before-setup')
    no_symlinks(backup, home)
    if local.exists() and not backup.exists():
        shutil.copy2(local, backup)
    mise = shutil.which('mise')
    if not mise:
        raise ValueError('mise is required for the credential helper')
    for host in ('github.com', 'gist.github.com'):
        key = f'credential.https://{host}.helper'
        run('git', 'config', '--file', str(local), '--replace-all', key, '')
        # Resolve the configured gh from HOME, not from an arbitrary/untrusted
        # project. Explicitly name gh so authentication never installs all tools.
        import shlex
        run('git', 'config', '--file', str(local), '--add', key,
            '!' + shlex.join([mise, '--cd', str(home), 'exec', 'gh', '--', 'gh', 'auth', 'git-credential']))
    local.chmod(0o600)


def vaults(home, profile):
    for kind in ('personal', 'work'):
        directory = home / f'ghq/github.com/junhat6/my-vault-{kind}'
        no_symlinks(directory, home)
        remote = f'https://github.com/junhat6/my-vault-{kind}.git'
        if not directory.exists():
            directory.parent.mkdir(parents=True, exist_ok=True)
            run('git', 'clone', remote, str(directory))
        origin = output('git', '-C', str(directory), 'remote', 'get-url', 'origin').decode().strip()
        if origin not in (remote, remote.removesuffix('.git'), f'git@github.com:junhat6/my-vault-{kind}.git'):
            raise ValueError(f'Unexpected vault origin: {directory}')
        # No pull/reset/clean: preserve existing edits when setup is resumed.
        git_settings = directory / '.obsidian/plugins/obsidian-git/data.json'
        no_symlinks(git_settings, home)
        for relative in ('setup/obsidian-git-role.py', 'setup/community-plugins.json', '.obsidian/community-plugins.json'):
            no_symlinks(directory / relative, home)
        role = 'writer' if kind == profile else 'reader'
        current = json.loads(git_settings.read_text()) if git_settings.exists() else {}
        community = directory / '.obsidian/community-plugins.json'
        if current.get('disablePush') is (kind != profile) and community.is_file():
            print(f'{kind}: existing {role} role retained')
            continue
        if subprocess.run(['pgrep', '-x', 'Obsidian'], capture_output=True).returncode == 0:
            raise ValueError('Close Obsidian before setting vault roles, then rerun setup')
        run('/usr/bin/python3', str(directory / 'setup/obsidian-git-role.py'), role)
    destination = home / f'ghq/github.com/junhat6/my-vault-{profile}'
    run('bash', str(home / '.claude/hooks/watch-and-save.sh'), '--check-destination', str(destination), f'junhat6/my-vault-{profile}')
    for directory in ('claude', 'Codex'):
        run('git', '-C', str(destination), 'check-ignore', directory + '/setup-check.md')


def services(home, profile):
    labels = ['com.claude.brewfile-sync', 'com.junhat6.homebrew-update']
    if profile != 'none':
        destination = home / f'ghq/github.com/junhat6/my-vault-{profile}'
        run('bash', str(home / '.claude/hooks/watch-and-save.sh'), '--check-destination', str(destination), f'junhat6/my-vault-{profile}')
        labels.append('com.claude.obsidian-sync')
    (home / '.claude/logs').mkdir(parents=True, exist_ok=True)
    for label in labels:
        target = f'gui/{os.getuid()}/{label}'
        plist = home / f'Library/LaunchAgents/{label}.plist'
        document = plistlib.loads(plist.read_bytes())
        if document['Label'] != label:
            raise ValueError(f'Unexpected LaunchAgent: {plist}')
        if subprocess.run(['launchctl', 'print', target], capture_output=True).returncode != 0:
            run('launchctl', 'bootstrap', f'gui/{os.getuid()}', str(plist))
        if label != 'com.junhat6.homebrew-update':
            run('launchctl', 'kickstart', '-k', target)


def finder_sidebar_plan(home):
    document = json.loads((home / '.config/dotfiles/finder-sidebar.json').read_text())
    if document.get('version') != 1 or document.get('method') != 'agent-finder':
        raise ValueError('Unsupported Finder sidebar preferences')
    favorites = document.get('favorites')
    if not isinstance(favorites, list) or not favorites:
        raise ValueError('Finder favorites are required')
    # Validate every path before creating anything. Resolve from this Mac's HOME.
    targets = []
    for item in favorites:
        relative = PurePosixPath(item['relative_path'])
        if relative.is_absolute() or not relative.parts or '..' in relative.parts or not isinstance(item.get('name'), str):
            raise ValueError('Finder favorite must be a relative HOME directory')
        target = home.joinpath(*relative.parts)
        no_symlinks(target, home)
        targets.append((item, target))
    records = []
    for item, target in targets:
        target.mkdir(parents=True, exist_ok=True)
        record = dict(item, path=str(target), status='pending-ui')
        print('FINDER_SIDEBAR_PREFERENCE: ' + json.dumps(record, ensure_ascii=False))
        records.append(record)
    print('AI: Finderで対象フォルダを開き、ファイル → サイドバーに追加。既存項目を残し、同じパスを重複追加せず、よく使う項目に表示されたことを画面確認。追加確認・再起動不要。')
    return records


def browser_plan(home, appdir=Path('/Applications')):
    document = json.loads((home / '.config/dotfiles/browser.json').read_text())
    if document.get('version') != 1 or document.get('method') != 'agent-system-settings' or document.get('bundle_id') != 'com.google.Chrome' or document.get('app_path') != '/Applications/Google Chrome.app':
        raise ValueError('Unsupported default browser preference')
    info = appdir / 'Google Chrome.app/Contents/Info.plist'
    try:
        identity = plistlib.loads(info.read_bytes())['CFBundleIdentifier']
    except (OSError, KeyError, plistlib.InvalidFileException):
        identity = None
    record = dict(document, status='pending-ui' if identity == document['bundle_id'] else 'unavailable')
    print('BROWSER_PREFERENCE: ' + json.dumps(record, ensure_ascii=False))
    if record['status'] == 'pending-ui':
        print('AI: デフォルトのWebブラウザをGoogle Chromeへ変更し、設定画面の選択値を確認。既にChromeなら変更不要。追加確認・再起動不要。')
    else:
        print('Chromeが未導入またはbundle ID不一致のため未適用。他のセットアップは続行し、完了と報告しない。')
    return record


def notification_plan(home):
    path = home / '.config/dotfiles/notifications.json'
    document = json.loads(path.read_text())
    if document.get('version') != 1 or document.get('method') != 'agent-system-settings':
        raise ValueError('Unsupported notification preferences format')
    apps = document.get('apps')
    if not isinstance(apps, list) or not apps:
        raise ValueError('Notification app preferences are required')
    for app in apps:
        if not isinstance(app.get('bundle_id'), str) or not isinstance(app.get('name'), str) or type(app.get('enabled')) is not bool:
            raise ValueError('Invalid notification app preference')
    for app in apps:
        print('NOTIFICATION_PREFERENCE: ' + json.dumps(app, ensure_ascii=False))
    print('AI: システム設定 → 通知で指定アプリの「通知を許可」を目標値へ設定し、画面で確認。追加確認・再起動不要。')
    return apps


def report(home, profile, run_dir):
    print('Installed dependencies verified. Profile:', profile)
    print('GitHub credentials: gh-managed local credential store; inspect with gh auth status.')
    if profile != 'none':
        destination = home / f'ghq/github.com/junhat6/my-vault-{profile}'
        print('Session destination:', destination)
        print('iPhone/Dropbox sync is separate; Remotely Save credentials are not restored.')
    for name in ('app-verification-early.json', 'app-verification.json'):
        path = run_dir / name
        if path.exists():
            records = json.loads(path.read_text())['apps']
            deferred = [item for item in records if item['status'] == 'deferred']
            print(f'App verification: {name}: {len(deferred)} deferred; details: {path}')
            for item in deferred:
                print('APP_ATTENTION:', item.get('app', item['cask']), item['reason'])
    print('Finder sidebar: agent must verify HOME/ghq/github.com in Favorites; the CLI plan creates the folder but does not add the sidebar item.')
    print('Default browser: agent must verify Google Chrome in System Settings after package installation; the CLI plan alone does not apply it.')
    print('Notification preferences require GUI verification at the early checkpoint; the CLI plan alone does not apply them.')
    print('App approvals are checked by the user/agent at the early GUI checkpoint.')
    print('No passwordless sudo rule or agent permission elevation was installed.')
    timings = run_dir / 'timings.tsv'
    if timings.exists():
        print('Stage / exit code / seconds:\n' + timings.read_text())


# Package casks do not declare app artifacts. These are explicit bundle targets,
# not a scan of /Applications or arbitrary package receipts.
PACKAGE_APPS = {
    'karabiner-elements': ['Karabiner-Elements.app', 'Karabiner-EventViewer.app'],
    'zoom': ['zoom.us.app'],
    'tailscale-app': ['Tailscale.app'],
}


def brewfile_casks(path):
    import re
    result = []
    for line in path.read_text().splitlines():
        if not re.match(r'^\s*cask\b', line):
            continue
        match = re.fullmatch(r'\s*cask\s+"([a-z0-9@+._/-]+)"\s*(?:#.*)?', line)
        if not match or '..' in match[1].split('/'):
            raise ValueError('Expected a literal cask entry: ' + line)
        result.append(match[1])
    return list(dict.fromkeys(result))


def app_targets(cask, metadata, appdir):
    # full_token is essential: bare "orca" is a different Homebrew cask.
    if metadata.get('full_token') != cask or not metadata.get('installed'):
        raise ValueError('Cask identity mismatch or not installed: ' + cask)
    targets = []
    for artifact in metadata.get('artifacts', []):
        if 'app' not in artifact:
            continue
        target = artifact.get('target')
        if not isinstance(target, str):
            raise ValueError('Missing installed app target: ' + cask)
        targets.append(Path(target))
    if not targets and cask in PACKAGE_APPS:
        targets = [appdir / name for name in PACKAGE_APPS[cask]]
    for target in targets:
        if target.parent != appdir or target.suffix != '.app':
            raise ValueError('App target must be directly inside /Applications: ' + str(target))
        no_symlinks(target, appdir)
        if not target.is_dir():
            raise ValueError('Installed app is missing: ' + str(target))
    return targets


def check_app(app):
    # Signature integrity alone also accepts ad-hoc signatures; Gatekeeper's
    # notarized Developer ID verdict is required separately, before any mutation.
    env = dict(os.environ, LC_ALL='C', LANG='C')
    for command in [
        ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
        ['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=4',
         '--ignore-cache', '--no-cache', str(app)],
    ]:
        result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=180)
        detail = (result.stdout + result.stderr).strip()
        if result.returncode:
            raise ValueError(detail or 'Verification failed: ' + command[0])
    if 'source=Notarized Developer ID' not in detail.splitlines():
        raise ValueError('Gatekeeper did not confirm Notarized Developer ID: ' + detail)


def clear_app_quarantine(app):
    # macOS's bundled Python has no os.listxattr. xattr -s operates on links
    # themselves, not their referents, including during recursive traversal.
    no_symlinks(app, app.parent)
    def attributes():
        result = subprocess.run(['/usr/bin/xattr', '-r', '-s', str(app)],
                                capture_output=True, text=True, check=True, timeout=180)
        return sum(line.endswith(': com.apple.quarantine') for line in result.stdout.splitlines())
    count = attributes()
    if count:
        no_symlinks(app, app.parent)
        subprocess.run(['/usr/bin/xattr', '-d', '-r', '-s', 'com.apple.quarantine', str(app)],
                       capture_output=True, text=True, check=True, timeout=180)
        if attributes():
            raise ValueError('Quarantine attributes remain: ' + str(app))
    return count


def prepare_apps(home, report_path, selected=None, check_only=False, appdir=Path('/Applications'), brewfile=None):
    import platform
    if platform.system() != 'Darwin':
        raise ValueError('App verification requires macOS')
    allowed = brewfile_casks(brewfile or home / '.config/dotfiles/Brewfile')
    if selected and not set(selected).issubset(allowed):
        raise ValueError('Requested cask is not in the shared Brewfile')
    env = dict(os.environ, LC_ALL='C', LANG='C', HOMEBREW_NO_AUTO_UPDATE='1')
    status = subprocess.run(['/usr/sbin/spctl', '--status'], capture_output=True,
                            text=True, env=env, timeout=30)
    if status.returncode or status.stdout.strip() != 'assessments enabled':
        raise ValueError('Gatekeeper is not enabled; no attributes were changed')
    records = []
    for cask in selected or allowed:
        try:
            result = subprocess.run(['brew', 'info', '--json=v2', '--cask', cask],
                                    capture_output=True, text=True, env=env, timeout=180, check=True)
            metadata = json.loads(result.stdout)['casks']
            if len(metadata) != 1:
                raise ValueError('Expected exactly one cask: ' + cask)
            targets = app_targets(cask, metadata[0], appdir)
            if not targets:
                records.append(dict(cask=cask, status='skipped', reason='No supported app artifact (e.g. fonts)'))
            for app in targets:
                try:
                    identity = app.stat()
                    check_app(app)
                    no_symlinks(app, appdir)
                    if (app.stat().st_dev, app.stat().st_ino, app.stat().st_mtime_ns) != (identity.st_dev, identity.st_ino, identity.st_mtime_ns):
                        raise ValueError('App changed during verification; deferred')
                    count = 0 if check_only else clear_app_quarantine(app)
                    records.append(dict(cask=cask, app=str(app), status='verified' if check_only else 'prepared', attributes_removed=count))
                except (OSError, ValueError, subprocess.SubprocessError) as exc:
                    records.append(dict(cask=cask, app=str(app), status='deferred', reason=str(exc)))
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
            records.append(dict(cask=cask, status='deferred', reason=str(exc)))
    for record in records:
        print('APP_VERIFICATION: ' + json.dumps(record, ensure_ascii=False))
    no_symlinks(report_path, home)
    write_json(report_path, {'check_only': check_only, 'apps': records}, home)
    print('App verification report:', report_path)
    # Rejected apps keep their quarantine and use the normal first-launch flow.
    # Attribute-removal errors may leave partial changes; report them as deferred.
    # A verification rejection must not prevent installing unrelated packages.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('checkout').add_argument('--backup', type=Path, required=True)
    sub.add_parser('prepare-local')
    sub.add_parser('credentials')
    sub.add_parser('notifications')
    sub.add_parser('browser')
    sub.add_parser('finder-sidebar')
    apps = sub.add_parser('prepare-apps')
    apps.add_argument('--report', type=Path, required=True)
    apps.add_argument('--cask', action='append')
    apps.add_argument('--check-only', action='store_true')
    apps.add_argument('--brewfile', type=Path)
    for command in ('vaults', 'services', 'report'):
        child = sub.add_parser(command)
        child.add_argument('--profile', choices=('personal', 'work', 'none'), required=True)
        if command == 'report':
            child.add_argument('--run-dir', type=Path, required=True)
    args = parser.parse_args()
    home = Path.home()
    if args.command == 'checkout':
        checkout(home, args.backup)
    elif args.command == 'prepare-local':
        prepare_local(home)
    elif args.command == 'prepare-apps':
        prepare_apps(home, args.report, args.cask, args.check_only, brewfile=args.brewfile)
    elif args.command == 'finder-sidebar':
        finder_sidebar_plan(home)
    elif args.command == 'browser':
        browser_plan(home)
    elif args.command == 'notifications':
        notification_plan(home)
    elif args.command == 'credentials':
        credentials(home)
    elif args.command == 'vaults':
        vaults(home, args.profile)
    elif args.command == 'services':
        services(home, args.profile)
    else:
        report(home, args.profile, args.run_dir)


if __name__ == '__main__':
    main()
