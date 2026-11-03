#!/usr/bin/python3
"""Install the per-user three-hour Orca updater. Does not unpause manual pauses."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

home = Path.home()
base = home / 'Library/Application Support/OrcaAutoUpdate'
logs = home / 'Library/Logs/OrcaAutoUpdate'
base.mkdir(parents=True, exist_ok=True, mode=0o700)
logs.mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(__file__).with_name('orca-autoupdate.py'), base / 'orca-autoupdate.py')
label = 'com.junhat6.orca-autoupdate'
agent = home / 'Library/LaunchAgents' / (label + '.plist')
agent.parent.mkdir(parents=True, exist_ok=True)
config = dict(Label=label, ProgramArguments=['/usr/bin/python3', str(base / 'orca-autoupdate.py')],
              RunAtLoad=True, StartInterval=10800, ProcessType='Background',
              LimitLoadToSessionType='Aqua', ExitTimeOut=30,
              StandardOutPath=str(logs / 'launchd.log'), StandardErrorPath=str(logs / 'launchd.log'))
# Existing installed jobs already use this exact configuration. Refuse to silently
# alter a loaded job: leave any replacement/reload explicit.
if agent.exists() and plistlib.loads(agent.read_bytes()) != config:
    raise SystemExit('Existing LaunchAgent differs; review before replacing it')
agent.write_bytes(plistlib.dumps(config))
domain = 'gui/' + str(os.getuid())
loaded = subprocess.run(['launchctl', 'print', domain + '/' + label], capture_output=True)
if loaded.returncode:
    subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
print('Installed:', agent)
print('Schedule: every three hours while logged in; stable releases only.')
