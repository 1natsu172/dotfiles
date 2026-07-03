# Git コマンド リファレンス

## ブランチ情報

```bash
# デフォルトブランチの取得
git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'

# 代替方法: リモートに問い合わせ
git remote show origin | grep 'HEAD branch' | awk '{print $NF}'

# 現在のブランチの取得
git branch --show-current
```

## マージベース操作

```bash
# 現在のブランチとリモートデフォルトの間
git merge-base origin/main HEAD

# 2つのブランチ間
git merge-base branch1 branch2

# マージベースの詳細表示
MERGE_BASE=$(git merge-base origin/main HEAD)
git show --no-patch --format="%H %s (%an, %ar)" $MERGE_BASE
```

## コミット履歴のフォーマット

```bash
# 1行表示
git log --oneline <merge-base>..HEAD

# 構造化（パイプ区切り）
git log --format="%H|%s|%an|%ae|%ad" --date=iso <merge-base>..HEAD

# 変更ファイル付き
git log --name-status <merge-base>..HEAD

# 著者でフィルタ
git log --author="Name" <merge-base>..HEAD

# 日付でフィルタ
git log --since="2 weeks ago" <merge-base>..HEAD

# ファイルでフィルタ
git log <merge-base>..HEAD -- path/to/file
```

## 差分操作

```bash
# 要約統計
git diff --stat <merge-base>..HEAD
git diff --shortstat <merge-base>..HEAD

# ファイル名のみ
git diff --name-only <merge-base>..HEAD

# ファイル名とステータス（A/M/D）
git diff --name-status <merge-base>..HEAD

# ファイルごとの行数
git diff --numstat <merge-base>..HEAD

# 空白を無視
git diff -w <merge-base>..HEAD
```

## 作業ディレクトリ

```bash
# 短縮ステータス
git status -s

# 未追跡ファイル
git ls-files --others --exclude-standard

# ステージ済みファイル
git diff --cached --name-only

# リモートとのahead/behind確認
git rev-list --left-right --count origin/main...HEAD
```

## パフォーマンスのヒント

- スクリプティングにはplumbingコマンドを使う（`git rev-parse`, `git diff-index`）
- 出力の深さを制限する：`git log --max-count=10`
- 独立したコマンドは `&` と `wait` で並列実行する
- diffのコンテキストを制限する：`git diff --unified=1`

## 堅牢なスクリプトテンプレート

```bash
#!/usr/bin/env bash
set -euo pipefail

git rev-parse --git-dir > /dev/null 2>&1 || { echo "Not in a git repo" >&2; exit 1; }
git ls-remote origin > /dev/null 2>&1 || { echo "Remote 'origin' not found" >&2; exit 1; }

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || { echo "Cannot determine default branch" >&2; exit 1; }
MERGE_BASE=$(git merge-base origin/"$DEFAULT_BRANCH" HEAD 2>/dev/null) || { echo "Cannot determine merge base" >&2; exit 1; }
```