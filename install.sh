#!/bin/bash

# Dotfiles セットアップスクリプト (chezmoi)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Dotfiles セットアップを開始します..."

# chezmoi がインストールされているか確認
if ! command -v chezmoi &> /dev/null; then
    echo "chezmoi が見つかりません。インストールしてください: brew install chezmoi"
    exit 1
fi

# chezmoi 設定ディレクトリを作成し、ソースを指定
mkdir -p "$HOME/.config/chezmoi"
cat > "$HOME/.config/chezmoi/chezmoi.toml" << EOF
sourceDir = "$DOTFILES_DIR"
EOF

echo "chezmoi ソースディレクトリ: $DOTFILES_DIR"

# 差分を表示してから適用
echo ""
echo "適用される変更:"
chezmoi diff || true

echo ""
echo "適用中..."
chezmoi apply

echo ""
echo "セットアップが完了しました！"
echo ""
echo "次のステップ:"
echo "1. ~/.gitconfig の user.name と user.email を設定してください"
echo "   git config --global user.name \"Your Name\""
echo "   git config --global user.email \"your@email.com\""
echo ""
echo "2. 変更を反映するために、以下を実行してください:"
echo "   source ~/.zshrc"
