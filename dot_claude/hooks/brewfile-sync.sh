#!/bin/bash
# Brewfile を実際の Homebrew 環境の状態に同期し、差分があれば自動 commit する。
# push は行わない。誤って壊れた状態や意図しないパッケージ変更をそのまま
# リモートへ送らないよう、次に dotfiles を触ったタイミングで手動 push する運用とする。
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

cd "$DOTFILES_DIR"

# Brewfile 以外に未コミットの変更が残っている場合、それを巻き込んで
# commit してしまわないよう自動更新を見送る（作業中の変更を尊重する）
if ! git diff --quiet -- . ':!Brewfile' || ! git diff --cached --quiet -- . ':!Brewfile'; then
    log "Brewfile 以外に未コミットの変更があるため、自動 commit をスキップします"
    exit 0
fi

brew bundle dump --force --no-vscode --file="$DOTFILES_DIR/Brewfile"

if git diff --quiet -- Brewfile; then
    log "Brewfile に変更なし"
    exit 0
fi

git add Brewfile
git commit -q -m "chore: Brewfile を自動更新 ($(date '+%Y-%m-%d'))"
log "Brewfile の変更を commit しました（push は未実行、手動で行ってください）"
