# Dotfiles

個人用の dotfiles セット。chezmoi で管理。

## 構成

```
dotfiles/
├── dot_claude/       # Claude Code 設定・hooks
├── dot_config/
│   ├── atuin/        # atuin (シェル履歴) 設定
│   ├── ghostty/      # Ghostty ターミナル設定
│   ├── karabiner/    # Karabiner-Elements 設定
│   ├── lazygit/      # lazygit 設定
│   ├── nvim/         # Neovim (LazyVim)
│   └── wezterm/      # WezTerm ターミナル設定
├── dot_gitconfig     # .gitconfig
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

エイリアス・キーバインド・プラグイン構成などの詳細は、このREADMEには書かず各 `dot_*` ファイルを直接参照してください（変更のたびにREADMEを追随させる運用コストを避けるため）。

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

`install.sh` は chezmoi を使って各ファイルを `$HOME` へ展開します。既存ファイルがある場合は差分を表示してから適用するため、コンフリクトが起きません。また、Obsidian同期用のLaunchAgentも合わせて読み込みます。

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

## Git ユーザー情報の更新

`dot_gitconfig` を直接編集して chezmoi で反映してください。

```bash
chezmoi edit ~/.gitconfig
chezmoi apply
```

## macOS キーリピートをターミナル上で変更するコマンド

```bash
# キーリピートを最速に（デフォルト: 6、小さいほど速い）
defaults write NSGlobalDomain KeyRepeat -int 1

# キーリピート開始までの時間を短く（デフォルト: 25、小さいほど速い）
defaults write NSGlobalDomain InitialKeyRepeat -int 15
```
