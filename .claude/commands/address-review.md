---
description: PRのレビューコメント（bot・人間レビュアー問わず）を取得し、対応要否を判断して修正・返信・pushまで行う
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

現在のブランチに紐づくPRのレビューコメントをすべて確認し、対応要否を判断した上で、必要な修正・各コメントへの返信・pushまでを行ってください。

## 実行手順

### Step 1: PR情報の取得

```bash
gh pr view --json number,title,url,state,headRefName
```

### Step 2: レビューコメントの取得

bot（Copilot, CodeRabbit, github-advanced-security[bot] など）・人間レビュアーを問わず、すべてのレビューコメントを取得してください。`--paginate` を付けて取得漏れを防ぎます。

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR_NUMBER=$(gh pr view --json number -q .number)

# インラインのレビューコメント（コード行への指摘）
gh api repos/${REPO}/pulls/${PR_NUMBER}/comments --paginate

# レビュー本文（Approve/Request changes時のコメント）
gh api repos/${REPO}/pulls/${PR_NUMBER}/reviews --paginate
```

- 各コメントの `in_reply_to_id` を確認し、**既に返信が付いているコメントは分析対象から除外**してください（再実行時の二重対応・二重返信を防ぐため）。
- 可能であれば GraphQL で `isResolved` を確認し、解決済みスレッドも除外してください：

```bash
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_NAME=$(gh repo view --json name -q .name)

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 1) { nodes { databaseId } }
          }
        }
      }
    }
  }' -f owner="$OWNER" -f repo="$REPO_NAME" -F pr=$PR_NUMBER
```

### Step 3: 各コメントの分析

除外されなかった各レビューコメントについて：

1. **コメント内容の確認**: 何を指摘しているか理解する
2. **関連コードの確認**: 指摘されたファイル・行を `Read` ツールで確認する
3. **対応要否の判断**:
   - **対応必須**: バグ、セキュリティ問題、明らかな改善点
   - **検討**: 設計判断が必要、トレードオフがある → 自分で結論を出し、理由を返信に明記する
   - **対応不要**: 好みの問題、既に対応済み、誤検知 → 理由を返信に明記する

同じ問題を複数のコメントが指摘している場合、修正は1箇所にまとめてよいですが、**返信は指摘ごとに個別**に行ってください。

### Step 4: 実装方針の評価

以下のパターンに該当する場合は、その場で大規模な作り直しを行わず、**Step 8のサマリーで根本的な見直しが必要な旨を報告するだけ**にとどめてください：

- 同じ種類の問題が繰り返し指摘されている
- アーキテクチャレベルの問題が示唆されている
- テストカバレッジの不足が指摘されている

### Step 5: 修正の実施

「対応必須」および「検討の結果対応する」と判断したコメントについて、`Edit` / `Write` ツールでコードを修正してください。

- リポジトリに lint / test コマンドがあれば、修正後に実行して壊れていないことを確認する
- 意味のある単位でコミットする（1コメント1コミットにこだわらず、関連する修正はまとめてよい）
- コミットメッセージには「何を」「なぜ」を簡潔に記載する

```bash
git add <該当ファイル>
git commit -m "..."
```

### Step 6: 各コメントへの返信

インラインのレビューコメントには reply API で返信してください：

```bash
gh api repos/${REPO}/pulls/${PR_NUMBER}/comments/${COMMENT_ID}/replies \
  -f body="対応内容、または対応しない理由"
```

レビュー本文（Step 2の `reviews` エンドポイントで取得したコメント）には reply API が無いため、PRの会話コメントとして返信してください：

```bash
gh pr comment ${PR_NUMBER} --body "@reviewer 対応内容、または対応しない理由"
```

返信には必ず以下のいずれかを含めてください：
- **対応した場合**: 何をどう直したか（該当コミットの要約）
- **対応しなかった場合**: 対応不要と判断した理由

### Step 7: push

```bash
git push
```

- 修正が1件もない場合は push をスキップする
- `--force` は使用しない

### Step 8: 結果サマリー

以下の形式で結果を報告してください：

## 対応結果

**PR**: #番号 - タイトル
**対象コメント**: X件（既に返信済み・解決済みのものは除外）

### 対応済み（X件）
| # | コメント元 | ファイル:行 | 指摘内容 | 対応内容 | コミット |
|---|-----------|------------|---------|---------|---------|

### 対応不要（X件）
| # | コメント元 | ファイル:行 | 指摘内容 | 理由 |
|---|-----------|------------|---------|------|

### 根本的な見直しが必要か
- [ ] はい → 問題パターンと推奨対応を記載
- [ ] いいえ → 個別対応で十分

**push**: 成功 / スキップ（修正なし）
