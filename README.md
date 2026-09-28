# Dotfiles

個人用の dotfiles セット。chezmoi で管理。

## 構成

```
dotfiles/
├── dot_claude/       # Claude Code 設定・hooks（PC ごとの Brewfile 記録を含む）
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
├── Brewfile          # 各 PC で共通して使う Homebrew パッケージ一覧
├── Brewfile.local    # この PC のインストール済み一覧（自動生成・Git 管理外）
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

`install.sh` は chezmoi を使って各ファイルを `$HOME` へ展開します。適用前に差分を表示します。ホーム側で変更したファイルがあると chezmoi が上書きの確認を求めることがあります。Obsidian 同期と Brewfile.local 記録用の LaunchAgent も読み込みます。

## chezmoi の使い方

```bash
chezmoi diff          # ホームとの差分を確認
chezmoi apply         # dotfiles をホームへ反映
chezmoi update        # git pull + apply を一括実行（Git 履歴が分岐しているとコンフリクトすることがある）
chezmoi add <file>    # 新しいファイルを管理対象に追加
chezmoi re-add <file> # ホーム側の変更をソースへ取り込む
chezmoi edit <file>   # ソースを編集して即反映
chezmoi cd            # ソースディレクトリへ移動
```

### Brewfile の管理

`Brewfile` は複数の PC で共通して使いたいパッケージを手動で管理します。`Library/LaunchAgents/com.claude.brewfile-sync.plist` は毎日10時（および `install.sh` 実行直後）に `dot_claude/hooks/brewfile-sync.sh` を実行し、その PC のインストール済みパッケージを `Brewfile.local` に記録します。`Brewfile.local` は Git と chezmoi の管理対象外です。パッケージを全 PC で使いたいときだけ、内容を確認して `Brewfile` に追加してください。この自動処理はコミットも push もしません。

手動で操作したい場合は以下を使う。

```bash
# この PC のインストール済み一覧を Brewfile.local に記録
bash ~/.claude/hooks/brewfile-sync.sh

# 共通設定とこの PC の一覧を比較
diff -u Brewfile Brewfile.local

# 共通のパッケージをインストール
brew bundle --file=Brewfile

# Brewfile にあって未インストールのものを確認
brew bundle check --file=Brewfile
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
