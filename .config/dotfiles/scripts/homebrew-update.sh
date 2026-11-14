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
# One hung step (e.g. mise idling forever after installing) must not block every later
# run: launchd never starts the next 04:00 run while this one is still alive.
STEP_TIMEOUT="${HOMEBREW_UPDATE_STEP_TIMEOUT:-3600}"
KILL_GRACE="${HOMEBREW_UPDATE_KILL_GRACE:-10}"
limited() {
  # Own process group, so a timeout also stops children (mise/brew spawn helpers).
  set -m
  "$@" &
  local pid=$!
  set +m
  local ticks=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( ticks >= STEP_TIMEOUT * 5 )); then
      printf 'Step timed out after %ss: %s\n' "$STEP_TIMEOUT" "$*"
      kill -TERM -- "-$pid" 2>/dev/null || true
      sleep "$KILL_GRACE"
      kill -KILL -- "-$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.2
    ticks=$((ticks + 1))
  done
  wait "$pid"
}
printf '[%s] Homebrew maintenance started\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
result=0
if limited brew update; then
  limited brew upgrade --formula || result=1
  # Include self-updating apps and nightly builds without quitting running apps.
  # Never replace a running Orca.app: its renderer lazy-loads hashed chunks from
  # app.asar, so swapping the bundle underneath it leaves a blank window.
  # A running Orca is updated by its own updater (orca-autoupdate) instead.
  if casks=$(limited brew outdated --cask --greedy --quiet); then
    if ps -axo comm= | grep -qE '/Orca\.app/Contents/MacOS/Orca$'; then
      casks=$(printf '%s\n' "$casks" | grep -vxE '(stablyai/orca/)?orca' || true)
    fi
    if [[ -n "$casks" ]]; then
      # shellcheck disable=SC2086
      limited brew upgrade --cask --greedy --no-quit $casks || result=1
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
  limited mise upgrade --global --yes --no-prune || result=1
fi
printf '[%s] Homebrew maintenance exit=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result"
exit "$result"
