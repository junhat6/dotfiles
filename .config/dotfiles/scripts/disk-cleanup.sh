#!/bin/bash
# Weekly disk cleanup as the logged-in user. Only removes things that are rebuilt or
# re-downloaded on demand (caches, unused tool versions, Chrome launch copies); never
# project files, worktrees, Docker volumes or anything that needs a password.
set -uo pipefail
export PATH="$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 SUDO_ASKPASS=/usr/bin/false
exec </dev/null
STEP_TIMEOUT="${DISK_CLEANUP_STEP_TIMEOUT:-1800}"
KILL_GRACE="${DISK_CLEANUP_KILL_GRACE:-10}"
# Chrome copies its app bundle here at every launch and deletes it on a clean exit.
# A force-quit (automation, crashes) leaves it behind: 104 copies were found on one Mac.
CHROME_ROOT="${DISK_CLEANUP_CHROME_ROOT:-$(dirname "$(getconf DARWIN_USER_TEMP_DIR)")/X}"
CLONE_MIN_AGE_MIN="${DISK_CLEANUP_CLONE_MIN_AGE_MIN:-1440}"

# Same reason as homebrew-update.sh: one hung step must not keep launchd from ever
# starting the next run. Own process group, so a timeout also stops helpers.
limited() {
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

free_space() { df -h "$HOME" | awk 'NR==2 {print $4}'; }

clean_chrome_clones() {
  local dirs=() dir root exes
  root=$(cd -P "$CHROME_ROOT" 2>/dev/null && pwd) || return 0
  shopt -s nullglob
  dirs=("$root"/com.google.Chrome*.code_sign_clone/code_sign_clone.*)
  shopt -u nullglob
  (( ${#dirs[@]} )) || return 0
  # A running Chrome executes from its copy. The copy's executable is a hard link to the
  # installed app, so lsof's path names are unreliable (it prints whichever link it finds).
  # Pass the files themselves: lsof matches those by inode. Copies of the version that is
  # running are therefore kept (they share its data and cost nothing); copies left from
  # older versions hold the space and go. If lsof cannot even see this shell, keep all.
  lsof -t -p "$$" 2>/dev/null | grep -qx "$$" || { echo 'lsof unavailable; Chrome copies kept'; return 1; }
  for dir in "${dirs[@]}"; do
    [[ -n "$(find "$dir" -maxdepth 0 -mmin +"$CLONE_MIN_AGE_MIN" 2>/dev/null)" ]] || continue
    exes=("$dir"/*/Contents/MacOS/*)
    [[ -e "${exes[0]}" ]] || continue  # unknown layout: leave it alone
    if lsof -t -- "${exes[@]}" 2>/dev/null | grep -q .; then
      continue
    fi
    rm -rf "$dir" && printf 'removed %s\n' "$dir"
  done
}

# mise prune decides what is still needed from every project config it has seen.
# Opening one under a privacy-protected folder from a background job waits on a TCC
# prompt nobody answers (see homebrew-update.sh), so forget those links first.
forget_protected_mise_configs() {
  local dir="${MISE_STATE_DIR:-$HOME/.local/state/mise}/tracked-configs" link
  [[ -d "$dir" ]] || return 0
  for link in "$dir"/*; do
    [[ -L "$link" ]] || continue
    case "$(readlink "$link")" in
      "$HOME/Documents/"*|"$HOME/Desktop/"*|"$HOME/Downloads/"*|"$HOME/Library/Mobile Documents/"*|"$HOME/Library/CloudStorage/"*|/Volumes/*)
        rm -f "$link" ;;
    esac
  done
}

printf '[%s] Disk cleanup started free=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(free_space)"
result=0
step() { limited "$@" || { printf 'Step failed: %s\n' "$*"; result=1; }; }

step clean_chrome_clones
if command -v brew >/dev/null 2>&1; then step brew cleanup -s --prune=all; fi
if command -v mise >/dev/null 2>&1; then
  forget_protected_mise_configs
  step mise cache clear
  # Old versions are kept by the daily `mise upgrade --no-prune` for a week of rollback.
  step mise prune --yes
fi
if command -v npm >/dev/null 2>&1; then step npm cache clean --force; fi
if command -v uv >/dev/null 2>&1; then step uv cache prune; fi
# Only when Docker is already running: never boot a VM just to clean it. Dangling
# images and build cache only; tagged images, containers and volumes stay.
if command -v docker >/dev/null 2>&1 && limited docker info >/dev/null 2>&1; then
  step docker image prune -f
  step docker builder prune -f --filter until=720h
fi

printf '[%s] Disk cleanup exit=%s free=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result" "$(free_space)"
exit "$result"
