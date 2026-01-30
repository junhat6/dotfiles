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

# Ghostty の設定ディレクトリとシンボリックリンクを作成
mkdir -p "$HOME/.config/ghostty"
if [ -f "$HOME/.config/ghostty/config" ] && [ ! -L "$HOME/.config/ghostty/config" ]; then
    echo "⚠️  既存の ~/.config/ghostty/config が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.config/ghostty/config" "$HOME/.config/ghostty/config.backup"
        echo "✅ ~/.config/ghostty/config を ~/.config/ghostty/config.backup にバックアップしました"
    else
        echo "❌ Ghostty config のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.config/ghostty/config" ]; then
    ln -sf "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"
    echo "✅ ~/.config/ghostty/config のシンボリックリンクを作成しました"
fi

# .tmux.conf のシンボリックリンクを作成
if [ -f "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
    echo "⚠️  既存の ~/.tmux.conf が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.backup"
        echo "✅ ~/.tmux.conf を ~/.tmux.conf.backup にバックアップしました"
    else
        echo "❌ .tmux.conf のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.tmux.conf" ]; then
    ln -sf "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"
    echo "✅ ~/.tmux.conf のシンボリックリンクを作成しました"
fi

# Hammerspoon の設定ディレクトリとシンボリックリンクを作成
mkdir -p "$HOME/.hammerspoon"
if [ -f "$HOME/.hammerspoon/init.lua" ] && [ ! -L "$HOME/.hammerspoon/init.lua" ]; then
    echo "⚠️  既存の ~/.hammerspoon/init.lua が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua.backup"
        echo "✅ ~/.hammerspoon/init.lua を ~/.hammerspoon/init.lua.backup にバックアップしました"
    else
        echo "❌ Hammerspoon init.lua のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.hammerspoon/init.lua" ]; then
    ln -sf "$DOTFILES_DIR/hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua"
    echo "✅ ~/.hammerspoon/init.lua のシンボリックリンクを作成しました"
fi

# Claude hooks のシンボリックリンクを作成
mkdir -p "$HOME/.claude/hooks"
if [ -f "$HOME/.claude/hooks/watch-and-save.sh" ] && [ ! -L "$HOME/.claude/hooks/watch-and-save.sh" ]; then
    echo "⚠️  既存の ~/.claude/hooks/watch-and-save.sh が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/.claude/hooks/watch-and-save.sh" "$HOME/.claude/hooks/watch-and-save.sh.backup"
        echo "✅ ~/.claude/hooks/watch-and-save.sh をバックアップしました"
    else
        echo "❌ watch-and-save.sh のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/.claude/hooks/watch-and-save.sh" ]; then
    ln -sf "$DOTFILES_DIR/.claude/hooks/watch-and-save.sh" "$HOME/.claude/hooks/watch-and-save.sh"
    echo "✅ ~/.claude/hooks/watch-and-save.sh のシンボリックリンクを作成しました"
fi

# LaunchAgents のシンボリックリンクを作成
mkdir -p "$HOME/Library/LaunchAgents"
if [ -f "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" ] && [ ! -L "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" ]; then
    echo "⚠️  既存の ~/Library/LaunchAgents/com.claude.obsidian-sync.plist が見つかりました"
    read -p "バックアップを作成して上書きしますか？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist.backup"
        echo "✅ ~/Library/LaunchAgents/com.claude.obsidian-sync.plist をバックアップしました"
    else
        echo "❌ LaunchAgent plist のリンク作成をスキップしました"
    fi
fi

if [ ! -L "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist" ]; then
    ln -sf "$DOTFILES_DIR/LaunchAgents/com.claude.obsidian-sync.plist" "$HOME/Library/LaunchAgents/com.claude.obsidian-sync.plist"
    echo "✅ ~/Library/LaunchAgents/com.claude.obsidian-sync.plist のシンボリックリンクを作成しました"
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
