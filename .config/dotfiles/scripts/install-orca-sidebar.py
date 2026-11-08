#!/usr/bin/python3
"""Install the per-machine Orca sidebar sorter (run once on the machine you operate Orca from).

The sorter reads the operating client's tab state, so it belongs only on the Mac you
drive Orca with (the MacBook), not on the headless runtime host (the Mac mini).
"""
from pathlib import Path
import os
import plistlib
import subprocess

home = Path.home()
script = home / '.config/dotfiles/scripts/orca-sidebar.js'
log = home / '.claude/logs/orca-sidebar.log'
log.parent.mkdir(parents=True, exist_ok=True)
label = 'com.junhat6.orca-sidebar'
agent = home / 'Library/LaunchAgents' / (label + '.plist')
agent.parent.mkdir(parents=True, exist_ok=True)
# launchd 経由だと Orca 本体が毎回 codesign_util の無害な警告を出すので、その行だけ捨てる。
# スクリプト自身の終了コードは保つ。
wrapper = ('e=$(/usr/bin/mktemp) || exit 1; /Applications/Orca.app/Contents/MacOS/Orca "$0" 2>"$e"; rc=$?; '
           '/usr/bin/grep -v codesign_util "$e" 1>&2; /bin/rm -f "$e"; exit $rc')
config = dict(Label=label, ProgramArguments=['/bin/sh', '-c', wrapper, str(script)],
              EnvironmentVariables={'ELECTRON_RUN_AS_NODE': '1'},
              StartInterval=60, RunAtLoad=True, ProcessType='Background',
              StandardOutPath=str(log), StandardErrorPath=str(log))
if agent.exists() and plistlib.loads(agent.read_bytes()) != config:
    raise SystemExit('Existing LaunchAgent differs; review before replacing it')
agent.write_bytes(plistlib.dumps(config))
domain = 'gui/' + str(os.getuid())
if subprocess.run(['launchctl', 'print', domain + '/' + label], capture_output=True).returncode:
    subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
print('Installed:', agent)
print('Schedule: every minute while Orca is running. Log:', log)
