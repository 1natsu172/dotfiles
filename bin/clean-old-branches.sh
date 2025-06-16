#!/bin/bash

# 古いブランチを削除するスクリプト
# Usage: ./clean-old-branches.sh [days] [--force]

set -e

DAYS=${1:-30}
FORCE_DELETE=${2:-""}

# 保護するブランチ
PROTECTED_BRANCHES="main|master|develop|dev|staging|production"

echo "🔍 ${DAYS}日より古いブランチを検索中..."

# 削除対象のブランチを確認
OLD_BRANCHES=$(git for-each-ref --format='%(committerdate:iso8601) %(refname:short)' refs/heads/ |
  awk -v date="$(date -v-${DAYS}d +%Y-%m-%d)" '$1 < date {print $2}' |
  grep -vE "^(${PROTECTED_BRANCHES})$" || true)

if [ -z "$OLD_BRANCHES" ]; then
  echo "✅ 削除対象のブランチはありません"
  exit 0
fi

echo "📋 削除対象のブランチ:"
echo "$OLD_BRANCHES" | sed 's/^/  - /'

# 確認プロンプト
if [ "$FORCE_DELETE" != "--force" ]; then
  echo ""
  read -p "⚠️  これらのブランチを削除しますか？ (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ キャンセルされました"
    exit 0
  fi
fi

# 削除実行
echo ""
echo "🗑️  ブランチを削除中..."

# まずはマージ済みブランチのみ安全に削除
DELETED_COUNT=0
FAILED_BRANCHES=""

while IFS= read -r branch; do
  if git branch -d "$branch" 2>/dev/null; then
    echo "  ✅ $branch"
    ((DELETED_COUNT++))
  else
    echo "  ⚠️  $branch (マージされていません)"
    FAILED_BRANCHES="$FAILED_BRANCHES$branch\n"
  fi
done <<<"$OLD_BRANCHES"

echo ""
echo "✨ 完了: ${DELETED_COUNT}個のブランチを削除しました"

# マージされていないブランチがある場合の案内
if [ -n "$FAILED_BRANCHES" ]; then
  echo ""
  echo "⚠️  以下のブランチはマージされていないため削除されませんでした："
  echo -e "$FAILED_BRANCHES" | sed 's/^/  - /'
  echo ""
  echo "💡 強制削除したい場合は以下のコマンドを使用してください："
  echo -e "$FAILED_BRANCHES" | sed 's/^/git branch -D /'
fi
