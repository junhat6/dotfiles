# Dotfiles

個人用の dotfiles セット。GNU Stow で管理。

## 構成

```
dotfiles/
├── claude/       # Claude Code 設定・hooks
├── ghostty/      # Ghostty ターミナル設定
├── git/          # .gitconfig（エイリアス・delta設定）
├── hammerspoon/  # Hammerspoon (macOS 自動化)
├── LaunchAgents/ # macOS LaunchAgents
├── lazygit/      # lazygit 設定（delta pager）
├── nvim/         # Neovim (LazyVim)
├── tmux/         # tmux 設定
└── zsh/          # .zshrc / .zprofile
```

## インストール

```bash
git clone https://github.com/JunichiHattori/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Homebrew パッケージを一括インストール
brew bundle

# シンボリックリンクを作成
./install.sh
source ~/.zshrc
```

`install.sh` は `stow` を使って各パッケージのシンボリックリンクを `$HOME` に作成します。

### Brewfile の管理

```bash
# 現在の環境を Brewfile に反映
brew bundle dump --force

# Brewfile にあって未インストールのものを確認
brew bundle check

# Brewfile にないパッケージを一括削除
brew bundle cleanup
```

## 依存ツール

`Brewfile` で管理しています。主なもの:

| ツール | 用途 |
|---|---|
| stow | dotfiles リンク管理 |
| fzf | ファジーファインダー（Ctrl-T / Ctrl-G / Ctrl-Q） |
| eza | `ls` 代替（アイコン・Git情報付き） |
| bat | `cat` 代替（シンタックスハイライト） |
| ripgrep | 高速 grep |
| zoxide | スマート `cd` |
| ghq | Git リポジトリ管理 |
| starship | モダンなプロンプト |
| direnv | ディレクトリ別環境変数 |
| mise | 言語バージョン管理 |
| git-delta | Git diff の見た目改善 |
| lazygit | TUI Git クライアント |
| tmux | ターミナルマルチプレクサ |
| zsh-syntax-highlighting | zsh コマンドのシンタックスハイライト |

## 主な機能

### zsh
- 補完: `compinit`・大文字小文字無視・メニュー選択
- 履歴: 重複排除・スペース始まり無視・共有履歴
- `Ctrl-Q`: zoxide 一覧を fzf で選んで移動（eza プレビュー付き）
- `Ctrl-G`: ghq リポジトリを fzf で選んで移動
- `gb`: ブランチを fzf で選んでチェックアウト
- エイリアス: `ll/la/lt/llt`（eza）、`cc`（claude）、`lg`（lazygit）、`v`（nvim）、`ta`（tmux attach）

### git / delta
- Side-by-side diff・行番号・シンタックスハイライト（Catppuccin Latte）
- エイリアス: `g st/ad/cm/co/lg/lga/p/undo/amend/cleanup/snap`

### Neovim
- LazyVim ベース。詳細は [`nvim/.config/nvim/README.md`](nvim/.config/nvim/README.md)

## Git ユーザー情報の更新

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```
