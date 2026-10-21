#!/bin/bash
# macOS's Bash 3.2 + curl are sufficient to start, including before CLT exists.
set -euo pipefail
PROFILE= STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/setup"
DRY_RUN=false STATUS=false NO_UI=false
usage() {
    cat <<'EOF'
Usage: bash setup.sh --profile personal|work|none [--dry-run] [--no-ui]
       bash setup.sh --status
Run in one interactive terminal (an agent may attach a PTY).
--no-ui defers app approvals; it does not claim those approvals are complete.
EOF
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) [[ $# -gt 1 ]] || { usage; exit 2; }; PROFILE=$2; shift ;;
        --dry-run) DRY_RUN=true ;; --status) STATUS=true ;; --no-ui) NO_UI=true ;;
        --help|-h) usage; exit 0 ;; *) usage >&2; exit 2 ;;
    esac
    shift
done
if $STATUS; then
    if [[ -f "$STATE/current" ]]; then cat "$STATE/current"; else echo 'not started'; fi
    echo "Logs: $STATE/runs"
    exit 0
fi
case "$PROFILE" in personal|work|none) ;; *) usage >&2; exit 2 ;; esac
if $DRY_RUN; then
    cat <<EOF
Profile: $PROFILE
1. Authenticate sudo once; renew only while this setup lives; revoke on exit.
2. Install Homebrew/CLT, then only Karabiner/Hammerspoon.
3. Prepare dotfiles; verify priority apps, clear quarantine only after signature/notarization pass, launch for approvals; prepare GitHub CLI.
4. Authenticate GitHub using the existing browser (Safari is sufficient).
5. Agent confirms OS approvals; user can leave after authentication.
6. Restore vaults ($PROFILE), remaining Brewfile packages; verify app signatures/notarization and prepare eligible apps; install mise tools with timed logs.
7. Verify dependencies; enable validated services.
8. Apply shared Dock/keyboard/display-sleep settings without prompting.
9. Finish reports, then offer one final Mac restart for cached settings/pending driver activation.
State: $STATE
No sudoers, Gatekeeper, TCC database or agent permission settings are changed.
EOF
    exit 0
fi
[[ $(uname -s) == Darwin ]] || { echo 'macOS only' >&2; exit 2; }
[[ $EUID -ne 0 ]] || { echo 'Run as your normal user, not sudo bash.' >&2; exit 2; }
[[ -t 0 && -t 1 ]] || { echo 'An interactive terminal/PTY is required for initial authentication.' >&2; exit 2; }
umask 077
mkdir -p "$STATE/runs"
LOCK="$STATE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Setup is already running, or its lock survived a forced termination: $LOCK" >&2
    echo 'Check the recorded PID before manually removing a stale lock.' >&2
    [[ ! -f "$LOCK/pid" ]] || cat "$LOCK/pid" >&2
    exit 2
fi
echo "$$" > "$LOCK/pid"
RUN_DIR=$(mktemp -d "$STATE/runs/$(date +%Y%m%d-%H%M%S).XXXXXX")
KEEPER= HEARTBEAT= SUDO_ACTIVE=false PHASE=starting
write_status() { printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$PHASE" "$RUN_DIR" > "$STATE/current.tmp"; mv "$STATE/current.tmp" "$STATE/current"; }
cleanup() {
    local result=$?
    trap - EXIT INT TERM HUP
    [[ -z "$HEARTBEAT" ]] || { kill "$HEARTBEAT" 2>/dev/null || true; wait "$HEARTBEAT" 2>/dev/null || true; }
    [[ -z "$KEEPER" ]] || { kill "$KEEPER" 2>/dev/null || true; wait "$KEEPER" 2>/dev/null || true; }
    if $SUDO_ACTIVE; then /usr/bin/sudo -k; fi
    if [[ $result -ne 0 ]]; then write_status "stopped:$result"; fi
    rm -f "$LOCK/pid"
    rmdir "$LOCK"
    printf '\nSetup exit=%s. Temporary sudo authentication has been invalidated.\nLogs: %s\n' "$result" "$RUN_DIR"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
run() {
    local start result
    PHASE=$1; shift
    write_status running
    if [[ -f "$RUN_DIR/sudo-renewal-failed" ]]; then
        echo 'Authentication renewal failed; rerun setup in one terminal.' >&2
        return 1
    fi
    start=$(date +%s)
    printf '\n[%s] START %s\n' "$(date +%H:%M:%S)" "$PHASE"
    (trap - EXIT INT TERM HUP; while sleep 30; do printf '[%s] %s: still running (%ss)\n' "$(date +%H:%M:%S)" "$PHASE" "$(( $(date +%s) - start ))"; done) &
    HEARTBEAT=$!
    set +e
    "$@" </dev/null 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
        printf '[%s] %s\n' "$(date +%H:%M:%S)" "$line"
    done | tee "$RUN_DIR/$PHASE.log"
    result=${PIPESTATUS[0]}
    set -e
    kill "$HEARTBEAT" 2>/dev/null || true
    wait "$HEARTBEAT" 2>/dev/null || true
    HEARTBEAT=
    printf '%s\t%s\t%s\n' "$PHASE" "$result" "$(( $(date +%s) - start ))" >> "$RUN_DIR/timings.tsv"
    [[ $result -eq 0 ]] || return "$result"
    printf '[%s] DONE %s (%ss)\n' "$(date +%H:%M:%S)" "$PHASE" "$(( $(date +%s) - start ))"
}
echo '最初に管理者認証を行います。パスワードをAIや設定ファイルへ渡す必要はありません。'
echo 'GitHub認証とアプリの初回許可を、大量インストールより先にまとめます。'
PHASE=administrator-auth; write_status waiting-for-user
# Arm revocation before authentication: a signal can arrive immediately after
# sudo succeeds, before the next Bash assignment gets a chance to run.
SUDO_ACTIVE=true
/usr/bin/sudo -v
PARENT_PID=$$
# Same controlling terminal: sudo's normal per-terminal timestamp is reused.
# kill -0 also stops renewal if the parent is killed without running its traps.
(
    renewal_sleep=
    trap '[[ -z "$renewal_sleep" ]] || kill "$renewal_sleep" 2>/dev/null || true; /usr/bin/sudo -k' EXIT
    trap 'exit 0' INT TERM HUP
    while :; do
        sleep 30 & renewal_sleep=$!
        wait "$renewal_sleep" || exit
        renewal_sleep=
        kill -0 "$PARENT_PID" 2>/dev/null || exit
        /usr/bin/sudo -n -v || { touch "$RUN_DIR/sudo-renewal-failed"; echo 'sudo renewal failed; rerun setup.' >&2; exit 1; }
    done
) &
KEEPER=$!
# Fail rather than opening a late password prompt if cached authentication is lost.
cat > "$RUN_DIR/no-password-prompt.sh" <<'EOF'
#!/bin/bash
echo 'Cached sudo authentication was lost. Rerun setup in one terminal; no password was stored.' >&2
exit 1
EOF
chmod 700 "$RUN_DIR/no-password-prompt.sh"
export SUDO_ASKPASS="$RUN_DIR/no-password-prompt.sh"
# Homebrew 7's sudo capability probe clears timestamps. We already validated sudo
# above, so reuse its process-local capability cache, not a passwordless rule.
# Older/newer versions may ignore this internal flag; askpass then fails closed.
export HOMEBREW_SUDO_CHECKED=1
export HOMEBREW_NO_INSTALL_UPGRADE=1
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
if ! command -v brew >/dev/null 2>&1; then
    run homebrew-download /usr/bin/curl --fail --location --retry 3 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$RUN_DIR/homebrew.sh"
    run homebrew env NONINTERACTIVE=1 /bin/bash "$RUN_DIR/homebrew.sh"
fi
export HOMEBREW_NO_AUTO_UPDATE=1
# Only these apps need early macOS approvals. Install first; launch only after
# the checked-out verification helper has assessed their signature/notarization.
run permission-apps brew install --cask karabiner-elements hammerspoon
run foundation brew install yadm mise
for setting in auto-private-dirs auto-perms auto-alt; do yadm config "yadm.$setting" false; done
NEW_CLONE=false
if ! yadm rev-parse --git-dir >/dev/null 2>&1; then
    touch "$STATE/needs-checkout"
    run dotfiles-clone yadm clone --no-checkout --no-bootstrap https://github.com/junhat6/dotfiles.git
    NEW_CLONE=true
fi
ORIGIN=$(yadm remote get-url origin)
case "$ORIGIN" in https://github.com/junhat6/dotfiles|https://github.com/junhat6/dotfiles.git|git@github.com:junhat6/dotfiles.git) ;; *) echo 'Existing yadm uses another repository; leaving it untouched.' >&2; exit 2 ;; esac
[[ $(yadm rev-parse --show-toplevel) == "$HOME" ]] || { echo 'yadm worktree must be HOME' >&2; exit 2; }
if ! $NEW_CLONE && [[ ! -f "$STATE/needs-checkout" ]]; then
    [[ $(yadm branch --show-current) == main ]] || { echo 'Return yadm to main before setup (existing branch was preserved).' >&2; exit 2; }
    yadm diff --cached --quiet || { echo 'Resolve staged dotfiles edits before setup; nothing was stashed/reset.' >&2; exit 2; }
    run dotfiles-update yadm pull --ff-only origin main
fi
# Materialize only this helper first; no conflicting HOME file is overwritten.
yadm show HEAD:.config/dotfiles/scripts/setup_machine.py > "$RUN_DIR/setup_machine.py"
HELPER="$RUN_DIR/setup_machine.py"
if $NEW_CLONE || [[ -f "$STATE/needs-checkout" ]]; then
    run dotfiles-checkout /usr/bin/python3 "$HELPER" checkout --backup "$RUN_DIR/backups"
    rm -f "$STATE/needs-checkout"
fi
run local-permissions /usr/bin/python3 "$HELPER" prepare-local
run bootstrap yadm bootstrap
run early-app-verification /usr/bin/python3 "$HELPER" prepare-apps --report "$RUN_DIR/app-verification-early.json" --cask karabiner-elements --cask hammerspoon
if ! $NO_UI; then
    for app in 'Karabiner-Elements' Hammerspoon; do open -a "$app" || true; done
    echo '権限対象アプリを起動しました。AIはCLI準備中にOS権限設定を進めてください。'
fi
run mise-trust mise trust "$HOME/.config/mise/config.toml"
run github-tool mise install gh
GH=$(mise which gh)
if ! "$GH" auth status --hostname github.com >/dev/null 2>&1; then
    PHASE=github-auth; write_status waiting-for-user
    echo 'GitHubのデバイス認証をここで完了してください。認証コードはログへ保存しません。'
    echo 'AIがブラウザを操作する場合は、このシェルのEnterもAIが送信できます。'
    "$GH" auth login --hostname github.com --git-protocol https --web --skip-ssh-key
fi
"$GH" auth status --hostname github.com >/dev/null 2>&1
run git-credentials /usr/bin/python3 "$HELPER" credentials
run notification-plan /usr/bin/python3 "$HELPER" notifications
if ! $NO_UI; then
    PHASE=app-permissions; write_status waiting-for-user
    cat <<EOF

ここで初回操作をまとめます（AIは .config/dotfiles/SETUP-AGENT.md を参照）。
・公式アプリの「開く」確認はAIが操作できます。
・Karabiner: background services / Accessibility / input capture / Driver Extension。
・Hammerspoon: Accessibility / login launch / reload config。
・通知: AIがnotifications.jsonの指定に従い、メッセージ／Game Centerの「通知を許可」をオフにして画面確認。追加の本人確認は不要。
・Obsidianとvaultは後で復元します。プラグイン等の追加同意が必要ならAIはこの時点で方針を確認します。
・Touch ID、GitHubの2FAなど本人認証だけユーザーが操作します。
・OSが再起動を案内しても「あとで」が選べる場合は保留し、残りの導入を続行します。
・再起動後にしか確認できないドライバは未検証として記録し、最後にまとめて確認します。

完了・確認後にEnter。未完了ならCtrl-Cで止め、同じコマンドで再開してください。
EOF
    read -r _confirmation
    echo '本人操作の確認が完了しました。以降はAIが監視し、完了・失敗・追加の本人操作が必要な場合だけお知らせします。'
fi
if [[ $PROFILE != none ]]; then run vaults /usr/bin/python3 "$HELPER" vaults --profile "$PROFILE"; fi
run packages brew bundle install --no-upgrade --verbose --file="$HOME/.config/dotfiles/Brewfile"
run app-verification /usr/bin/python3 "$HELPER" prepare-apps --report "$RUN_DIR/app-verification.json"
run runtimes mise install --yes
run runtime-check mise ls --missing
[[ -z $(mise ls --missing) ]] || { echo 'Some mise tools are missing.' >&2; exit 1; }
run package-check brew bundle check --file="$HOME/.config/dotfiles/Brewfile"
run dotfiles-check "$HOME/.local/bin/dotfiles" check
run auto-update bash "$HOME/.config/dotfiles/install.sh" --auto-update
run services /usr/bin/python3 "$HELPER" services --profile "$PROFILE"
run macos-settings env DOTFILES_SETUP_NONINTERACTIVE=1 "$HOME/.local/bin/dotfiles" macos apply
run report /usr/bin/python3 "$HELPER" report --profile "$PROFILE" --run-dir "$RUN_DIR"
if $NO_UI; then PHASE=app-permissions; write_status attention-required; echo 'GUI permissions/first launch were deferred (--no-ui).'; exit 2; fi
PHASE=complete; write_status complete
echo 'セットアップ完了。認証情報・状態・バックアップは端末内だけに保存しました。'
echo 'FINAL_RESTART: 全工程の処理が終了しました。キーリピートと保留中のドライバ反映をまとめるため、作業を保存してMacを最後に1回再起動してください（自動再起動はしません）。再起動後に未検証の権限・キー操作を確認します。'
