---
description: アーティファクトHTMLを GitHub Pages (junhat6.github.io/claude-artifacts) に公開する
argument-hint: <HTMLファイルパス（省略時はこのセッションで最後に作成したアーティファクト）>
allowed-tools: Bash, Read, Glob
---

アーティファクト HTML を公開サイト https://junhat6.github.io/claude-artifacts/ に追加してください。

対象ファイル: **$ARGUMENTS**（未指定の場合は、このセッションで最後に Artifact ツールに渡した HTML ファイル。見つからなければユーザーにパスを確認する）

## 実行手順

### Step 1: 公開前の内容チェック（必須）

対象の HTML を読み、以下が含まれていないか確認する:

- 社名・取引先名・業務の内部情報（進捗レポート、仕様、社内 URL など）
- 認証情報・API キー・トークン
- 個人情報（自分以外の氏名・メールアドレスなど）

**該当するものがあれば公開せずに停止し、ユーザーに具体的に何が含まれているかを伝えて判断を仰ぐこと。** 公開先は認証なしの公開インターネットであり、一度公開したものはキャッシュ・インデックスされ完全には取り消せない。

### Step 2: リポジトリの確認

```bash
ls ~/ghq/github.com/junhat6/claude-artifacts/publish.py
```

存在しなければ `ghq get junhat6/claude-artifacts` で取得する。

### Step 3: 取り込みと公開

```bash
cd ~/ghq/github.com/junhat6/claude-artifacts
python3 publish.py <対象ファイル>
git add -A && git commit -m "Add artifact: <タイトル>" && git push
```

`publish.py` が断片 HTML を完全な文書にラップし、`YYYY-MM-DD-<slug>.html` で配置して一覧ページ（index.html）を再生成する。タイトルや slug を変えたい場合は `--title` / `--slug` オプションを使う。

### Step 4: 結果報告

`publish.py` が出力した公開 URL をユーザーに伝える。GitHub Pages への反映には push から最大1分程度かかることも添える。
