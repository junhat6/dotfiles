"""Run after every `dotfiles update` on each Mac.

1. Register per-machine LaunchAgents that every Mac should run but that are not loaded
   (an auto-pull only writes files; launchd registration used to be a manual step, which
   is how orca-autoupdate went missing on one Mac). A loaded job is never stopped or
   restarted; a job explicitly disabled with `launchctl disable` is respected.
2. Collect what still needs a human (sudo, a changed plist that needs a reload, a blocked
   update, a hung or failing maintenance run) and post it to Discord, at most once a day per
   item, plus one "resolved" message when it clears.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import urllib.request

from dotfiles import atomic_write, op_env

HOME = Path.home()
STATE = HOME / 'Library/Application Support/dotfiles'
AGENTS = HOME / 'Library/LaunchAgents'
SCRIPTS = Path(__file__).resolve().parent
WEBHOOK_SERVICE = 'dotfiles-discord-webhook'
WEBHOOK_OP_REF = 'op://Automation/dotfiles-discord-webhook/credential'
WEBHOOK_URL = re.compile(r'https://(?:(?:ptb|canary)\.)?(?:discord|discordapp)\.com/api/(?:v\d+/)?webhooks/\d+/[A-Za-z0-9_-]+(?:\?[A-Za-z0-9_=&-]*)?')
HOMEBREW_LOG = HOME / '.claude/logs/homebrew-update.log'
DAY = 86400
# Every Mac runs these. obsidian-sync is profile-dependent and stays a setup decision.
SERVICES = [
    {'label': 'com.junhat6.homebrew-update'},
    {'label': 'com.claude.brewfile-sync'},
    {'label': 'com.junhat6.orca-autoupdate', 'installer': 'install-orca-autoupdate.py',
     'installed_copy': HOME / 'Library/Application Support/OrcaAutoUpdate/orca-autoupdate.py',
     'source': SCRIPTS / 'orca-autoupdate.py', 'requires': Path('/Applications/Orca.app')},
]


def sh(*cmd, **kwargs):
    return subprocess.run(list(cmd), capture_output=True, text=True, timeout=120, **kwargs)


def domain():
    return 'gui/' + str(os.getuid())


def disabled_labels():
    out = sh('launchctl', 'print-disabled', domain()).stdout
    return {m.group(1) for m in re.finditer(r'"([^"]+)" => (?:disabled|true)', out)}


def loaded(label):
    return sh('launchctl', 'print', domain() + '/' + label).returncode == 0


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def converge_services(state, issues, disabled=None, is_loaded=loaded, run=sh):
    disabled = disabled_labels() if disabled is None else disabled
    hashes = state.setdefault('plist_hashes', {})
    for service in SERVICES:
        label = service['label']
        if label in disabled:
            continue
        if service.get('requires') and not service['requires'].exists():
            continue
        plist = AGENTS / (label + '.plist')
        try:
            if service.get('installer'):
                copy = service['installed_copy']
                stale = not copy.exists() or copy.read_bytes() != service['source'].read_bytes()
                if stale or not is_loaded(label):
                    # The installer is idempotent: refresh the job's script copy, write the
                    # plist, bootstrap only if not loaded. A loaded job picks up the new copy
                    # on its next scheduled run (each run is a fresh process).
                    result = run(sys.executable, str(SCRIPTS / service['installer']))
                    if result.returncode:
                        raise RuntimeError((result.stderr or result.stdout).strip()[-300:])
                    print('converge: refreshed ' + label)
            elif not is_loaded(label):
                if not plist.exists():
                    raise RuntimeError('plist がありません (dotfiles render を確認)')
                result = run('launchctl', 'bootstrap', domain(), str(plist))
                if result.returncode:
                    raise RuntimeError(result.stderr.strip()[-300:])
                print('converge: registered ' + label)
                hashes[label] = digest(plist)
            current = digest(plist)
            if label not in hashes:
                hashes[label] = current  # first observation: assume the loaded job matches
            elif current and hashes[label] != current:
                issues[label + ':reload'] = (
                    f'`{label}` の設定が変わりました。再読み込みが必要です: '
                    f'`dotfiles services reload {label}`')
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            issues[label + ':register'] = f'`{label}` を登録できませんでした: {exc}'


def reload_service(label, state):
    if label not in {s['label'] for s in SERVICES}:
        raise ValueError('unknown service: ' + label)
    plist = AGENTS / (label + '.plist')
    if loaded(label):
        sh('launchctl', 'bootout', domain() + '/' + label)
    result = sh('launchctl', 'bootstrap', domain(), str(plist))
    if result.returncode:
        raise ValueError(result.stderr.strip())
    state.setdefault('plist_hashes', {})[label] = digest(plist)


def update_issues(issues):
    last = STATE / 'last-update.json'
    if last.exists():
        data = json.loads(last.read_text())
        if data.get('status') == 'blocked':
            issues['dotfiles:blocked'] = 'dotfiles の自動取り込みが保留中です: ' + data.get('message', '')


def homebrew_issues(issues, log=HOMEBREW_LOG, now=None):
    if not log.exists():
        return
    now = now or time.time()
    lines = log.read_text(errors='replace').splitlines()
    starts = [i for i, line in enumerate(lines) if line.endswith('Homebrew maintenance started')]
    if not starts:
        return
    run = lines[starts[-1]:]
    started = re.match(r'\[([^\]]+)\]', run[0])
    finished = any('Homebrew maintenance exit=' in line for line in run)
    if not finished and started:
        try:
            age = now - time.mktime(time.strptime(started.group(1), '%Y-%m-%dT%H:%M:%S%z'))
        except ValueError:
            age = 0
        if age > 6 * 3600:
            issues['homebrew:hung'] = (f'Homebrew の定期更新が {int(age // 3600)} 時間終わっていません'
                                       '（止まった処理がないか確認してください）')
        return
    sudo = sorted({m.group(1) for line in run
                   for m in [re.match(r'Error: ([\w@./+-]+): Failure while executing; `/usr/bin/sudo', line)] if m})
    if sudo:
        issues['homebrew:sudo'] = ('管理者パスワードが必要な更新があります。画面の前で実行してください: '
                                   '`brew upgrade --cask ' + ' '.join(sudo) + '`')
    for line in run:
        if line.startswith('Step timed out'):
            issues['homebrew:timeout'] = 'Homebrew の定期更新で時間切れになった処理があります: ' + line


def webhook():
    found = sh('/usr/bin/security', 'find-generic-password', '-s', WEBHOOK_SERVICE, '-w')
    url = found.stdout.strip() if found.returncode == 0 else ''
    return url if WEBHOOK_URL.fullmatch(url) else None


def host():
    name = sh('/usr/sbin/scutil', '--get', 'ComputerName').stdout.strip()
    return name or platform.node()


def post(url, text):
    body = json.dumps({'content': text[:1900], 'allowed_mentions': {'parse': []}}).encode()
    # Discord's edge rejects the default Python-urllib User-Agent.
    request = urllib.request.Request(url, body, {'Content-Type': 'application/json',
                                                 'User-Agent': 'dotfiles-notify/1.0'})
    with urllib.request.urlopen(request, timeout=20) as response:
        response.read()


def notify(state, issues, send, now=None):
    """Send new/changed issues and daily reminders; announce resolved ones once."""
    now = now or time.time()
    sent = state.setdefault('issues', {})
    due = [key for key, text in issues.items()
           if key not in sent or sent[key]['text'] != text or now - sent[key]['at'] >= DAY]
    resolved = [key for key in sent if key not in issues]
    if not due and not resolved:
        return False
    lines = []
    if due:
        lines.append(f'🖐 **{host()}**: 人の操作が必要です')
        lines += ['• ' + issues[key] for key in due]
    if resolved:
        lines.append(f'✅ **{host()}**: 解消しました')
        lines += ['• ' + sent[key]['text'] for key in resolved]
    send('\n'.join(lines))
    for key in due:
        sent[key] = {'text': issues[key], 'at': now}
    for key in resolved:
        del sent[key]
    return True


def load_state():
    path = STATE / 'converge-state.json'
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    atomic_write(STATE / 'converge-state.json', (json.dumps(state, ensure_ascii=False, indent=2) + '\n').encode(), 0o600)


def converge():
    if platform.system() != 'Darwin':
        return 0
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'converge.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        state = load_state()
        issues = {}
        converge_services(state, issues)
        update_issues(issues)
        homebrew_issues(issues)
        url = webhook()
        if not url and op_env():
            # Unattended Macs (service account token in the Keychain) set themselves up.
            # Interactive Macs would show Touch ID from a background job, so they don't.
            try:
                store_webhook(WEBHOOK_OP_REF)
                url = webhook()
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                print('converge: Discord の Webhook を取り込めませんでした: ' + str(exc))
        if url:
            try:
                notify(state, issues, lambda text: post(url, text))
            except OSError as exc:
                print('converge: Discord に送れませんでした (次回再送): ' + str(exc))
        elif issues:
            print('converge: Discord 未設定のため通知しません (dotfiles discord-webhook): ' + ', '.join(sorted(issues)))
        save_state(state)
        return 0


def store_webhook(reference):
    try:
        # A pending 1Password/Keychain dialog nobody answers must not hang the update job.
        result = subprocess.run(['op', 'read', '--no-newline', reference], capture_output=True, text=True,
                                env=op_env(), timeout=60)
    except FileNotFoundError:
        raise ValueError('op が見つかりません (brew install --cask 1password-cli)')
    except subprocess.TimeoutExpired:
        raise ValueError('1Password の応答が60秒ありません (画面に承認ダイアログが出ていないか確認)')
    if result.returncode:
        raise ValueError('1Password から読めませんでした: ' + result.stderr.strip())
    url = result.stdout.strip()
    if not WEBHOOK_URL.fullmatch(url):
        shape = re.sub(r'[A-Za-z0-9_-]{12,}', '<秘密>', url)
        raise ValueError('Discord の Webhook URL の形式ではありません: ' + shape[:120])
    # Overwriting a different value makes macOS ask for the login keychain password on screen.
    if webhook() != url:
        subprocess.run(['/usr/bin/security', '-i'], check=True, capture_output=True,
                       input=('add-generic-password -U -a dotfiles -s ' + WEBHOOK_SERVICE +
                              ' -T /usr/bin/security -w ' + url + '\n').encode())
    post(url, f'🔔 **{host()}**: dotfiles の通知を設定しました')
