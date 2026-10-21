# Dotfiles

新しいMacは、AIエージェントにこのURLと「セットアップして」と伝え、[1コマンドのセットアップ手順](.config/dotfiles/README.md)を使います。開始時に管理者認証を行い、Homebrew直後に権限対象アプリだけ起動し、CLI準備中にもAIが許可設定を進めます。GitHub認証後はvaultや残りのアプリを導入します。その後はエージェントが監視します。[エージェント向け手順](.config/dotfiles/SETUP-AGENT.md)。

[yadm で HOME の個別ファイルを直接追跡します。セットアップ・所有権・日常操作はこちら。](.config/dotfiles/README.md)

## MacBookのキー割り当て

[現在の割り当てと更新方法](.config/karabiner/README.md)。KarabinerのJSONから図と表を生成し、設定と一緒に管理します。

[![MacBook US配列の現在の割り当て](.config/karabiner/keymap.svg)](.config/karabiner/keymap.svg)

## MacのDock・キーボード設定

初期セットアップの最後に確認なしで自動適用します。単独で適用する場合は `dotfiles macos apply`、戻す場合は `dotfiles macos restore`、確認は `dotfiles macos status`。リポジトリ直下の「Mac-Settings-Apply.command」「Mac-Settings-Restore.command」はダブルクリックでも実行できます。

- Dockに固定するアプリはFinder・Launchpad・システム設定だけ（存在するもの）。
- Dockを自動的に隠し、最近使ったアプリを表示しない。起動中のアプリは終了するまで表示されます。Downloads等は維持します。
- KeyRepeat=1、InitialKeyRepeat=15。

初回適用前の設定を端末内に保存して一括復元できます。Dockは即時再起動し、キーリピートは作業後のログアウト／ログインまたは再起動で反映を確認してください。Macは自動再起動しません。

ロック画面のディスプレイ消灯も同じ一括適用・復元に含む。バッテリー使用時は10分、電源接続時は「しない」（`pmset -b displaysleep 10` / `pmset -c displaysleep 0`）。画面消灯以外のスリープ、スクリーンセーバー、パスワード要求設定は変更しない。バッテリーのないMacでは電源接続側だけ適用する。追加前のバージョンで保存したDock・キーボードのバックアップも維持し、消灯設定は初回適用前の値を別途保存する。

電源設定の変更には管理者権限が必要。初期セットアップでは最初のsudo認証を再利用し、失効時は追加の入力待ちにせず停止する。ボタン／単独コマンドで実行して変更が必要な場合だけ、Terminalが管理者認証を求める。既に目標値なら認証不要。消灯設定は即時反映し、自動再起動しない。

セットアップ中の再起動は可能な限り「あとで」にし、全インストール・設定・レポート終了後の `FINAL_RESTART:` で最後の1回にまとめます。再起動後だけ確認できるドライバは未検証として記録し、後続インストールを続けます。OSが延期できない再起動を必須とする場合や、認証失効・インストール失敗は例外です。

通知の共通設定は `.config/dotfiles/notifications.json` に保存しています。メッセージ・Game Centerの「通知を許可」をオフにします。次のMacでは、エージェントが序盤のシステム設定操作にまとめて確認なしで適用し、画面で検証します。通知はGUIで適用するため、`dotfiles macos apply/restore` 単独には含まれません。再起動は不要です。
