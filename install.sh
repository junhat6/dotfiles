#!/bin/bash

# Dotfiles セットアップスクリプト

DOTFILES_DIR="$HOME/dotfiles"

echo "🚀 Dotfiles セットアップを開始します..."

# .gitconfig のシンボリックリンクを作成
if [ -f "$HOME/.gitconfig" ]; then
    echo "⚠️  既存の ~/.gitconfig が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.gitconfig" "$HOME/.gitconfig.backup"
        echo "✅ ~/.gitconfig を ~/.gitconfig.backup にバックアップしました"
    else
        echo "❌ .gitconfig のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.gitconfig" ]; then
    ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
    echo "✅ ~/.gitconfig のシンボリックリンクを作成しました"
fi

# .zprofile のシンボリックリンクを作成
if [ -f "$HOME/.zprofile" ]; then
    echo "⚠️  既存の ~/.zprofile が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.zprofile" "$HOME/.zprofile.backup"
        echo "✅ ~/.zprofile を ~/.zprofile.backup にバックアップしました"
    else
        echo "❌ .zprofile のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.zprofile" ]; then
    ln -sf "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
    echo "✅ ~/.zprofile のシンボリックリンクを作成しました"
fi

# .zshrc のシンボリックリンクを作成
if [ -f "$HOME/.zshrc" ]; then
    echo "⚠️  既存の ~/.zshrc が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
        echo "✅ ~/.zshrc を ~/.zshrc.backup にバックアップしました"
    else
        echo "❌ .zshrc のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.zshrc" ]; then
    ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
    echo "✅ ~/.zshrc のシンボリックリンクを作成しました"
fi

echo ""
echo "✨ セットアップが完了しました！"
echo ""
echo "次のステップ:"
echo "1. ~/.gitconfig の user.name と user.email を設定してください"
echo "   git config --global user.name \"Your Name\""
echo "   git config --global user.email \"your@email.com\""
echo ""
echo "2. 変更を反映するために、以下を実行してください:"
echo "   source ~/.zshrc"
