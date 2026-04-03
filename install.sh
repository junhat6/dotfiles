#!/bin/bash

# Dotfiles セットアップスクリプト

DOTFILES_DIR="$HOME/dotfiles"

echo "Dotfiles セットアップを開始します..."

# stow がインストールされているか確認
if ! command -v stow &> /dev/null; then
    echo "stow が見つかりません。インストールしてください: brew install stow"
    exit 1
fi

PACKAGES=(
    git
    zsh
    tmux
    ghostty
    lazygit
    nvim
    hammerspoon
    claude
    LaunchAgents
)

for pkg in "${PACKAGES[@]}"; do
    echo "Stowing $pkg..."
    stow --target="$HOME" --dir="$DOTFILES_DIR" "$pkg"
done

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
