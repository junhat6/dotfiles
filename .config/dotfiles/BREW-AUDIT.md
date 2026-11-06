# Homebrew とアプリの棚卸し

2026-10-31 に、この Mac の Homebrew 導入記録、共有 [Brewfile](Brewfile)、端末専用の `Brewfile.local`、`/Applications` と `~/Applications` を照合した結果です。日々の更新で変わるため、この一覧は調査時点の記録です。

## 今回の変更

- `cask "capsomnia"` を共有 Brewfile に追加。Hammerspoon の Alt + Ctrl + S が依存する、蓋閉じ時のスリープ防止アプリです。
- このMacへ Capsomnia 4.3.0 を brew で導入済み。アプリ本体・署名・Gatekeeper検証・特権helper・ログイン時のLaunchAgent起動を確認しました。常時起動モードへの切り替えは行っていません。
- `brew bundle check --no-upgrade` が成功し、共有 Brewfile の全依存が導入済みであることを確認しました。通常のcheckではChrome・Obsidian・Slack・VS Codeに更新が提示されましたが、今回まとめて更新していません。
- ほかの未記載パッケージは以下に列挙し、共有 Brewfile へは自動追加していません。
- インストール済みの Caffeine と Capsomnia は別用途です。Caffeine は削除していません。

## brew 導入済みだが共有 Brewfile にないもの

| 種別 | パッケージ | 用途・共有を検討する理由 | 端末用 Brewfile.local |
| --- | --- | --- | --- |
| formula | `coreutils` | GNU版の基本コマンド。共通設定で必須かを確認してから追加を判断 | 記載あり |
| formula | `imagemagick` | 画像変換。画像作業の共通ツールにするなら追加候補 | 記載あり |
| formula | `librsvg` | SVG描画。キー割り当て図のPNG化・目視確認で利用しているため追加候補 | 記載あり |
| cask | `1password-cli` | `op` コマンド。GUIの1Passwordアプリとは別。利用する端末へ共通導入するなら追加候補 | 記載あり |
| cask | `claude` | Claudeデスクトップアプリ。Hammerspoonの初回アプリ割り当てにもあるため追加候補 | 記載あり |
| cask | `keycastr` | キー入力表示。動画・デモ用として必要な端末だけに残す案もある | 記載あり |

この6件は「導入記録そのものがない」のではなく、「このMacの記録にはあるが、新しいMacへの共通導入対象にはなっていない」という差分です。

Capsomnia の導入開始前の集計は、formula 97件（直接導入の記録があるもの26件、依存としてのみ導入されたもの71件）、cask 21件でした。Capsomnia 導入後のcaskは22件です。formula の共有未記載は直接導入分だけを上表へ列挙しています。

依存ライブラリ71件をすべて Brewfile に書き写す必要はありません。Homebrew が必要な依存を解決します。既存の明示的な `libyaml` の指定などは今回変更していません。未使用に見える依存も削除していません。

## Homebrew 管理記録が見つからない主要アプリ

以下はアプリ本体が存在しますが、Homebrew の導入済み cask としては記録されていません。手動導入やアプリ内更新などの可能性があり、導入経路は断定していません。

| アプリ | 状況・確認事項 |
| --- | --- |
| 1Password | GUIアプリ本体。導入済み `1password-cli` だけでは本体は導入されない |
| AivisSpeech | 現在の版は `1.1.0-dev`。安定版のパッケージへ置き換えてよいか要確認 |
| ChatGPT | 現在のbundle IDは `com.openai.codex`。名前だけを根拠に同名caskへ置き換えない。配布元・対応パッケージの確認が必要 |
| Granola | アプリ本体あり。共通導入したいかを判断する対象 |
| Muse | アプリ本体あり。Hammerspoonの Alt + M は共有したが、アプリ本体の導入はまだ自動化していない |

Safari、Karabinerの付属アプリ、生成されたClaude Code URL Handlerは、独立した共通導入候補から除外しています。システム領域の全アプリ、App Storeの購入履歴、すべてのCLI実行ファイルまでは対象にしていません。

`gh`・`ripgrep` などは [mise設定](../mise/config.toml) 側で管理する方針です。brewにないことだけで未管理とは扱いません。

## 再確認方法

```bash
brew list --formula --versions
brew list --cask --versions
brew leaves --installed-on-request
brew info --installed --json=v2
bash ~/.claude/hooks/brewfile-sync.sh --once
diff -u ~/.config/dotfiles/Brewfile ~/.config/dotfiles/Brewfile.local
```

`Brewfile.local` はこのMac全体の現状保存、共有 Brewfile は別のMacにも導入したいものの指定です。差分をそのまま全部コピーせず、用途を確認して共有対象を決めます。`brew bundle cleanup` による一括削除は行いません。
