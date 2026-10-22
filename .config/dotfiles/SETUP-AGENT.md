# 新しいMacをAIエージェントでセットアップする

前提は、AIエージェント（ChatGPT / Codex / Claude Code等）を導入済みで、このリポジトリのURLがあること。Homebrew・Git・Pythonは事前に不要。

## 最初に確認すること

このMacの用途をユーザーに確認し、`personal`（個人vaultがwriter）か`work`（会社vaultがwriter）を指定する。vaultを復元しない場合だけ`none`。ユーザーの設定を推測して会社の記録を個人vaultへ保存しない。

実行前に `setup.sh --profile personal --dry-run` 相当の予定を提示できる。実行は必ず**ひとつの対話Terminal/PTYを最後まで保つ**。シェルを別々に起動してステップを代行するとsudoの認証キャッシュを共有できない場合がある。非対話ツールしかない場合、ダウンロード済みスクリプトを `.command` からTerminalで実行し、同じプロセスを監視する。ユーザーにパスワードをチャットへ送らせない。

## 実行

```bash
setup_dir="$(mktemp -d)" && curl -fsSL https://raw.githubusercontent.com/junhat6/dotfiles/main/setup.sh -o "$setup_dir/setup.sh" && bash "$setup_dir/setup.sh" --profile personal
```

`mktemp` で作った作業ディレクトリへダウンロードする。取得先はこのリポジトリの公式URLに限定し、可能ならcommit SHAを固定して内容を確認してから実行する。

1. `sudo -v` の本人認証だけユーザーに依頼する。その後はスクリプト内で認証を維持する。sudoersやエージェントの承認設定を緩めたり、1Password・キーチェーンからMacのパスワードを取り出したりしない。
2. Homebrew / CLTの直後にKarabinerとHammerspoonだけを導入する。dotfilesのbootstrap後に署名・公証を検証し、合格した対象アプリだけ隔離属性を削除して起動する。CLI側のyadm / mise / GitHub CLI準備と並行して、AIはOS権限設定を進める。Chromeの導入は待たず、GitHub認証には既存のSafariを使う。デバイスコードのEnterはエージェントが送信できる。既存アカウントでログインを進め、2FA・パスキーの本人確認はユーザーへ。追加権限や規約同意などは実行環境の確認ルールに従う。
3. GitHub認証後に `app-permissions` で最終確認のため待つ。公式配布アプリの通常の「開く」確認を代行する。Gatekeeper等の保護を全体無効化しない。
4. KarabinerのSetup画面でBackground Services / Accessibility / Capture Input Events / Driver Extensionを確認する。HammerspoonはAccessibilityとログイン時起動を設定し、設定を再読み込みしてエラーがないことを確認する。Touch ID等が要求されたときだけユーザーへ依頼する。
5. Obsidianとvaultのダウンロードは本人操作後へ回す。プラグイン有効化に追加同意が必要な環境では、このチェックポイントでユーザーに方針を確認しておく。導入後、AIがObsidianを初めて開く場合、「保管庫としてフォルダを開く」で `~/ghq/github.com/junhat6/my-vault-personal` または `my-vault-work` を登録する。既存プラグインの信頼確認は実行環境のルールに従う。iPhone/Dropbox連携の認証は別扱いで、勝手に別vaultへ同期しない。
6. 初回許可が済んだら、**エージェントが待機中のシェルにEnterを送り**残りを続行する。ユーザーにTerminalを見張らせない。アプリ更新で新しい許可が必要になる例外は、実際に発生した時だけ説明する。
7. 終了コード・`--status`・`timings.tsv`を確認する。GUIで確認していない権限を「完了」と報告しない。GitHub認証コードやtokenをログ・コミットへ含めない。

## 中断と復旧

通常終了・失敗・Ctrl-Cでsudoキャッシュを失効する。認証維持プロセスは親プロセスが消えると停止して失効する。Terminalの強制終了やOS停止で両方のtrapが実行されない場合は通常のsudo有効期限まで残り得る。気になる場合は同じTerminalで `sudo -k`、全Terminal分を明示的に失効させる場合だけ `sudo -K`。常設の権限変更は行わない。

再実行は同じコマンド。インストール状態を再確認し、既存yadm・vaultのリセットや強制pullはしない。既存設定と衝突する初回checkoutは実行ログと同じディレクトリの `backups/` に退避する。既存のyadmが別リポジトリなら停止する。

ロックが残る場合は `~/.local/state/dotfiles/setup/lock/pid` と実際のプロセスを確認する。動作中のセットアップのロックを消さない。停止済みなら `pid` ファイルと空のlockディレクトリだけを削除して再実行できる。

```bash
bash ~/setup.sh --status
```

状態・ログは `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/setup/`。`--no-ui` はGUI確認を後回しにして終了コード2で未完了を示すためのオプションで、無人セットアップ完了の意味ではない。

## 自動化の境界

| 処理 | 方針 |
| --- | --- |
| Homebrew・pkgの管理者認証 | 最初に認証し、同じTerminal内だけで維持。失効したら後から入力待ちにせず失敗する |
| Homebrew 7の認証検査 | この版はsudoキャッシュを消す検査を行うため、認証済みセットアップ内ではプロセス内の `HOMEBREW_SUDO_CHECKED=1` を使う。内部変数なので将来の互換性は保証されない。未対応版でもpasswordless sudoにはならず、認証が失われたら停止する |
| GitHubログイン・2FA | 序盤へ集約。CLIの標準認証を使い、本人確認は代行しない |
| アクセシビリティ・ドライバ許可 | 対象アプリを先に入れてまとめて操作。macOSが求める本人認証は必要 |
| AI自身の操作権限 | 未許可のAIが自分に権限を付けることはできない。導入直後の許可と必要な再起動は事前操作として案内する |
| 通常の初回「開く」 | 公式アプリについてエージェントが代行。隔離属性の削除は下記の検証工程に限定し、Gatekeeper全体は無効化しない |
| 実行中の表示 | 時刻付きの詳細出力、30秒ごとの生存表示、段階別の所要時間と終了コード |

## 現在のMacを変更しない模擬確認

```bash
python3 ~/.config/dotfiles/scripts/rehearse_setup.py --output-dir /tmp/dotfiles-rehearsal
```

実際のsetup.shを一時HOMEとPTYで動かし、sudo・Homebrew・GitHub・アプリ操作を模擬実装へ置換する。初期状態、再実行、認証失効、想定外の入力要求、インストール失敗を確認する。実際の認証やインストールは行わない。

初回モデルの本人操作は管理者認証1回、GitHub認証1フロー、OS許可3フロー。操作のまとまりは2回（開始時と、権限対象アプリ・GitHub CLI導入後）。OS許可数は仮定であり、実際のmacOSで要求される認証回数を保証しない。最初の5分で全操作が終わる保証もない。大量インストール開始後は通常の標準入力を閉じ、想定外の入力要求は待ち続けず失敗させる。/dev/ttyを直接使うプログラムやOSダイアログまではこの模擬テストで検証できないため、AIはプロセスとGUIを監視し、必要なときだけユーザーへ連絡する。

### 本人操作を早める順番

Homebrew/CLT → Karabiner/Hammerspoonだけ導入 → CLI基盤・dotfiles準備 → 署名・公証を検証して対象アプリを起動 → GUI許可をAIが進めつつGitHub CLI準備 → SafariでGitHub認証 → OS許可の最終確認 → ユーザー離席 → vault・Chrome・Obsidian・WezTerm・その他を導入。Hammerspoonはdotfiles反映後に設定を再読み込みする。Obsidianの登録やプラグイン設定もAIが後半に担当する。追加の本人認証が出た場合は実際に必要になった時だけ知らせる。

本人操作を最初の5〜10分へ寄せる目標だが、Homebrew/CLTと権限対象アプリの取得時間は短縮を保証できない。模擬テストは順序の改善を検証し、所要時間は検証しない。

## 共通のMac設定（追加確認不要）

`setup.sh` はパッケージ・サービス導入後の終盤で `dotfiles macos apply` を必ず実行する。Dockの固定アプリはFinder（OSが表示）・Launchpad・システム設定だけ、自動非表示をオン、最近使ったアプリ表示をオフ、KeyRepeat=1、InitialKeyRepeat=15。追加の確認ダイアログは不要。電源設定だけ、セットアップ開始時のsudo認証を再利用する。Launchpad等が存在しないOSではそのアプリをスキップして報告する。起動中のアプリは固定解除後も終了するまでDockに表示される。Downloadsなどアプリ以外の項目は変更しない。

Dockはその場で再起動する。キー設定はアプリ／セッションにキャッシュされる可能性があるので、全工程終了後にログアウト／ログインまたは再起動を案内する。エージェントが勝手にMacを再起動しない。初回適用前の対象キーだけ端末内へ保存する。`dotfiles macos restore` で一括復元でき、繰り返し適用しても初回バックアップは上書きしない。

ロック画面のディスプレイ消灯も同じ一括適用・復元に含む。バッテリー使用時は10分、電源接続時は「しない」（`pmset -b displaysleep 10` / `pmset -c displaysleep 0`）。バッテリー使用時のスリープ、スクリーンセーバー、パスワード要求設定は変更しない。バッテリーのないMacでは電源接続側だけ適用する。追加前のバージョンで保存したDock・キーボードのバックアップも維持し、消灯設定は初回適用前の値を別途保存する。

電源設定の変更には管理者権限が必要。初期セットアップでは最初のsudo認証を再利用し、失効時は追加の入力待ちにせず停止する。ボタン／単独コマンドで実行して変更が必要な場合だけ、Terminalが管理者認証を求める。既に目標値なら認証不要。消灯設定は即時反映し、自動再起動しない。

## 再起動は最後の1回へまとめる

今回の共通設定は確認なしで一括適用する。Dockの再起動はMac全体の再起動ではなく、作業中のアプリを終了しない。消灯設定は即時反映し、キーリピートは最後のMac再起動で反映を確認する。

Karabiner等でOSが再起動を案内したら「あとで」が選べる場合は保留し、残りのvault・パッケージ・ランタイム・サービス・共通設定・レポートまで進める。GUIチェックポイントでは、許可操作が済みドライバ反映だけが再起動待ちなら、エージェントが未検証項目をチャットに記録してEnterを送り続行する。「有効に動作している」とは報告しない。アプリ単体の再起動が必要なら対象アプリだけを再起動する。セットアップを実行しているTerminalやAIの操作環境の再起動は後回しにする。

`FINAL_RESTART:` が全工程終了後に1回だけ出る。ここで未検証項目をまとめ、作業保存後にMacを1回再起動する流れを案内する。自動でreboot/shutdownを実行しない。再起動後はKarabinerのドライバ・キー割り当て、Hammerspoonの権限・ショートカット、キーリピートを確認する。通常はインストール全体を最初から再実行する必要はない。

OSが「あとで」を許さず、先へ進む必須処理そのものが再起動を要求する場合や、認証失効・通信／インストール失敗は例外。実際に発生した理由だけ説明する。全macOS・全ドライバ版で再起動回数1回を保証するものではない。

模擬実行は実際のsetup.shとmacos-personal.pyを動かし、defaults・pmset・sudo等のOS境界だけを置き換える。初回／再実行に加え、終盤の電源設定での認証失効・書き込み失敗も確認する。実機の権限ダイアログやOS再起動は実行しない。

## OrcaとHomebrewの更新

Orcaは公式の `stablyai/orca/orca` caskで初回導入する。既存のOrca.appがHomebrew管理外にある場合、強制上書き・削除・再インストールせず、既存インストールを報告して移行を別途扱う。通常更新はOrca内蔵アップデーター（標準は安定版）に任せる。更新目的でエージェントやデーモンを終了しない。内蔵更新によるアプリ再起動ではデーモンがセッションを保持するが、Mac自体の再起動は実行中プロセスを終了する。

セットアップのservices段階で `com.junhat6.homebrew-update` を有効化する。ログイン中、毎日ローカル時刻04:00に `brew update`（Homebrew本体・定義）、`brew upgrade --formula`、`brew upgrade --cask --greedy-latest --no-quit` を実行する。スリープ中の予定は復帰後に実行される。ログアウト中は実行されない。セットアップ直後に全アプリを更新する処理ではない。

Orca等の `auto_updates` caskはHomebrewの更新対象に含めず、各アプリの更新機能へ任せる。`--greedy`、強制終了、強制上書き、無人sudoは使わない。起動中のアプリは更新が保留される場合がある。CLIやサービスの更新は動作変更やサービス再起動を伴う可能性がある。

内蔵アップデーターの有効状態はアプリごとに異なり、Homebrewの `auto_updates` 属性だけでは有効と断定しない。初回起動時にOrcaの更新設定を確認する。管理者認証や追加のOS許可が必要な更新は失敗・保留となるため、全更新が完全無人で完了する保証はない。

確認: `launchctl print gui/$(id -u)/com.junhat6.homebrew-update`。結果は `~/.claude/logs/homebrew-update.log` の終了コードを確認する。手動で同じ処理を実行する場合は `bash ~/.config/dotfiles/scripts/homebrew-update.sh`。既存のbrewfile-syncは一覧保存、dotfiles-updateは設定同期であり、パッケージ更新ではない。

参考: https://docs.brew.sh/Manpage / https://www.onorca.dev/docs/install / https://www.onorca.dev/docs/model/session-restore

既存Macで設定を取り込んだ後は、`dotfiles render` を実行し、`mkdir -p ~/.claude/logs`、`launchctl enable gui/$(id -u)/com.junhat6.homebrew-update`、未登録なら `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.junhat6.homebrew-update.plist` を実行する。dotfilesの自動同期だけでは、新しいLaunchAgentは登録されない。

## Brewfileアプリの初回確認を減らす検証工程

Gatekeeperは常に有効のまま。`setup.sh` はbootstrap後、Karabiner/Hammerspoonを起動する前に優先アプリを検証し、Brewfileの一括導入後に対象アプリ全体を検証する。`install.sh --packages` にも同じ工程を含む。確認対象は指定Brewfileに文字列で明記されたcaskのみで、再実行時は既存の対象アプリも再検証する。Brewfile.localや一覧にないアプリは対象にしない。

`brew info --json=v2 --cask` の `full_token` とインストール状態を照合し、app artifactの実際のtargetを使う。`stablyai/orca/orca` を裸の `orca` に置き換えない（別製品になる）。対象パスは `/Applications` 直下の `.app` だけ。pkg型のKarabinerとZoomはスクリプト内の明示的なアプリ対応表を使い、それ以外のpkgやフォントは自動推測せずスキップする。

各アプリについて `codesign --verify --deep --strict` が成功し、キャッシュを使わない `spctl --assess --type execute` が成功し、出力に `source=Notarized Developer ID` がある場合だけ、アプリ内の `com.apple.quarantine` を削除する。バンドル内のシンボリックリンクは `xattr -s` によりリンク自体だけを扱い、リンク先はたどらない。他の拡張属性は変更しない。署名が有効でも公証を確認できない場合、通信エラー、属性削除権限不足などは `deferred` として理由を記録する。検証失敗では削除処理へ進まない。削除中の失敗では一部の属性が削除済みの場合があるため、`deferred` を成功扱いしない。

Gatekeeperが無効な場合は処理を停止する（勝手に有効化・無効化しない）。アプリ単位の保留は他のインストールを妨げず、通常の初回確認で扱う。アクセシビリティ、入力監視、フルディスクアクセス、ドライバ許可は別であり、この処理では付与しない。公証は完全な安全性の保証ではない。

ログ: セットアップ実行ディレクトリの `app-verification-early.json` / `app-verification.json` と時刻付きの検証ログ。AIは `deferred` を確認して未完了項目を報告する。`install.sh --packages` では `~/.local/state/dotfiles/app-verification.json`。

属性を変更しない検証だけの実行:

```bash
python3 ~/.config/dotfiles/scripts/setup_machine.py prepare-apps --check-only --report ~/.local/state/dotfiles/app-verification-check.json
```

参考: https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html

## アプリ別の通知設定（追加確認不要）

共有の希望値は `.config/dotfiles/notifications.json`。現在はメッセージ（`com.apple.iChat`）とGame Center（`com.apple.gamecenter`）の「通知を許可」をオフ。アプリ全体の通知を止めるので、バナーだけを「なし」にする設定ではない。その他のアプリ、通知全体、集中モードは変更しない。

`notification-plan` が出たら序盤のGUIチェックポイントでエージェントがシステム設定 → 通知 → 各アプリを開く。マスタースイッチ（AX ID `allow-notifications`）を確認し、オンの場合だけオフへ変更。既にオフならクリックしない。メッセージは一覧に「重大」と表示されても、個別画面のマスタースイッチがオフなら目標達成。各アプリ画面でoffを確認してからチェックポイントのEnterを送る。ユーザーに追加の確認や操作を依頼しない。通知設定のための再起動は不要。

macOSの内部ncprefsフラグはOS版・アプリによって画面と対応しない場合があるため、ビット値の推測や通知データベースのコピーは行わない。CLIのプラン表示は適用済みの証拠ではない。GUIが使えない／対象が存在しない場合は未適用として記録し、完了と報告しない。`--no-ui` では他のGUI設定と同じく後回しとなる。

`dotfiles macos apply/restore` とそのボタンはDock・キーボード・消灯設定用。通知はエージェントのGUI工程で適用し、戻す際も該当アプリの「通知を許可」をGUIで変更する。

## デフォルトブラウザはChrome（インストール後・追加確認不要）

希望値は `.config/dotfiles/browser.json`。序盤は既存Safariを使い、Chrome導入のために本人操作を待たせない。`packages` と `app-verification` の後に `browser-preference` が実行される。`BROWSER_PREFERENCE` が `pending-ui` なら、エージェントはシステム設定 → デスクトップとDock → デフォルトのWebブラウザ（新しいOSでは設定検索で探す）でGoogle Chromeを選び、選択値を画面で確認する。現在のAX IDは `default-web-browser`。既にGoogle Chromeなら変更不要。OSの通常のChromeへの切替確認も追加のユーザー確認なしで代行する。

CLIは導入されたChromeのbundle IDを確認して作業対象を提示するだけで、ブラウザを変更済みと見なさない。CLIの残りのランタイム・サービス処理と並行してGUIを操作し、新たなEnter待ちは作らない。最終報告までに画面で確認する。Chrome未導入／識別子不一致／GUI操作不可なら未適用として報告し、他の導入は継続する。`--no-ui` は後回しで終了コード2。デフォルトブラウザ変更のためのMac再起動は不要。通知と同様、`dotfiles macos apply/restore` の対象には含まずエージェントのGUI工程で適用する。

電源アダプタ使用時の「ディスプレイがオフのときに自動でスリープさせない」もオンにします（`pmset -c sleep 0`）。既存の `dotfiles macos apply/restore` とボタン、初期セットアップ終盤の確認なし一括適用に含まれます。バッテリー使用時の自動スリープや、手動スリープ・ふたを閉じた際の設定は変更しません。初回適用直前のACスリープ値を別ファイルへ保存し、過去のバックアップを壊さず復元します。反映に再起動は不要です。

## Finderのよく使う項目（追加確認不要）

`.config/dotfiles/finder-sidebar.json` に `ghq/github.com` を共有する。絶対パスのユーザー名や別Macのブックマークデータは保存しない。`finder-sidebar` フェーズでこのMacのHOMEを基準に対象ディレクトリを用意し、`FINDER_SIDEBAR_PREFERENCE` を表示する。profile=noneでもフォルダを作るため、vaultやリポジトリ取得の有無に依存しない。

序盤のGUIチェックポイントでエージェントがFinderを開き、⌘⇧Gで表示された対象パスに移動する。よく使う項目に同じパスがある場合は追加しない（同名の別フォルダと混同しない）。未登録なら内容を選択していない状態で「ファイル」→「サイドバーに追加」を操作する。今回の実機ではフォルダを開いた状態からこのメニューで追加できた。追加後にサイドバーのgithub.comを開き、対象パスへ移動できることを確認する。既存のお気に入りを削除・並べ替えたり、Finder全体を再起動したりしない。追加のユーザー確認・認証・Mac再起動は不要。

CLIはフォルダ作成とGUI操作の指示だけを行う。表示ログだけでサイドバー追加済みとは報告しない。GUIが使えない場合は未適用と記録する。`--no-ui` ではGUI処理を後回しにする。通知・ブラウザと同様、`dotfiles macos apply/restore` とボタンによる設定変更とは別のエージェントGUI工程。戻す場合はFinderの「サイドバーから削除」を使う（フォルダ自体は削除しない）。

## Tailscale

公式Standalone版を `brew install --cask tailscale-app` で導入する。CLI専用formulaの `tailscale` は重複導入しない。権限対象アプリとして前半で導入し、拡張機能・VPN許可・ログインを案内する。接続先tailnetやアカウントを推測しない。新しいネットワーク権限や登録の同意は実行環境の確認ルールに従う。

`yadm bootstrap` / `install.sh --apply` で `io.tailscale.ipn.macsys` の `SUEnableAutomaticChecks` と `SUAutomaticallyUpdate` をtrueに設定し、アプリ内のSparkle更新を使う。Homebrewの日次更新は自動更新対応caskを除外するため二重管理しない。公式資料: https://tailscale.com/kb/1315/mdm-keys 。
