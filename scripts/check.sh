#!/bin/bash
# ローカルと GitHub Actions で共通の構文確認。設定は実行しない。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for file in "$ROOT/dot_zshrc" "$ROOT/dot_zprofile" "$ROOT"/dot_config/zsh/*.zsh; do
    zsh -n "$file"
done
for file in "$ROOT/install.sh" "$ROOT"/scripts/*.sh "$ROOT"/dot_claude/hooks/*.sh "$ROOT/dot_claude/statusline-command.sh"; do
    bash -n "$file"
done
git config --file "$ROOT/dot_gitconfig" --list >/dev/null
printf 'Zsh / Bash / Git 設定の構文チェックに成功しました。\n'
