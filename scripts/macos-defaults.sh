#!/bin/bash
# 選んだ Finder 設定だけ適用。初回の値を保存し、--restore で戻せる。
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { printf 'macOS 専用です。\n' >&2; exit 1; }
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/finder"
case "${1:---apply}" in
    --apply|--restore|--check) MODE="${1:---apply}" ;;
    *) printf 'Usage: bash scripts/macos-defaults.sh [--apply|--restore|--check]\n' >&2; exit 2 ;;
esac
for entry in 'NSGlobalDomain AppleShowAllExtensions' 'com.apple.finder ShowPathbar'; do
    read -r domain key <<< "$entry"
    saved="$STATE_DIR/$domain.$key"
    case "$MODE" in
        --check)
            printf '%s/%s: ' "$domain" "$key"
            defaults read "$domain" "$key" 2>/dev/null || printf '(未設定)\n'
            ;;
        --apply)
            mkdir -p "$STATE_DIR"
            if [[ ! -f "$saved" ]]; then
                if previous=$(defaults read "$domain" "$key" 2>/dev/null); then
                    printf '%s\n' "$previous" > "$saved"
                else
                    printf 'UNSET\n' > "$saved"
                fi
            fi
            defaults write "$domain" "$key" -bool true
            ;;
        --restore)
            [[ -f "$saved" ]] || { printf '元の値がありません: %s\n' "$saved" >&2; exit 1; }
            previous=$(cat "$saved")
            if [[ "$previous" == UNSET ]]; then
                defaults delete "$domain" "$key" 2>/dev/null || true
            else
                defaults write "$domain" "$key" -bool "$previous"
            fi
            ;;
    esac
done
[[ "$MODE" == --check ]] || printf 'Finder 設定を更新しました。次に開くウィンドウで確認してください。\n'
