#!/bin/bash
# 段階ごとに再実行できる dotfiles セットアップ。
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
PHASES=()
usage() {
    cat <<'HELP'
Usage: ./install.sh [--check] [--packages] [--apply] [--launchagents] [--all] [--dry-run]
  --check         依存とシェル構文を確認（書き込みなし）
  --packages      Brewfile のパッケージをインストール
  --apply         chezmoi の差分表示と適用
  --launchagents  macOS の既存 LaunchAgent を再登録
  --all           上記すべてを実行
  --dry-run       選んだ段階のコマンドだけ表示（書き込みなし）
引数なし: check → apply → launchagents（従来と同じセットアップ範囲）
複数の段階を指定した場合は check → packages → apply → launchagents の順。
HELP
}
CHECK=false PACKAGES=false APPLY=false AGENTS=false
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=true ;;
        --packages) PACKAGES=true ;;
        --apply) APPLY=true ;;
        --launchagents) AGENTS=true ;;
        --all) CHECK=true; PACKAGES=true; APPLY=true; AGENTS=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf '不明な引数: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done
if ! $CHECK && ! $PACKAGES && ! $APPLY && ! $AGENTS; then
    CHECK=true APPLY=true AGENTS=true
fi
$CHECK && PHASES+=(check)
$PACKAGES && PHASES+=(packages)
$APPLY && PHASES+=(apply)
$AGENTS && PHASES+=(launchagents)
require() {
    command -v "$1" >/dev/null 2>&1 || { printf '必要なコマンドがありません: %s\n' "$1" >&2; exit 1; }
}
run() {
    if $DRY_RUN; then
        printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}
save_source_config() {
    local escaped_source="$DOTFILES_DIR"
    escaped_source=${escaped_source//\\/\\\\}
    escaped_source=${escaped_source//\"/\\\"}
    escaped_source=${escaped_source//$'\n'/\\n}
    escaped_source=${escaped_source//$'\r'/\\r}
    escaped_source=${escaped_source//$'\t'/\\t}
    printf 'sourceDir = "%s"\n' "$escaped_source" > "$1"
}
for phase in "${PHASES[@]}"; do
    printf '\n== %s ==\n' "$phase"
    case "$phase" in
        check)
            if ! $DRY_RUN; then require brew; require zsh; fi
            run bash "$DOTFILES_DIR/scripts/check.sh"
            ;;
        packages)
            $DRY_RUN || require brew
            run brew bundle --file="$DOTFILES_DIR/Brewfile"
            ;;
        apply)
            $DRY_RUN || require chezmoi
            # 暗号化など既存設定は上書きしない。新規端末だけ sourceDir を保存。
            config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"
            if [[ ! -f "$config_dir/chezmoi.toml" && ! -f "$config_dir/chezmoi.yaml" && ! -f "$config_dir/chezmoi.yml" && ! -f "$config_dir/chezmoi.json" && ! -f "$config_dir/chezmoi.jsonc" ]]; then
                run mkdir -p "$config_dir"
                run save_source_config "$config_dir/chezmoi.toml"
            fi
            run chezmoi --source="$DOTFILES_DIR" --no-pager diff
            run chezmoi --source="$DOTFILES_DIR" apply
            ;;
        launchagents)
            if [[ "$(uname -s)" != Darwin ]]; then
                printf 'LaunchAgent は macOS 専用です。\n' >&2; exit 1
            fi
            $DRY_RUN || require launchctl
            run mkdir -p "$HOME/.claude/logs"
            for agent in "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" "$HOME/Library/LaunchAgents/com.claude.brewfile-sync.plist"; do
                if [[ -f "$agent" ]] || $DRY_RUN; then
                    run launchctl unload "$agent" || true
                    run launchctl load -w "$agent"
                fi
            done
            ;;
    esac
done
printf '\n完了。シェル設定の反映: source ~/.zshrc\n'
