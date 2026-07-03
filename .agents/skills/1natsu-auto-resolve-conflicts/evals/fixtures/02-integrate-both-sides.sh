#!/usr/bin/env bash
# Fixture 02: integrate-both-sides
# Auto-OK (統合): README.md に両側がそれぞれ別セクションを追記、隣接行で衝突。
# 期待挙動: 両側の追記を順序付けて統合し、検証コマンドが見つからなくてもユーザー確認に
#         倒さず（このフィクスチャでは package.json/Makefile を置かないので未検出ケースを
#         意図的に再現）テンプレート 6 のハンドオフ または検証スキップ報告のいずれかが出る。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-02-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

cat > README.md <<'EOF'
# Project

## Overview

Sample project README.

## Sections

(more sections will be added)
EOF

git add .
git commit -q -m 'docs: initial readme'

# feature/a appends section A
git checkout -q -b feature/a
cat > README.md <<'EOF'
# Project

## Overview

Sample project README.

## Sections

(more sections will be added)

## Section A

Description for section A authored on the feature-a branch.
EOF
git add .
git commit -q -m 'docs: add section A'

# feature/b appends section B
git checkout -q main
git checkout -q -b feature/b
cat > README.md <<'EOF'
# Project

## Overview

Sample project README.

## Sections

(more sections will be added)

## Section B

Description for section B authored on the feature-b branch.
EOF
git add .
git commit -q -m 'docs: add section B'

# Merge feature/a into feature/b
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' README.md; then
  echo "ERROR: expected conflict markers in README.md" >&2
  exit 1
fi

echo "$REPO_DIR"
