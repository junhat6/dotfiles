#!/bin/bash
# Daily maintenance as the logged-in user; never ask for a password or quit apps.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NONINTERACTIVE=1 HOMEBREW_NO_ASK=1
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_UPGRADE_QUIT_CASKS=1
export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
export SUDO_ASKPASS=/usr/bin/false
unset HOMEBREW_UPGRADE_GREEDY HOMEBREW_UPGRADE_GREEDY_CASKS
unset HOMEBREW_NO_INSTALL_UPGRADE HOMEBREW_NO_UPDATE_REPORT_NEW
exec </dev/null
printf '[%s] Homebrew maintenance started\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
result=0
brew update || exit $?
brew upgrade --formula || result=1
# auto_updates casks (including Orca) are excluded by Homebrew by default.
# --no-quit defers running applications instead of terminating them.
brew upgrade --cask --greedy-latest --no-quit || result=1
printf '[%s] Homebrew maintenance exit=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result"
exit "$result"
