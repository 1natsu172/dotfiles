---
name: 1natsu-create-pr
description: GitHub PRの作成、PRタイトルやdescriptionの記述時に使用する。Conventional Commitsフォーマットのタイトル、構造化されたdescription、多言語対応（en/ja）を提供する。
argument-hint: "[lang]"
license: MIT
metadata:
  author: 1natsu
  version: "1.4.0"
---

# Pull Requestの作成

Conventional Commitsフォーマットと構造化されたdescriptionで高品質なGitHub PRを作成する。

## ワークフロー

### ステップ1: ベースブランチの解決とブランチの変更を分析

意味のあるPRを書くために必要な情報をすべて収集する。最新のコミットだけでなく、マージベースからの**すべてのコミット**を分析する。

#### ベースブランチの自動解決

PRのマージ先（ベースブランチ）は以下の優先順位で決定する。featブランチを直接mainにマージするのではなく、Epicブランチ（機能集積ブランチ）に合流させるワークフローに対応するため、ブランチ名の階層構造を活用する。

**1. スラッシュネストによる親ブランチ推論（優先）**

現在のブランチ名にスラッシュが2つ以上含まれる場合（= 階層がネストしている場合）、末尾のセグメントを1つずつ除去しながら、リモートに存在する親ブランチを探す。

```
例: epic/hoge-1234/feat/auth
  → "epic/hoge-1234/feat" が origin に存在する？ → No
  → "epic/hoge-1234" が origin に存在する？ → Yes → ベースブランチ決定
```

```bash
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH=""

# スラッシュが2つ以上あれば親ブランチを探索
SLASH_COUNT=$(echo "$CURRENT_BRANCH" | tr -cd '/' | wc -c | tr -d ' ')
if [ "$SLASH_COUNT" -ge 2 ]; then
  CANDIDATE="$CURRENT_BRANCH"
  while [ "$SLASH_COUNT" -ge 1 ]; do
    CANDIDATE=$(echo "$CANDIDATE" | sed 's|/[^/]*$||')
    if git show-ref --verify --quiet "refs/remotes/origin/$CANDIDATE"; then
      BASE_BRANCH="$CANDIDATE"
      break
    fi
    SLASH_COUNT=$(echo "$CANDIDATE" | tr -cd '/' | wc -c | tr -d ' ')
  done
fi
```

**2. Git設定によるフォールバック（スラッシュネストなし or 親が見つからない場合）**

```bash
if [ -z "$BASE_BRANCH" ]; then
  # 追跡ブランチの設定を確認
  TRACKING=$(git config "branch.$CURRENT_BRANCH.merge" 2>/dev/null | sed 's|^refs/heads/||')
  if [ -n "$TRACKING" ] && [ "$TRACKING" != "$CURRENT_BRANCH" ]; then
    BASE_BRANCH="$TRACKING"
  else
    # リポジトリのデフォルトブランチにフォールバック
    BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
  fi
fi
```

#### 変更の収集

```bash
MERGE_BASE=$(git merge-base "origin/$BASE_BRANCH" HEAD)

# 並列実行
git status &
git diff --cached &
git log --oneline "$MERGE_BASE..HEAD" &
git diff --stat "$MERGE_BASE..HEAD" &
wait
```

解決した `BASE_BRANCH` はステップ6の `gh pr create` で `--base` オプションに指定する。

### ステップ2: 言語の決定

以下の優先順位で言語を決定する：
1. 引数（`$ARGUMENTS`）で指定された言語コード
2. ユーザーがプロンプトで指定した言語
3. デフォルト: `en`（英語）

**使用例：**
- `/1natsu-create-pr` → 英語（デフォルト）
- `/1natsu-create-pr ja` → 日本語
- `/1natsu-create-pr en` → 英語（明示指定）

**対応言語：**
- `en` — English（Summary, Test plan）
- `ja` — Japanese（概要, テスト計画）

一貫性を保つ — 1つのPR内で言語を混ぜない。

### ステップ3: PRタイトルの作成

[Conventional Commits](https://www.conventionalcommits.org/) フォーマットに従う（タイプやdescriptionの詳細ルールは `1natsu-conventional-commits` スキルを参照）：

```
<type>(<scope>): <description>
```

**例：**
```
feat(auth): add OAuth2 authentication
fix(api): resolve timeout on large requests
docs(readme): update installation instructions
refactor(db): extract query builder into module
```

### ステップ4: PR descriptionの作成

**基本構成：**

```markdown
## Summary
- 変更の簡潔な説明（1-3箇条書き）
- whatとwhyに焦点を当て、howには触れない

## Test plan
- [ ] テストケース1
- [ ] テストケース2
- [ ] リグレッションがないことを確認
```

**複雑なPRでは必要に応じてセクションを追加：**

```markdown
## Summary
- 主な変更点

## Background
コンテキストや動機

## Implementation Details
アプローチの概要

## Test plan
- [ ] テスト
```

**重要な原則：**
- Summary：1-3箇条書き、現在形、何をなぜ変更したか
- Test plan：チェックボックス形式、具体的で実行可能なシナリオ
- Summaryに実装の詳細を入れない（それはコードにある）

### ステップ5: プロジェクトテンプレートの確認

`.github/pull_request_template.md` が存在する場合：
- その構造に正確に従う
- セクションヘッダーを変更したり独自セクションを追加しない
- すべてのセクションを埋める（該当しない場合は "N/A"）

### ステップ6: PRの作成

```bash
gh pr create --draft --base "$BASE_BRANCH" --title "feat(scope): description" --body "$(cat <<'EOF'
## Summary
- Changes

## Test plan
- [ ] Tests
EOF
)"
```

**重要：**
- デフォルトで `--draft` フラグを使用する
- `--base` にステップ1で解決した `BASE_BRANCH` を指定する
- 複数行のbodyには HEREDOC（`cat <<'EOF'`）を使う
- リモートにブランチがなければ先に `git push -u origin <branch>` でpushする
- 完了時にPR URLを返す

## 言語別の例

### English

```markdown
## Summary
- Add user authentication with OAuth2
- Implement token refresh mechanism

## Test plan
- [ ] Test OAuth2 login flow
- [ ] Test token refresh
- [ ] Verify error handling
```

### Japanese

```markdown
## 概要
- OAuth2によるユーザー認証を追加
- トークンリフレッシュ機能を実装

## テスト計画
- [ ] OAuth2ログインフローのテスト
- [ ] トークンリフレッシュのテスト
- [ ] エラーハンドリングの確認
```

## よくある間違い

| 間違い | 修正 |
|--------|------|
| リモートにpushせずに `gh pr create` する | 先に `git push -u origin <branch>` を実行する |
| ベースブランチを常にmain/developにする | ステップ1の自動解決ロジックに従い、Epicブランチ等の親ブランチを正しく特定する |
| `--base` を指定しない | 自動解決した `BASE_BRANCH` を必ず `--base` で明示する |
| タイトルに絵文字を使う | 絵文字は使わない |
| `Add new feature`（タイプなし） | `feat: add new feature` |
| 最新のコミットだけを分析 | マージベースからの**すべて**のコミットを分析 |
| 曖昧な説明 | whatとwhyを具体的に書く |
| 言語の混在 | PR内で一貫した言語を使う |

## リファレンス

各種シナリオ（機能追加、バグ修正、リファクタリング、セキュリティ修正、破壊的変更）のPR descriptionテンプレート（英語・日本語）は [references/pr-templates.md](references/pr-templates.md) を参照。