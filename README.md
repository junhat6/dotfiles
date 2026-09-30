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

### Claude / Codex セッションの Obsidian 記録

`dot_claude/hooks/watch-and-save.sh` は Claude Code と Codex のローカル JSONL を監視します。`~/ghq/github.com/junhat6/` にある2つの vault の GitHub 接続先と Obsidian Git の `disablePush: false` を確認し、この Mac の書き手 vault を自動選択します。個人 Mac では個人 vault、会社 Mac では会社 vault です。両 vault の設定が揃っていない場合や、書き手が重複する場合は、誤った vault に書かないよう起動を止めます。Claude は `<vault>/claude/<repo>/<セッション開始日>/`、Codex は `<vault>/Codex/<repo>/<セッション開始日>/` に保存します。各日付フォルダの中は `<開始時刻> <タイトル> [Claude|Codex] <ID>.md` というセッション別ノートです。同じセッションを翌日再開しても、開始日の同じノートに続けます。ブランチ、エージェント、セッション ID を記録し、Issue が解決できた場合はリンクも付けます。

タイトルは Claude の `custom-title` / `ai-title`、Codex のローカルセッション DB の `name` を優先します。タイトルがまだ無い間は初回プロンプトまたは仮題を使い、後からタイトルが付いたらファイル名と見出しを更新します。AI に別途タイトル生成を依頼しません。`OBSIDIAN_DIR`、`CODEX_OBSIDIAN_DIR`、`SESSION_DIR`、`CODEX_SESSION_DIR`、`CODEX_STATE_DB`、`SYNC_STATE_DIR` で各パスを変更できます。手動で `OBSIDIAN_DIR` を指定した場合は自動選択しません。

`claude/` と `Codex/` は両 vault で Git の管理対象外です。個人 Mac の記録は個人 vault に保存し、Remotely Save で Dropbox 経由で iPhone に同期します。会社 Mac の記録は会社 vault に保存し、Dropbox は使いません。会社用の記録を GitHub でも共有したい場合は、機密情報を含む可能性を確認してから Git の除外設定を変更してください。

会社 Mac を切り替えるときは、先に既存の `com.claude.obsidian-sync` LaunchAgent を停止し、個人 vault を `reader`、会社 vault を `writer` に設定します。その後 dotfiles を更新して `chezmoi apply ~/.claude/hooks/watch-and-save.sh` を実行し、LaunchAgent を再読み込みします。旧 vault に既に保存されたセッションノートは自動で一括移動しないので、内容を確認してから必要なものだけ移してください。

以前 `claude/` に生成した Codex のセッション別ノートは、同期処理の起動時に `Codex/` へ移動します。

旧方式の `日付.md` と `日付/ブランチ.md` はそのまま残ります。新方式では最初に検出した最近のセッションを先頭からセッション別ノートに記録するため、切替前の集約ノートと一時的に内容が重複します。

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
