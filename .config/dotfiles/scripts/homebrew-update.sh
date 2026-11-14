#!/bin/bash
# Daily maintenance as the logged-in user; never ask for a password or quit apps.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NONINTERACTIVE=1 HOMEBREW_NO_ASK=1
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_UPGRADE_QUIT_CASKS=1
unset HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS
export SUDO_ASKPASS=/usr/bin/false
unset HOMEBREW_UPGRADE_GREEDY HOMEBREW_UPGRADE_GREEDY_CASKS
unset HOMEBREW_NO_INSTALL_UPGRADE HOMEBREW_NO_UPDATE_REPORT_NEW
exec </dev/null
printf '[%s] Homebrew maintenance started\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
result=0
if brew update; then
  brew upgrade --formula || result=1
  # Include self-updating apps and nightly builds without quitting running apps.
  # Never replace a running Orca.app: its renderer lazy-loads hashed chunks from
  # app.asar, so swapping the bundle underneath it leaves a blank window.
  # A running Orca is updated by its own updater (orca-autoupdate) instead.
  if casks=$(brew outdated --cask --greedy --quiet); then
    if ps -axo comm= | grep -qE '/Orca\.app/Contents/MacOS/Orca$'; then
      casks=$(printf '%s\n' "$casks" | grep -vxE '(stablyai/orca/)?orca' || true)
    fi
    if [[ -n "$casks" ]]; then
      # shellcheck disable=SC2086
      brew upgrade --cask --greedy --no-quit $casks || result=1
    fi
  else
    result=1
  fi
else
  result=1
fi
# Only the shared environment: never read or modify project version pins.
# Keep old versions for rollback and avoid background confirmation prompts.
if command -v mise >/dev/null 2>&1; then
  mise upgrade --global --yes --no-prune || result=1
fi
printf '[%s] Homebrew maintenance exit=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result"
exit "$result"
