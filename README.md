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
│   ├── mise/         # 共通ランタイムのバージョン指定
│   ├── nvim/         # Neovim (LazyVim)
│   ├── zsh/          # 用途別のシェル設定
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
├── scripts/          # 構文確認・macOS 設定・会社用 Git 名義の登録
└── .chezmoiignore    # chezmoi 管理対象外リスト
```

エイリアス・キーバインド・プラグイン構成などの詳細は、このREADMEには書かず各 `dot_*` ファイルを直接参照してください（変更のたびにREADMEを追随させる運用コストを避けるため）。

## インストール

```bash
git clone https://github.com/junhat6/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Homebrew パッケージを一括インストール
brew bundle

# dotfiles をホームディレクトリへ展開
./install.sh

# mise の共通ランタイム・CLI をインストール
mise install
source ~/.zshrc
```

`install.sh` は chezmoi を使って各ファイルを `$HOME` へ展開します。適用前に差分を表示します。ホーム側で変更したファイルがあると chezmoi が上書きの確認を求めることがあります。Obsidian 同期と Brewfile.local 記録用の LaunchAgent も読み込みます。

必要な段階だけ再実行できます。引数なしの動作は従来どおり、チェック・設定適用・LaunchAgent 登録です。複数の段階は下記の順で実行します。

```bash
./install.sh --check         # 依存と構文を確認
./install.sh --packages      # brew bundle
./install.sh --apply         # 設定だけ適用
./install.sh --launchagents  # 常駐処理だけ再登録
./install.sh --all --dry-run # 全段階の実行予定を表示（書き込みなし）
bash scripts/check.sh       # CI と同じ構文確認
```

端末に固有の PATH などは `~/.zshrc.local` に保存します。これは同期されません。共通ランタイムの指定は `dot_config/mise/config.toml` にあります。 Node・Go・Rust・uv と開発 CLI（gh・ghq・lazygit・ripgrep・fd・bat・eza・delta・CMake・czg・Gemini CLI・gog・goimports・gopls・staticcheck・mdbook-plantuml）は mise で管理し、GUI アプリ・ネイティブライブラリ・mise 自体は Homebrew で管理します。Rust の rustup は mise のバックエンドが準備します。ログインシェルでは `dot_zprofile` の shims、対話シェルでは `dot_zshrc` の activate により mise を優先します。プロジェクト固有の版は各 repo の `mise.toml` で指定します。変更は正本の `dot_config/mise/config.toml` に書き、`chezmoi apply ~/.config/mise/config.toml` → `mise install` の順で反映してください。

Finder の拡張子表示・パスバーは必要な端末で明示的に適用します。初回の元の値をローカルに保存します。

```bash
bash scripts/macos-defaults.sh --apply
bash scripts/macos-defaults.sh --check
bash scripts/macos-defaults.sh --restore
```

### Claude / Codex セッションの Obsidian 記録

`dot_claude/hooks/watch-and-save.sh` は Claude Code と Codex のローカル JSONL を監視します。`~/ghq/github.com/junhat6/` にある2つの vault の GitHub 接続先と Obsidian Git の `disablePush: false` を確認し、この Mac の書き手 vault を自動選択します。個人 Mac では個人 vault、会社 Mac では会社 vault です。両 vault の設定が揃っていない場合や、書き手が重複する場合は、誤った vault に書かないよう起動を止めます。Claude は `<vault>/claude/<repo>/<セッション開始日>/`、Codex は `<vault>/Codex/<repo>/<セッション開始日>/` に保存します。各日付フォルダの中は `<開始時刻> <タイトル> [Claude|Codex] <ID>.md` というセッション別ノートです。同じセッションを翌日再開しても、開始日の同じノートに続けます。ブランチ、エージェント、セッション ID を記録し、Issue が解決できた場合はリンクも付けます。

タイトルは Claude の `custom-title` / `ai-title`、Codex のローカルセッション DB の `name` を優先します。タイトルがまだ無い間は初回プロンプトまたは仮題を使い、後からタイトルが付いたらファイル名と見出しを更新します。AI に別途タイトル生成を依頼しません。`OBSIDIAN_DIR`、`CODEX_OBSIDIAN_DIR`、`SESSION_DIR`、`CODEX_SESSION_DIR`、`CODEX_STATE_DB`、`SYNC_STATE_DIR` で各パスを変更できます。手動で `OBSIDIAN_DIR` を指定した場合は自動選択しません。

`claude/` と `Codex/` は両 vault で Git の管理対象外です。個人 Mac の記録は個人 vault に保存し、Remotely Save で Dropbox 経由で iPhone に同期します。会社 Mac の記録は会社 vault に保存し、Dropbox は使いません。会社用の記録を GitHub でも共有したい場合は、機密情報を含む可能性を確認してから Git の除外設定を変更してください。

会社 Mac を切り替えるときは、先に既存の `com.claude.obsidian-sync` LaunchAgent を停止し、個人 vault を `reader`、会社 vault を `writer` に設定します。その後 dotfiles を更新して `chezmoi apply ~/.claude/hooks/watch-and-save.sh` を実行します。常駐処理を起動する前に `~/.claude/hooks/watch-and-save.sh --check-destination <会社vaultのディレクトリ> <GitHubのowner/repo>` を実行し、Claude と Codex の保存先が両方とも会社 vault で、Git の接続先も合っていることを確認してください。この確認コマンドはノートを書きません。成功したら LaunchAgent を再読み込みします。旧 vault に既に保存されたセッションノートは自動で一括移動しないので、内容を確認してから必要なものだけ移してください。

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

### mise へ移したツールと Homebrew の整理

上記の開発 CLI は `dot_config/mise/config.toml` に版を記録します。Google Workspace の CLI は `gws` から `gog`（公式配布 `openclaw/gogcli`）へ統一します。gog の Google アカウント認証は端末ごとの設定で、資格情報は dotfiles に入れません。初回は `gog auth --help` を参照してください。

移行済みツールを Homebrew から削除するときは、mise 側の起動と `brew uses --installed <formula>` を確認してから対象だけを `brew uninstall` します。`brew bundle cleanup` による一括削除は、この PC 固有のパッケージまで消すため使いません。Homebrew 側のグローバル npm に入れた Gemini CLI も、mise 版を確認してから旧 Node の npm で削除します。

## Git ユーザー情報の更新

### 個人用の名義

共通の個人用名義は `dot_gitconfig` の `[user]` を編集して chezmoi で反映します。

```bash
chezmoi edit ~/.gitconfig
chezmoi apply
```

### 会社 Mac での初回設定

会社用名義は端末ごとに設定します。通常の dotfiles セットアップ後、dotfiles リポジトリ内で次を実行してください。`COMMIT_NAME` と `WORK_EMAIL` は会社で使う名前・メールアドレスに置き換えます。実際の会社メールは公開リポジトリに記載しません。

```bash
bash scripts/setup-git-work.sh speee "COMMIT_NAME" "WORK_EMAIL"
```

このコマンドは `~/.gitconfig.work` に会社の名前・メールを保存し、`~/.gitconfig.local` に条件付き読み込みを設定します。`~/ghq/github.com/speee/` 配下のリポジトリと、そのリポジトリから作った worktree で会社用名義が有効になります。判定はリポジトリの保存場所によるため、別の場所に clone した場合は `~/.gitconfig.local` の `gitdir` 条件を合わせてください。

会社用ファイルは Git 管理・chezmoi 同期の対象外です。別の Mac に dotfiles を導入しても自動ではコピーされないため、その Mac でも上のコマンドを実行してください。これらのファイルは `chezmoi add` / `re-add` で取り込まないでください。

### 会社用の名前・メールを変更する場所

| ファイル | 用途 |
| --- | --- |
| `~/.gitconfig.work` | 会社用の `[user]` の `name` / `email`。会社メールの変更先 |
| `~/.gitconfig.local` | 会社用名義を使うディレクトリの条件 |
| `dot_gitconfig` | 共通の個人用名義と Git 設定 |

会社用メールの変更は、この端末の `~/.gitconfig.work` に対して行います。直接編集しても、次のコマンドで更新しても構いません。保存後すぐに有効になり、chezmoi の適用は不要です。

```bash
git config --file "$HOME/.gitconfig.work" user.email "NEW_WORK_EMAIL"
git config --file "$HOME/.gitconfig.work" user.name "NEW_COMMIT_NAME"
```

設定後は会社リポジトリに移動して、有効な名義と読み込み元を確認してください。個人リポジトリでも同じコマンドで確認できます。

```bash
git config --show-origin --get user.name
git config --show-origin --get user.email
```

既存 repo のローカル `user.name` / `user.email` が設定されていると、そちらが優先されます。期待した名義にならない場合は、上記の読み込み元を確認してください。

GitHub Actions の構文確認は、この変更を push した後に有効になります。ローカルでは `bash scripts/check.sh` で同じチェックを実行できます。

## macOS キーリピートをターミナル上で変更するコマンド

```bash
# キーリピートを最速に（デフォルト: 6、小さいほど速い）
defaults write NSGlobalDomain KeyRepeat -int 1

# キーリピート開始までの時間を短く（デフォルト: 25、小さいほど速い）
defaults write NSGlobalDomain InitialKeyRepeat -int 15
```
