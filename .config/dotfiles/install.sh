#!/bin/bash
# Re-runnable yadm bootstrap; checks never modify HOME.
set -euo pipefail
SUPPORT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SUPPORT/../.." && pwd)"
CHECK=false PACKAGES=false APPLY=false AGENTS=false DRY_RUN=false
usage() { echo 'Usage: install.sh [--check] [--packages] [--apply] [--launchagents] [--all] [--dry-run]'; }
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=true ;; --packages) PACKAGES=true ;; --apply) APPLY=true ;;
        --launchagents) AGENTS=true ;; --all) CHECK=true; PACKAGES=true; APPLY=true; AGENTS=true ;;
        --dry-run) DRY_RUN=true ;; -h|--help) usage; exit 0 ;; *) usage >&2; exit 2 ;;
    esac
done
if ! $CHECK && ! $PACKAGES && ! $APPLY && ! $AGENTS; then CHECK=true; APPLY=true; fi
run() { if $DRY_RUN; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
if [[ -x /usr/bin/python3 ]]; then PYTHON=/usr/bin/python3; else PYTHON=python3; fi
if $CHECK; then run bash "$SUPPORT/scripts/check.sh" "$ROOT"; fi
if $PACKAGES; then run brew bundle --file="$SUPPORT/Brewfile"; fi
if $APPLY; then
    # Clone/checkout is yadm's job. Bootstrap only configures repository hooks and local/generated files.
    if [[ "$ROOT" != "$HOME" ]]; then
        printf 'Bootstrap must run in a yadm HOME checkout; use yadm clone --no-bootstrap then yadm bootstrap.\n' >&2
        exit 1
    fi
    run yadm config yadm.auto-private-dirs false
    run yadm config yadm.auto-perms false
    run yadm config yadm.auto-alt false
    run yadm gitconfig core.hooksPath "$SUPPORT/git-hooks"
    run "$PYTHON" "$SUPPORT/scripts/dotfiles.py" --root "$ROOT" bootstrap-local
    run "$PYTHON" "$SUPPORT/scripts/dotfiles.py" --root "$ROOT" render
fi
if $AGENTS; then
    [[ "$(uname -s)" == Darwin ]] || { echo 'LaunchAgents require macOS' >&2; exit 1; }
    run mkdir -p "$HOME/.claude/logs"
    for agent in "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" "$HOME/Library/LaunchAgents/com.claude.brewfile-sync.plist"; do
        run launchctl unload "$agent" || true
        run launchctl load -w "$agent"
    done
fi
