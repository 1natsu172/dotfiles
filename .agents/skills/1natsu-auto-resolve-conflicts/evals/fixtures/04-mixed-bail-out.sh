#!/usr/bin/env bash
# Fixture 04: mixed-bail-out
# 5 ファイルがコンフリクト。3 つは Auto-OK（README/import/設定別キー）、
# 2 つは Auto-No（auth 系の両側変更 + DB マイグレーションの両側変更）。
# 期待挙動: Auto-OK 3 ファイルは適用、残り 2 ファイルは pair に渡す（混合 bail-out）。
#         Phase 4 には進まない（コミットを作成しない）。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-04-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src/auth db/migrations docs

# Auto-OK seed: README
cat > docs/README.md <<'EOF'
# Project Docs

## Overview
EOF

# Auto-OK seed: imports
cat > src/index.ts <<'EOF'
import { existing } from './existing';

export const main = () => {
  existing();
};
EOF

cat > src/existing.ts <<'EOF'
export const existing = () => 'ok';
EOF

# Auto-OK seed: config (different keys)
cat > config.json <<'EOF'
{
  "name": "fixture-04",
  "version": "0.0.0"
}
EOF

# Auto-No seed: auth file
cat > src/auth/policy.ts <<'EOF'
export const policy = {
  allow: ['admin'],
};
EOF

# Auto-No seed: db migration (timestamped)
cat > db/migrations/2024_01_01_init.sql <<'EOF'
CREATE TABLE users (id INT PRIMARY KEY);
EOF

git add .
git commit -q -m 'feat: initial project'

# feature/a: Auto-OK changes + Auto-No changes
git checkout -q -b feature/a
cat > docs/README.md <<'EOF'
# Project Docs

## Overview

Sample overview from feature-a.
EOF
cat > src/index.ts <<'EOF'
import { existing } from './existing';
import { featureA } from './featureA';

export const main = () => {
  existing();
  featureA();
};
EOF
cat > src/featureA.ts <<'EOF'
export const featureA = () => 'A';
EOF
cat > config.json <<'EOF'
{
  "name": "fixture-04",
  "version": "0.0.0",
  "featureA": true
}
EOF
cat > src/auth/policy.ts <<'EOF'
export const policy = {
  allow: ['admin', 'editor'],
  audit: 'verbose',
};
EOF
cat > db/migrations/2024_01_01_init.sql <<'EOF'
CREATE TABLE users (
  id INT PRIMARY KEY,
  email VARCHAR(255) NOT NULL
);
EOF
git add .
git commit -q -m 'feat: feature-a additions (auto-ok + auth/db)'

# feature/b: same files but different changes
git checkout -q main
git checkout -q -b feature/b
cat > docs/README.md <<'EOF'
# Project Docs

## Overview

Sample overview from feature-b.
EOF
cat > src/index.ts <<'EOF'
import { existing } from './existing';
import { featureB } from './featureB';

export const main = () => {
  existing();
  featureB();
};
EOF
cat > src/featureB.ts <<'EOF'
export const featureB = () => 'B';
EOF
cat > config.json <<'EOF'
{
  "name": "fixture-04",
  "version": "0.0.0",
  "featureB": true
}
EOF
cat > src/auth/policy.ts <<'EOF'
export const policy = {
  allow: ['admin'],
  rateLimit: 100,
};
EOF
cat > db/migrations/2024_01_01_init.sql <<'EOF'
CREATE TABLE users (
  id INT PRIMARY KEY,
  username VARCHAR(64) NOT NULL UNIQUE
);
EOF
git add .
git commit -q -m 'feat: feature-b additions (auto-ok + auth/db)'

# Merge feature/a into feature/b
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected conflicts" >&2
  exit 1
fi

# Sanity: count conflicts (should be at least 5 files)
CONFLICTS=$(git diff --name-only --diff-filter=U | wc -l | tr -d ' ')
if [ "$CONFLICTS" -lt 5 ]; then
  echo "ERROR: expected at least 5 conflicting files, got $CONFLICTS" >&2
  exit 1
fi

echo "$REPO_DIR"
