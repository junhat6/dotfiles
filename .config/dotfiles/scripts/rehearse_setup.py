#!/usr/bin/env python3
"""Run the actual setup Bash in a disposable HOME with simulated OS boundaries.

All approvals are synthetic. Never authenticate sudo, open apps or contact GitHub.
"""
import argparse
import json
import os
from pathlib import Path
import pty
import select
import shlex
import subprocess
import tempfile
import time

STUB = r'''#!/usr/bin/python3
import json, os, sys, time, plistlib, subprocess
from pathlib import Path
name=Path(sys.argv[0]).name; args=sys.argv[1:]
root=Path(os.environ['SIM_ROOT']); scenario=os.environ['SIM_SCENARIO']
def record(action):
    with (root/'calls.jsonl').open('a') as f: f.write(json.dumps([name,action,args])+'\n')
record('call')
if name in ('reboot', 'shutdown', 'osascript'):
    print('[SIM] Forbidden session interruption', flush=True)
    sys.exit(99)
if name=='defaults':
    path=root/'preferences.json'
    data=json.loads(path.read_text()) if path.exists() else {'NSGlobalDomain': {}, 'com.apple.dock': {'persistent-apps': [], 'persistent-others': ['Downloads']}}
    if args[0]=='export':
        sys.stdout.buffer.write(plistlib.dumps(data[args[1]]))
    elif args[0]=='write':
        data[args[1]][args[2]]=plistlib.loads(('<plist version="1.0">'+args[3]+'</plist>').encode())
        path.write_text(json.dumps(data))
    else: sys.exit(98)
    sys.exit(0)
if name=='pmset':
    path=root/'power.json'
    data=json.loads(path.read_text()) if path.exists() else {'Battery Power': 2, 'AC Power': 10}
    if args==['-g','custom']:
        for source,value in data.items(): print(source+':\n displaysleep '+str(value))
    else:
        if scenario=='macos-write-failure': sys.exit(19)
        assert args[1]=='displaysleep'
        data['Battery Power' if args[0]=='-b' else 'AC Power']=int(args[2])
        path.write_text(json.dumps(data))
    sys.exit(0)
if name=='sudo':
    if '-n' in args and any('pmset' in arg for arg in args):
        if scenario=='macos-auth-loss': sys.exit(1)
        sys.exit(subprocess.run(args[1:]).returncode)

    if args==['-v'] and scenario!='existing':
        print('[SIM_USER:administrator-auth]',flush=True)
        if not sys.stdin.readline(): sys.exit(10)
    if args==['-n','-v'] and scenario=='auth-loss' and (root/'bulk').exists(): sys.exit(1)
elif name=='curl':
    target=Path(args[args.index('-o')+1])
    target.write_text('echo "[SIM] Homebrew / Command Line Tools download (time compressed)"\ntouch "'+str(root/'brew-ready')+'"\n')
elif name=='brew':
    if args[:2]==['install','--cask']:
        print('[SIM_DOWNLOAD:priority-apps]',flush=True)
    if args[:2]==['bundle','install']:
        (root/'bulk').touch()
        print('[SIM_BULK_START]',flush=True)
        time.sleep(0.2)
        if scenario=='package-failure': sys.exit(17)
        if scenario=='late-input':
            if sys.stdin.isatty(): print('[SIM_USER:late-package-input]',flush=True)
            answer=sys.stdin.readline()
            if not answer:
                print('[SIM] Unexpected package stdin prompt received EOF; stopped instead of waiting.',flush=True)
                sys.exit(23)
elif name=='yadm':
    if args==['rev-parse','--git-dir']:
        if scenario!='existing' and not (root/'cloned').exists(): sys.exit(1)
        print('.git')
    elif args and args[0]=='clone': (root/'cloned').touch()
    elif args==['rev-parse','--show-toplevel']: print(os.environ['HOME'])
    elif args==['branch','--show-current']: print('main')
    elif args==['remote','get-url','origin']: print('https://github.com/junhat6/dotfiles.git')
    elif args and args[0]=='show': print('import sys\nprint("[SIM] local helper " + sys.argv[1])')
elif name=='mise':
    if args==['which','gh']: print(root/'bin/gh')
elif name=='gh':
    if args[:2]==['auth','status']:
        sys.exit(0 if scenario=='existing' or (root/'github-ready').exists() else 1)
    if args[:2]==['auth','login']:
        print('[SIM_USER:github-2fa]',flush=True)
        if not sys.stdin.readline(): sys.exit(11)
        (root/'github-ready').touch()
'''

APP_APPROVALS = ('karabiner-background', 'karabiner-driver', 'hammerspoon-accessibility')


def rehearse(source, scenario='fresh'):
    """Return transcript/events; the temporary HOME is deleted even after failure."""
    if os.uname().sysname != 'Darwin' or os.geteuid() == 0:
        raise ValueError('Use macOS as a normal user for this PTY rehearsal')
    with tempfile.TemporaryDirectory(prefix='dotfiles-rehearsal-') as temporary:
        root = Path(temporary)
        home = root / 'home'
        home.mkdir()
        binaries = root / 'bin'
        binaries.mkdir()
        for name in ('sudo', 'curl', 'brew', 'yadm', 'mise', 'gh', 'open', 'defaults', 'pmset', 'killall', 'reboot', 'shutdown', 'osascript'):
            target = binaries / name
            target.write_text(STUB)
            target.chmod(0o700)
        for relative in ('.local/bin/dotfiles', '.config/dotfiles/install.sh'):
            target = home / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('#!/bin/bash\necho "[SIM] verification/service operation"\n')
            target.chmod(0o700)
        # Exercise the production profile too. Replace only its OS commands.
        profile = home / '.config/dotfiles/scripts/macos-personal.py'
        profile.parent.mkdir(parents=True, exist_ok=True)
        original = Path(source).resolve().parent / '.config/dotfiles/scripts/macos-personal.py'
        profile_text = original.read_text()
        for command in ('sudo', 'pmset'):
            profile_text = profile_text.replace('/usr/bin/' + command, str(binaries / command))
        profile.write_text(profile_text)
        (home / '.local/bin/dotfiles').write_text("#!/bin/bash\nif [[ $1 == macos ]]; then shift; exec /usr/bin/python3 \"$HOME/.config/dotfiles/scripts/macos-personal.py\" \"$@\"; fi\necho '[SIM] verification operation'\n")
        if scenario == 'existing':
            (root / 'brew-ready').touch()
        # Platform-boundary replacement only. Keep production branching, order,
        # terminal reads, logging, failure handling and cleanup intact.
        script = Path(source).read_text()
        for command in ('sudo', 'curl'):
            script = script.replace('/usr/bin/' + command, shlex.quote(str(binaries / command)))
        script = script.replace('/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:', '')
        script = script.replace('sleep 30', 'sleep 0.05')
        script = script.replace('set -euo pipefail', '''set -euo pipefail
command() {
    if [[ "$*" == '-v brew' && ! -f "$SIM_ROOT/brew-ready" ]]; then return 1; fi
    builtin command "$@"
}''', 1)
        target = root / 'setup.sh'
        target.write_text(script)
        env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'),
                   PATH=str(binaries) + ':/usr/bin:/bin:/usr/sbin:/sbin',
                   SIM_ROOT=str(root), SIM_SCENARIO=scenario)
        master, slave = pty.openpty()
        process = subprocess.Popen(['bash', str(target), '--profile', 'personal'],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        os.set_blocking(master, False)
        chunks, events, handled = [], [], set()
        group = 0
        downloads_since_input = True
        bulk = False
        deadline = time.monotonic() + 30
        try:
            while process.poll() is None or select.select([master], [], [], 0)[0]:
                if time.monotonic() > deadline:
                    raise RuntimeError('Rehearsal stalled:\n' + b''.join(chunks).decode(errors='replace'))
                if not select.select([master], [], [], 0.1)[0]:
                    continue
                try:
                    chunk = os.read(master, 65536)
                    if not chunk: break
                except BlockingIOError:
                    continue
                except OSError:
                    break
                chunks.append(chunk)
                text = b''.join(chunks).decode(errors='replace')
                # Record first occurrences in their actual stream order.
                markers = ['[SIM] Homebrew / Command Line Tools download', '[SIM_USER:administrator-auth]', '[SIM_DOWNLOAD:priority-apps]',
                           '[SIM_USER:github-2fa]', '完了・確認後にEnter。',
                           '[SIM_BULK_START]', '[SIM_USER:late-package-input]']
                pending = sorted((text.index(marker), marker) for marker in markers if marker in text and marker not in handled)
                for _, marker in pending:
                    handled.add(marker)
                    if marker in ('[SIM_DOWNLOAD:priority-apps]', '[SIM] Homebrew / Command Line Tools download'):
                        downloads_since_input = True
                        events.append({'actor': 'system', 'action': 'priority-app-download' if 'priority-apps' in marker else 'foundation-download'})
                    elif marker == '[SIM_BULK_START]':
                        bulk = True
                        events.append({'actor': 'system', 'action': 'bulk-start'})
                    elif marker == '完了・確認後にEnter。':
                        if scenario != 'existing':
                            if downloads_since_input:
                                group += 1
                            for approval in APP_APPROVALS:
                                events.append({'actor': 'user', 'action': approval, 'group': group, 'after_bulk': bulk})
                            downloads_since_input = False
                        events.append({'actor': 'agent', 'action': 'check-apps-and-send-enter'})
                        os.write(master, b'\n')
                    else:
                        action = marker[len('[SIM_USER:'):-1]
                        if downloads_since_input:
                            group += 1
                        downloads_since_input = False
                        events.append({'actor': 'user', 'action': action, 'group': group, 'after_bulk': bulk})
                        os.write(master, b'simulated-approval\n')
            code = process.wait(timeout=2)
            state = home / 'state/dotfiles/setup'
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            user = [event for event in events if event['actor'] == 'user']
            return {
                'scenario': scenario, 'exit_code': code,
                'user_operations': len(user), 'attention_groups': len({event['group'] for event in user}),
                'user_operations_after_bulk': sum(event['after_bulk'] for event in user),
                'auth_revoked': any(call[0] == 'sudo' and call[2] == ['-k'] for call in calls),
                'lock_released': not (state / 'lock').exists(), 'events': events,
                'transcript': b''.join(chunks).decode(errors='replace'),
                'settings': json.loads((root / 'preferences.json').read_text()) if (root / 'preferences.json').exists() else {},
                'power': json.loads((root / 'power.json').read_text()) if (root / 'power.json').exists() else {},
                'calls': calls,
                'scope': 'Synthetic approvals and compressed downloads; no real OS authentication or installation.',
            }
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[3] / 'setup.sh')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    directory = args.output_dir or Path(tempfile.mkdtemp(prefix='dotfiles-rehearsal-report-'))
    directory.mkdir(parents=True, exist_ok=True)
    results = [rehearse(args.source, scenario) for scenario in ('fresh', 'existing', 'auth-loss', 'late-input', 'package-failure', 'macos-auth-loss', 'macos-write-failure')]
    (directory / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    for result in results:
        (directory / (result['scenario'] + '.txt')).write_text(result['scope'] + '\n\n' + result['transcript'])
        print(f"{result['scenario']}: exit={result['exit_code']} user={result['user_operations']} groups={result['attention_groups']} after-bulk={result['user_operations_after_bulk']} revoked={result['auth_revoked']}")
    print('Rehearsal reports:', directory)


if __name__ == '__main__':
    main()
