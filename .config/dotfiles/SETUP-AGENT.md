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
2. Homebrew / CLT / yadm / miseの基盤導入を待つ。最初のアプリ導入より先にGitHubの認証を完了する。デバイスコードのEnterはエージェントが送信できる。既存アカウントでログインを進め、2FA・パスキーの本人確認はユーザーへ。追加権限や規約同意などは実行環境の確認ルールに従う。
3. 優先アプリの導入が終わると `app-permissions` で待つ。公式配布アプリの通常の「開く」確認を代行する。Gatekeeper等の保護を全体無効化しない。
4. KarabinerのSetup画面でBackground Services / Accessibility / Capture Input Events / Driver Extensionを確認する。HammerspoonはAccessibilityとログイン時起動を設定し、設定を再読み込みしてエラーがないことを確認する。Touch ID等が要求されたときだけユーザーへ依頼する。
5. Obsidianを初めて開く場合、「保管庫としてフォルダを開く」で `~/ghq/github.com/junhat6/my-vault-personal` または `my-vault-work` を登録する。既存プラグインの信頼確認は実行環境のルールに従う。iPhone/Dropbox連携の認証は別扱いで、勝手に別vaultへ同期しない。
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
| 通常の初回「開く」 | 公式アプリについてエージェントが代行。quarantine削除やGatekeeper全体無効化はしない |
| 実行中の表示 | 時刻付きの詳細出力、30秒ごとの生存表示、段階別の所要時間と終了コード |
