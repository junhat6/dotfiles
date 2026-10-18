"""Fast-forward shared HOME files; opt-in per-machine macOS scheduling."""
import fcntl
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

from dotfiles import Repository, atomic_write

LABEL = 'com.junhat6.dotfiles-update'
PLIST = 'Library/LaunchAgents/' + LABEL + '.plist'
TEMPLATE = '.config/dotfiles/templates/' + LABEL + '.plist'


def state_dir(repo):
    return repo.root / 'Library/Application Support/dotfiles'


def command(repo, *args):
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never',
               GIT_SSH_COMMAND='ssh -oBatchMode=yes -oConnectTimeout=15')
    result = subprocess.run(list(args), cwd=repo.root, env=env, capture_output=True, timeout=120)
    if result.returncode:
        raise ValueError(result.stderr.decode(errors='replace').strip() or result.stdout.decode(errors='replace').strip() or 'command failed: ' + ' '.join(args))
    return result.stdout.decode().strip()


def git(repo, *args):
    return command(repo, 'yadm' if repo.backend == 'yadm' else 'git', *args)


def update(repo):
    directory = state_dir(repo)
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / 'update.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('dotfiles: another update is running')
            return 0
        result = {'time': time.strftime('%Y-%m-%dT%H:%M:%S%z')}
        try:
            if git(repo, 'symbolic-ref', '--short', 'HEAD') != 'main':
                raise ValueError('main 以外のブランチでは更新しません。main に戻して dotfiles update を実行してください')
            # Never let merge.autoStash silently save/reapply local edits.
            if git(repo, 'diff', '--name-only', '--cached'):
                raise ValueError('ステージ済みの変更があります。commit または unstage して再実行してください')
            git_dir = Path(git(repo, 'rev-parse', '--absolute-git-dir'))
            if any((git_dir / name).exists() for name in ('MERGE_HEAD', 'rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD', 'REVERT_HEAD')):
                raise ValueError('Git の merge/rebase 等が進行中です。完了してから再実行してください')
            git(repo, 'fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main')
            target = git(repo, 'rev-parse', 'refs/remotes/origin/main')
            git(repo, 'merge-base', '--is-ancestor', 'HEAD', target)
            incoming = Repository(repo.root, repo.backend, target)
            errors = incoming.check(generated=False, discover=False)
            if errors:
                raise ValueError('remote validation failed: ' + '\n'.join(errors))
            previous = git(repo, 'rev-parse', 'HEAD')
            # Git rejects overlapping local edits, untracked-file collisions and divergence.
            git(repo, '-c', 'merge.autoStash=false', 'merge', '--ff-only', '--no-autostash', '--no-overwrite-ignore', target)
            # Run the NEW renderer in a new process after updating its source.
            command(repo, sys.executable, str(repo.root / '.config/dotfiles/scripts/dotfiles.py'),
                    '--root', str(repo.root), '--backend', repo.backend, 'render')
            result.update(status='updated' if previous != target else 'current', revision=target)
            print('dotfiles: ' + result['status'] + ' ' + target[:12])
            return 0
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            result.update(status='blocked', message=str(exc))
            print('dotfiles: 更新を保留しました: ' + str(exc))
            return 1
        finally:
            atomic_write(directory / 'last-update.json', (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode(), 0o600)


def auto_update(repo, action):
    directory = state_dir(repo)
    target = repo.root / PLIST
    domain = 'gui/' + str(os.getuid())
    if action == 'status':
        loaded = False
        if platform.system() == 'Darwin':
            loaded = subprocess.run(['launchctl', 'print', domain + '/' + LABEL], capture_output=True).returncode == 0
        print('auto-update: ' + ('enabled (15分ごと / ログイン時)' if loaded else 'disabled / not loaded'))
        last = directory / 'last-update.json'
        if last.exists():
            print(last.read_text().strip())
        print('log: ' + str(directory / 'update.log'))
        return 0
    if platform.system() != 'Darwin' or repo.backend != 'yadm' or repo.root != Path.home().resolve():
        raise ValueError('自動登録は macOS の yadm HOME で実行してください。他の環境は dotfiles update を利用できます')
    directory.mkdir(parents=True, exist_ok=True)
    service = domain + '/' + LABEL
    loaded = subprocess.run(['launchctl', 'print', service], capture_output=True).returncode == 0
    if action == 'disable':
        if loaded:
            command(repo, 'launchctl', 'bootout', service)
        target.unlink(missing_ok=True)
        print('dotfiles: auto-update disabled')
        return 0
    item = {'template': TEMPLATE, 'output': PLIST}
    atomic_write(target, repo.rendered(item, repo.root))
    command(repo, 'launchctl', 'enable', service)
    if not loaded:
        command(repo, 'launchctl', 'bootstrap', domain, str(target))
    print('dotfiles: auto-update enabled (15分ごと / ログイン時)。dotfiles auto-update status で結果を確認できます')
    return 0
