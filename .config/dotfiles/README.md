# Dotfiles

HOME の共有ファイルを yadm (Git) で直接追跡します。コピーや symlink を介さないため、エディタ・AI・atomic save で実体を変更しても `yadm diff` に現れます。既存 Git 履歴は引き継ぎます。

## 初回セットアップ

```bash
brew install yadm
yadm config yadm.auto-private-dirs false
yadm config yadm.auto-perms false
yadm config yadm.auto-alt false
yadm clone --no-bootstrap https://github.com/junhat6/dotfiles.git
yadm bootstrap
bash ~/.config/dotfiles/install.sh --packages
mise install
source ~/.zshrc
# macOS の常駐処理は保存先を確認してから明示的に登録
bash ~/.config/dotfiles/install.sh --launchagents
```

既存 HOME を移行するときは先に対象ファイルとローカル設定をバックアップし、yadm の checkout との差分を確認します。既存のローカルファイルを force checkout で上書きしないでください。別の Git checkout は履歴保管・開発用で、日常編集する正本は HOME です。

Bootstrap は `yadm gitconfig core.hooksPath ~/.config/dotfiles/git-hooks` を設定し、yadm の自動 private-dir 作成・権限変更・alternate 処理を無効化します。ローカル Claude mode の初期化と LaunchAgent の render を行います。再実行しても既存 local 値は保存し、local JSON が壊れていれば上書きせず失敗します。会社の managed-settings がある新規端末だけ `auto`、ない端末は従来の `bypassPermissions` を local に初期化します。既存 mode を広げません。

`--check` はシェル/Git 構文・所有権と一時 HOME による統合テストを実行し、HOME を変更しません。`--apply` は bootstrap 処理、`--packages` は共通 Brewfile、`--launchagents` は常駐処理、`--all --dry-run` は実行予定のみ表示します。

## 設定を探す・差分を見る（ターミナル / Neovim）

`dedit` は共有設定を検索し、ステージ済み・未ステージの差分を分けてプレビューします。変更がないファイルは内容を表示。認証・ローカル専用設定は候補に入りません。削除されたファイルは差分を見られますが、Enter で勝手に作り直しません。

```bash
dedit                   # 全共有設定を検索して Neovim で開く
dedit --changed         # 変更がある共有設定から選ぶ
dedit --query wezterm   # 検索語を入れた状態で開く
dlg                     # dotfiles の lazygit
```

|入口 / 操作|動作|
|---|---|
|ターミナル `Ctrl-X` → `Ctrl-D`|dedit を直接開く（2キーを順に押す）|
|既存 `Ctrl-Q` → `[dotfiles] shared settings`|dedit を開く。通常のリポジトリ選択・移動も継続|
|選択画面 `Ctrl-S` / `Ctrl-A`|変更ファイル / 全共有ファイルに切り替え|
|選択画面 `Ctrl-/`|プレビューを表示・非表示（端末により Ctrl-_ と同じコード）|
|選択画面 `Ctrl-G`|dotfiles の lazygit を開く|
|Neovim `Space f d` / `Space f Shift-D`|差分プレビュー付きの共有設定 / 変更設定の検索|
|Neovim `Space g y`|dotfiles 専用 lazygit を開く|
|Neovim `Space g h p`|現在の変更の差分をインライン表示（LazyVim 標準）|
|Neovim `]h` / `[h`|変更箇所を次 / 前へ移動（LazyVim 標準）|

通常の `lg` / `v` と、Neovim の通常プロジェクト用 Git 操作はそのままです。ショートカットから設定を開いて戻っても、入力途中のシェルコマンド・カーソル・作業ディレクトリを保持します。新しいターミナルで読み込まれ、既存のターミナルでは `source ~/.zshrc`。Neovim は開き直します。

Neovim は既存 Gitsigns の `worktrees` 設定で yadm を接続します。通常の Git リポジトリが検出できる場合はそちらが優先されます。Git の場所を Neovim 全体の環境変数に書き換えず、バッファごとに両方を扱います。設定検索と lazygit は既存 Snacks を使用し、端末と Neovim の検索は同じ `.config/dotfiles/scripts/picker.py` の共有一覧・プレビューを使います。追加の Git プラグインは導入していません。

`dotfiles files --json` / `dotfiles files --changed --json` はエディタ用の共有ファイル一覧、`dotfiles preview KEY --plain` はその候補の差分です。候補の key は不透明な識別子で、任意のパスを指定してローカル情報を読む入口にはなりません。新しい共有ファイルは引き続き ownership.json と .gitignore に個別登録します。

fzf のプレビューは幅100未満なら下、広い端末なら右に出します。全変更とファイル選択は都度更新されます。ステージ/未ステージ表示は Git の内容の違いで、編集者が人/AIかの識別ではありません。未保存のエディタ内容を外部変更で強制上書きする仕組みは追加していません。

## 日常操作と所有権

```bash
dotfiles status             # 追跡差分・新規候補・生成物 drift
dotfiles status --json      # パスと診断だけ。設定内容は表示しない
yadm diff                   # 既存共有ファイルの変更
dotfiles check              # HOME の所有権・設定・生成物検証
dotfiles add ~/.zshrc       # manifest 登録済みの個別ファイルだけ stage
yadm commit -m 'Update shell settings'
yadm pull --ff-only         # 共有変更を HOME に直接反映
dotfiles render             # この HOME の LaunchAgent を再生成
```

`.config/dotfiles/ownership.json` の `shared` は完全なファイル名の allowlist、`local` は端末専用パス、`excluded` は runtime の除外、`generated` は template と未追跡出力の組です。新規共有ファイルは内容を確認し `shared` に個別登録してから manifest と一緒に stage します。`.claude` 全体やディレクトリを一括 add しません。登録された共有 config 内の新規ファイルはチェックで検知し、未知の `.config` ディレクトリは status が所有権確認候補として表示します。既存の他ツール設定と runtime はローカル扱いです。

HOME の `.gitignore` は既定で全パスを除外し、共有ファイルだけを個別に許可します。新規共有登録時は manifest とこの個別許可も更新します。

pre-commit/pre-push は実際の Git INDEX のパス・manifest・JSON を検証するため、`yadm add -f` した local ファイルや、stage 後に作業ファイルだけを直した不正設定も拒否します。pre-push は stdin で渡された各 branch tip の committed tree も検証します。LaunchAgent の drift と新規共有候補も検知します。自動 add・commit・push は行いません。Git hooks は `--no-verify` 等で回避可能で、任意の AI に認識を強制する仕組みではありません。既存共有編集の追跡と明示的な所有権検査を機械で支えます。

共有設定は `.zshrc`, `.zprofile`, `.gitconfig`, `.tmux.conf` と `.config/`, `.claude/`, `.hammerspoon/` の manifest にある個別ファイルです。Neovim は標準 bootstrap・配色に、共有設定検索と Git 連携用の `lua/plugins/dotfiles.lua`, `lua/dotfiles/init.lua` を加えた5ファイルです。LazyVim 標準と Catppuccin Latte を使用し、`lazy-lock.json` / `lazyvim.json` はローカル生成物です。以前の `lazyvim.json` に extras が残る端末では、バックアップ後にその extras を空にして標準構成に戻します。Ghostty・Gemini CLI・opencode は共通設定から削除済みです。

Claude の共通 `settings.json` は共有 UI/plugin 設定のみ。`settings.local.json` の permissions・defaultMode・host hooks は共有しません。端末固有の `.gitconfig.local`, `.gitconfig.work`, `.zshrc.local`、認証データもローカルです。

## Brewfile と mise

共通の `.config/dotfiles/Brewfile` は手動編集します。日次 LaunchAgent は `~/.claude/hooks/brewfile-sync.sh` で `~/.config/dotfiles/Brewfile.local` にこの端末のパッケージ一覧を記録し、コミット/push しません。

```bash
bash ~/.claude/hooks/brewfile-sync.sh
diff -u ~/.config/dotfiles/Brewfile ~/.config/dotfiles/Brewfile.local
brew bundle --file="$HOME/.config/dotfiles/Brewfile"
brew bundle check --file="$HOME/.config/dotfiles/Brewfile"
# 共通版指定を直接編集して反映
$EDITOR ~/.config/mise/config.toml
mise install
```

GUI・ネイティブ依存・mise は Homebrew、ランタイムと開発 CLI は mise で管理します。`brew bundle cleanup` による端末独自パッケージの一括削除は使いません。gog 認証は端末ごとに `gog auth --help` を確認します。

## Git 名義と macOS 設定

共通の個人名義は `~/.gitconfig` を直接編集します。会社名義はローカル helper を使います。

```bash
bash ~/.config/dotfiles/scripts/setup-git-work.sh speee "COMMIT_NAME" "WORK_EMAIL"
git config --file "$HOME/.gitconfig.work" user.email "NEW_WORK_EMAIL"
git config --file "$HOME/.gitconfig.work" user.name "NEW_COMMIT_NAME"
git config --show-origin --get user.name
git config --show-origin --get user.email
bash ~/.config/dotfiles/scripts/macos-defaults.sh --apply
bash ~/.config/dotfiles/scripts/macos-defaults.sh --check
bash ~/.config/dotfiles/scripts/macos-defaults.sh --restore
```

会社 helper は `~/.gitconfig.work` と `~/.gitconfig.local` に条件付き名義を保存します。`~/ghq/github.com/speee/` とその worktree が対象です。別の場所なら local の gitdir 条件を変更します。repo 固有 user.name/email はそちらが優先されます。macOS defaults は初回の値をローカル保存し、明示的に apply/restore します。

## 検証

```bash
bash ~/.config/dotfiles/scripts/check.sh "$HOME"
# ネイティブ checkout でも root を明示できる
bash .config/dotfiles/scripts/check.sh "$PWD"
```

GitHub Actions も同じ検証を実行します。テストは一時 HOME の Git repository で atomic save、新規候補、強制 add の拒否、不正 INDEX、portable template、ローカル初期化と再実行を検証します。

### Claude / Codex セッションの Obsidian 記録

`.claude/hooks/watch-and-save.sh` は Claude Code と Codex のローカル JSONL を監視します。`~/ghq/github.com/junhat6/` にある2つの vault の GitHub 接続先と Obsidian Git の `disablePush: false` を確認し、この Mac の書き手 vault を自動選択します。個人 Mac では個人 vault、会社 Mac では会社 vault です。両 vault の設定が揃っていない場合や、書き手が重複する場合は、誤った vault に書かないよう起動を止めます。Claude は `<vault>/claude/<repo>/<セッション開始日>/`、Codex は `<vault>/Codex/<repo>/<セッション開始日>/` に保存します。各日付フォルダの中は `<開始時刻> <タイトル> [Claude|Codex] <ID>.md` というセッション別ノートです。同じセッションを翌日再開しても、開始日の同じノートに続けます。ブランチ、エージェント、セッション ID を記録し、Issue が解決できた場合はリンクも付けます。

タイトルは Claude の `custom-title` / `ai-title`、Codex のローカルセッション DB の `name` を優先します。タイトルがまだ無い間は初回プロンプトまたは仮題を使い、後からタイトルが付いたらファイル名と見出しを更新します。AI に別途タイトル生成を依頼しません。`OBSIDIAN_DIR`、`CODEX_OBSIDIAN_DIR`、`SESSION_DIR`、`CODEX_SESSION_DIR`、`CODEX_STATE_DB`、`SYNC_STATE_DIR` で各パスを変更できます。手動で `OBSIDIAN_DIR` を指定した場合は自動選択しません。

`claude/` と `Codex/` は両 vault で Git の管理対象外です。個人 Mac の記録は個人 vault に保存し、Remotely Save で Dropbox 経由で iPhone に同期します。会社 Mac の記録は会社 vault に保存し、Dropbox は使いません。会社用の記録を GitHub でも共有したい場合は、機密情報を含む可能性を確認してから Git の除外設定を変更してください。

会社 Mac を切り替えるときは、先に既存の `com.claude.obsidian-sync` LaunchAgent を停止し、個人 vault を `reader`、会社 vault を `writer` に設定します。その後 dotfiles を更新して `yadm pull --ff-only` を実行します。常駐処理を起動する前に `~/.claude/hooks/watch-and-save.sh --check-destination <会社vaultのディレクトリ> <GitHubのowner/repo>` を実行し、Claude と Codex の保存先が両方とも会社 vault で、Git の接続先も合っていることを確認してください。この確認コマンドはノートを書きません。成功したら LaunchAgent を再読み込みします。旧 vault に既に保存されたセッションノートは自動で一括移動しないので、内容を確認してから必要なものだけ移してください。

以前 `claude/` に生成した Codex のセッション別ノートは、同期処理の起動時に `Codex/` へ移動します。

旧方式の `日付.md` と `日付/ブランチ.md` はそのまま残ります。新方式では最初に検出した最近のセッションを先頭からセッション別ノートに記録するため、切替前の集約ノートと一時的に内容が重複します。

## macOS キーボード操作

Alt（Option）+ H/J/K/L はそれぞれ ←/↓/↑/→。Tabを押しながら使ってもAltとして操作できます。Shift・Command・Control・Fnを併用した組み合わせは矢印へ変換しません。

アプリ起動と登録済みURLの番号キーはAlt、検索や一覧などの操作はAlt + Shiftに揃えます。クリップボード履歴はCommand + Shift + Vです。

| キー | 操作 |
| --- | --- |
| Alt + Shift + H | ショートカット一覧 |
| Alt + Shift + L | URLランチャー |
| Alt + Shift + P | 統合パレット |
| Alt + Shift + W | ウィンドウ検索 |
| Alt + Shift + G | GitHubリポジトリ検索 |
| Command + Shift + V | クリップボード履歴 |
| Alt + Shift + , / . | ウィンドウを記憶 / 記憶したウィンドウへ戻る |

Alt + H/J/K/L はアプリ起動に登録できません。以前のAmicalのAlt + K割り当ては設定の再読み込み時に削除します。

## macOS キーリピートをターミナル上で変更するコマンド

```bash
# キーリピートを最速に（デフォルト: 6、小さいほど速い）
defaults write NSGlobalDomain KeyRepeat -int 1

# キーリピート開始までの時間を短く（デフォルト: 25、小さいほど速い）
defaults write NSGlobalDomain InitialKeyRepeat -int 15
```
