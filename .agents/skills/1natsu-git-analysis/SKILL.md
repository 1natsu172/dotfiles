---
name: 1natsu-git-analysis
description: gitリポジトリの変更、ブランチの差分、コミット履歴を分析する。ブランチ分析、変更比較、コミット履歴の確認、PR作成の準備、コード変更のレビュー時に使用する。
license: MIT
metadata:
  author: 1natsu
  version: "1.1.0"
---

# Git 分析

gitリポジトリの状態を分析する — ブランチ、コミット、差分、作業ディレクトリの変更。

## いつ使うか

- ブランチで何が変更されたかを分析するとき
- PR作成やコードレビューのために情報を整理するとき
- ブランチの比較やコミット履歴を確認するとき
- コミット前にコード変更を把握するとき

## クイックスタート

よく使う操作のヘルパースクリプトを実行する：

```bash
# ブランチ差分の要約（デフォルトブランチ、マージベース、コミット数、ファイル統計）
bash scripts/get_branch_diff.sh

# マージベースからの構造化されたコミット履歴
bash scripts/get_commit_history.sh
```

## 基本ワークフロー

### 1. デフォルトブランチとマージベースの特定

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
MERGE_BASE=$(git merge-base origin/$DEFAULT_BRANCH HEAD)
```

マージベースは現在のブランチが分岐した地点。ベースブランチの現在の状態ではなく、常にここから比較する。

### 2. 変更の分析

効率のためにこれらを並列実行する：

```bash
# 分岐以降のコミット
git log --oneline $MERGE_BASE..HEAD

# ファイル変更の統計
git diff --stat $MERGE_BASE..HEAD

# 構造化されたコミットデータ
git log --format="%H|%s|%an|%ae|%ad" --date=iso $MERGE_BASE..HEAD
```

### 3. 作業ディレクトリの確認

```bash
git status                # 全体のステータス
git diff --cached         # ステージ済みの変更
git diff                  # 未ステージの変更
```

## 出力フォーマット

分析結果はまず要約、次に詳細を提示する：

```
Branch: feature/new-feature (from main)
Diverged at: abc123d (2025-01-15)

5 commits | 12 files changed | +234 -89

Recent commits:
1. feat(api): add new endpoint
2. test(api): add endpoint tests
3. docs(api): update documentation
```

## ヘルパースクリプト

### get_branch_diff.sh

構造化されたキーバリューペアを出力する：

```
DEFAULT_BRANCH: main
MERGE_BASE: abc123def456
COMMITS: 5
CHANGED_FILES: 12
INSERTIONS: 234
DELETIONS: 89
```

### get_commit_history.sh

パイプ区切りのコミットデータを1行ずつ出力する：

```
hash|subject|author_name|author_email|date
```

オプションでマージベースを引数として受け取る。省略時は自動検出。

## エラーハンドリング

分析前に前提条件を確認する：

```bash
# gitリポジトリかどうか確認
git rev-parse --git-dir > /dev/null 2>&1 || echo "Not in a git repository"

# リモートが存在するか確認
git ls-remote origin > /dev/null 2>&1 || echo "Remote 'origin' not found"
```

## リファレンス

高度なgitコマンドパターン、plumbingコマンド、パフォーマンス最適化のヒントは [references/git-commands.md](references/git-commands.md) を参照。