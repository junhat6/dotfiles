#!/bin/bash
# この PC の Homebrew 環境を Brewfile.local に記録する。
# 共通の Brewfile と Git の履歴は自動で変更しない。
#
# LaunchAgent (com.claude.brewfile-sync) から日次で呼び出される想定。
# usage: brewfile-sync.sh [--once]
#   --once: 手動実行用のエイリアス（動作は通常起動と同じ）

set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

if ! command -v brew >/dev/null 2>&1; then
    log "[ERROR] brew が見つかりません"
    exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
    log "[ERROR] chezmoi が見つかりません"
    exit 1
fi

DOTFILES_DIR="$(chezmoi source-path)"
if [ -z "$DOTFILES_DIR" ] || [ ! -d "$DOTFILES_DIR/.git" ]; then
    log "[ERROR] chezmoi source-path (${DOTFILES_DIR}) が dotfiles の git リポジトリではありません"
    exit 1
fi

brew bundle dump --force --no-vscode --file="$DOTFILES_DIR/Brewfile.local"
log "この PC のパッケージ一覧を Brewfile.local に保存しました"
