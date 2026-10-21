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
    labels = ['com.claude.brewfile-sync']
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
        run('launchctl', 'kickstart', '-k', target)


def report(home, profile, run_dir):
    print('Installed dependencies verified. Profile:', profile)
    print('GitHub credentials: gh-managed local credential store; inspect with gh auth status.')
    if profile != 'none':
        destination = home / f'ghq/github.com/junhat6/my-vault-{profile}'
        print('Session destination:', destination)
        print('iPhone/Dropbox sync is separate; Remotely Save credentials are not restored.')
    print('App approvals are checked by the user/agent at the early GUI checkpoint.')
    print('No passwordless sudo rule or agent permission elevation was installed.')
    timings = run_dir / 'timings.tsv'
    if timings.exists():
        print('Stage / exit code / seconds:\n' + timings.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('checkout').add_argument('--backup', type=Path, required=True)
    sub.add_parser('prepare-local')
    sub.add_parser('credentials')
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
