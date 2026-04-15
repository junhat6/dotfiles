# Dotfiles

個人用の dotfiles セット。chezmoi で管理。

## 構成

```
dotfiles/
├── dot_claude/       # Claude Code 設定・hooks
├── dot_config/
│   ├── ghostty/      # Ghostty ターミナル設定
│   ├── karabiner/    # Karabiner-Elements 設定
│   ├── lazygit/      # lazygit 設定（delta pager）
│   └── nvim/         # Neovim (LazyVim)
├── dot_gitconfig     # .gitconfig（エイリアス・delta設定）
├── dot_hammerspoon/  # Hammerspoon (macOS 自動化)
├── dot_tmux.conf     # tmux 設定
├── dot_zshrc         # zsh 設定
├── dot_zprofile      # zsh 環境変数
├── Library/
│   └── LaunchAgents/ # macOS LaunchAgents
├── Brewfile          # Homebrew パッケージ一覧
├── install.sh        # セットアップスクリプト
└── .chezmoiignore    # chezmoi 管理対象外リスト
```

## インストール

```bash
git clone https://github.com/JunichiHattori/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Homebrew パッケージを一括インストール
brew bundle

# dotfiles をホームディレクトリへ展開
./install.sh
source ~/.zshrc
```

`install.sh` は chezmoi を使って各ファイルを `$HOME` へ展開します。既存ファイルがある場合は差分を表示してから適用するため、コンフリクトが起きません。

## chezmoi の使い方

```bash
chezmoi diff          # ホームとの差分を確認
chezmoi apply         # dotfiles をホームへ反映
chezmoi update        # git pull + apply を一括実行（リモート変更の取り込み）
chezmoi add <file>    # 新しいファイルを管理対象に追加
chezmoi re-add <file> # ホーム側の変更をソースへ取り込む
chezmoi edit <file>   # ソースを編集して即反映
chezmoi cd            # ソースディレクトリへ移動
```

### Brewfile の管理

```bash
# 現在の環境を Brewfile に反映（VSCode 拡張を除く）
brew bundle dump --force --no-vscode

# Brewfile にあって未インストールのものを確認
brew bundle check

# Brewfile にないパッケージを一括削除
brew bundle cleanup
```

## 依存ツール

`Brewfile` で管理しています。主なもの:

| ツール | 用途 |
|---|---|
| chezmoi | dotfiles 管理 |
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
- エイリアス: `ll/la/lt/llt`（eza）、`cc`（claude）、`lg`（lazygit）、`v`（nvim）、`ta`（tmux attach）

### git / delta
- Side-by-side diff・行番号・シンタックスハイライト（Catppuccin Latte）
- エイリアス: `g st/ad/cm/co/lg/lga/p/undo/amend/cleanup/snap`

### Neovim
- LazyVim ベース。詳細は [`dot_config/nvim/README.md`](dot_config/nvim/README.md)

## Git ユーザー情報の更新

`dot_gitconfig` を直接編集して chezmoi で反映してください。

```bash
chezmoi edit ~/.gitconfig
chezmoi apply
```
