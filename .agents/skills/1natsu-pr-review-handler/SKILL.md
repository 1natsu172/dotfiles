---
name: 1natsu-pr-review-handler
description: GitHubのPRレビューコメントを自律的に読んで判断・コード修正・返信・サマリー投稿を行う。「レビューを対応して」「PRの指摘を直して」「レビューコメントを処理して」など、PRレビュー対応のタスクで使用する。人間レビュワーとAIレビューツール（Devin, Copilot, CodeRabbit, Gemini等）を区別せず処理する。
license: MIT
metadata:
  author: 1natsu
  version: "1.2.0"
---

# PR Review Handler

GitHubのPRレビューコメントを自律的に処理する。判断・修正・返信・サマリー投稿を一貫して行う。

## Phase 1: PRの特定

引数があればそれを使う。なければ現在のブランチから自動検出する。

```bash
# 引数でPR番号/URLが指定された場合はそれを使う
# なければ現在のブランチのPRを取得
gh pr view --json number,url,title,headRefName,baseRefName,author
```

PR作成者のログイン名を控えておく（Phase 2でフィルタに使う）。

## Phase 2: レビューコメントの収集

GitHub PRのコメントは複数箇所に分散している。**全てのソースを確認**しないと指摘を見落とす。

```bash
PR_NUMBER=<番号>
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR_AUTHOR=<PR作成者のlogin>

# 1. インラインコメント（コードの特定行に紐づく指摘）
gh api repos/$REPO/pulls/$PR_NUMBER/comments \
  --jq '.[] | select(.in_reply_to_id == null) | {id, path, line, body, user: .user.login}'

# 2. レビュー単位のコメント（CHANGES_REQUESTED等のレビュー本文）
#    レビュー本文にnitpickや追加指摘が含まれることがある
gh api repos/$REPO/pulls/$PR_NUMBER/reviews \
  --jq '.[] | select(.state != "APPROVED" and .body != "") | {id, body, state, user: .user.login}'

# 3. 特定レビューに紐づくコメント（レビュー本文内のnitpick等）
#    レビューIDごとに取得
gh api repos/$REPO/pulls/$PR_NUMBER/reviews/$REVIEW_ID/comments \
  --jq '.[] | {id, path, line, body, user: .user.login}'
```

AIレビューツール（CodeRabbit等）はレビュー本文にnitpickを折りたたんで含めることが多い。レビュー本文の`<details>`タグ内にも指摘がないか確認する。

**スキップするコメント：**
- PR作成者（`$PR_AUTHOR`）自身のコメント
- `position == null`（outdated：コードが変わって対象行が消えた）
- すでにresolvedになっているスレッド
- 既に返信済みのコメント（二重対応を防ぐ）

## Phase 3: 各コメントの分析・判断

コメントごとにアクションを決定する。

| アクション | 判断基準 |
|-----------|---------|
| **Fix** | 修正箇所と内容が明確。バグ、命名、typo、スタイル統一 |
| **Skip** | スコープ外、意図的な設計への反論、別PRで対応すべき内容 |
| **AskUser** | アーキテクチャ選択、設計方針の選択、ビジネスコンテキストが必要 |

**Fix判断のポイント：**
- 変更箇所が特定できる（ファイル・行がわかる）
- 既存コードのパターンや慣習と照合して判断できる
- 変更の影響範囲が局所的で副作用が読める
- コメントに`suggestion`ブロックがある場合は、その提案コードを参考にする

**AskUser判断のポイント：**
- 複数の正解がある選択肢を迫られている
- ビジネス要件や優先度の判断が必要
- 大きなリファクタリングや設計変更を伴う

## Phase 4: ユーザー確認（AskUserがある場合）

AskUserと判断したコメントがある場合、**ここで作業を一時停止**してユーザーに確認する。

```
以下のコメントは判断が必要です。どう対応しますか？

1. [@reviewer] "コメント内容"
   → A: [選択肢A]
   → B: [選択肢B]
   → スキップ（今回は対応しない）

2. ...
```

ユーザーの指示を受けてから Phase 5 に進む。

## Phase 5: コード修正

Fixと判断したコメント（＋ユーザーが指示した対応）を順番に修正する。

1. 対象ファイルを読む
2. コメントが指している箇所を特定する
3. 修正を適用する
4. 修正内容をメモしておく（後の返信・サマリーに使う）

同一ファイルへの複数コメントはまとめて修正する。

## Phase 6: コミット & プッシュ

全修正が完了したらコミット・プッシュする。

```bash
git add <修正したファイル>
git commit -m "fix: address PR review comments

- [修正した指摘の簡潔な説明]
- ..."
git push
```

コミットメッセージは `1natsu-commit` スキルのConventional Commitsルールに従う。
`git add -A` ではなく修正したファイルを個別に指定する。

## Phase 7: コメント返信

各レビューコメントに個別に返信する。返信には**変更箇所へのリンク**を含める。

コミットSHAはPhase 6のプッシュ後に取得する：
```bash
COMMIT_SHA=$(git rev-parse HEAD)
```

**Fixしたコメントへの返信（単一箇所の変更）：**
```
対応しました。[何をどう変えたか1〜2行]

https://github.com/$REPO/blob/$COMMIT_SHA/$FILE_PATH#L$LINE
```

**Fixしたコメントへの返信（複数箇所にまたがる変更）：**
```
対応しました。[何をどう変えたか1〜2行]

https://github.com/$REPO/commit/$COMMIT_SHA
```

**Skipしたコメントへの返信：**
```
[理由]のため今回は対応を見送りました。
```

返信は簡潔に。詳細な説明は不要。リンクがあれば読み手が自分で確認できる。

**全ての返信にフッター署名を付ける：**
```
---
<sub>🤖 by [1natsu-pr-review-handler](https://github.com/1natsu-vacation/agent-skills) | $AI_TOOL ($MODEL_NAME)</sub>
```

`$AI_TOOL` と `$MODEL_NAME` は実行環境に合わせる（例: `Claude Code (claude-opus-4-6)`、`Cursor (gpt-4o)` 等）。

## Phase 8: サマリーコメント投稿

PRにサマリーコメントを**1つだけ**投稿する。

```bash
COMMIT_SHA=$(git rev-parse HEAD)

gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## レビュー対応サマリー

### 対応済み
- **[コメントの要約]**: [対応内容] ([`$FILE_PATH#L$LINE`](https://github.com/$REPO/blob/$COMMIT_SHA/$FILE_PATH#L$LINE))
- ...

### 要確認
- **[コメントの要約]**: [理由・質問内容]
- ...

---
<sub>🤖 by [1natsu-pr-review-handler](https://github.com/1natsu-vacation/agent-skills) | $AI_TOOL ($MODEL_NAME)</sub>
EOF
)"
```

要確認項目がなければ「要確認」セクションは省略する。

## よくある注意点

| 状況 | 対応 |
|------|------|
| outdatedコメント（position == null）| スキップ。返信もしない |
| 同じ指摘が複数レビュワーから来ている | まとめて1回修正し、各コメントに個別返信 |
| AIレビューツールのコメント | 人間と同様に処理する |
| 修正すると他の指摘と矛盾する | 優先度の高い方を採用し、もう一方の返信に理由を記載 |
| suggestionブロック付きコメント | 提案コードを参考にしつつ、プロジェクト慣習に合わせて修正 |
| レビュー本文内のnitpick | 折りたたみ内も確認し、見落とさない |
