#!/usr/bin/env bash
# Fixture 01: simple-import-merge
# Auto-OK 典型: 同一 TS ファイルで両側が異なる import を追加しただけ。
# 期待挙動: 自動解消 → typecheck (tsc --noEmit) 成功 → コミット完了。

set -euo pipefail

# Allow override via env; default tries Claude-harness friendly path first,
# then falls back to $TMPDIR/auto-resolve-fixtures so it also works outside the harness.
FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-01-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

# Initial commit on main
mkdir -p src
cat > src/app.ts <<'EOF'
import { existing } from './existing';

export function run() {
  existing();
}
EOF

cat > src/existing.ts <<'EOF'
export function existing() {
  return 'ok';
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-01",
  "private": true,
  "scripts": {
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "typescript": "^5.5.0"
  }
}
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"]
}
EOF

git add .
git commit -q -m 'feat: initial app skeleton'

# Feature branch: adds an import for `featureA`
git checkout -q -b feature/a
cat > src/featureA.ts <<'EOF'
export function featureA() {
  return 'A';
}
EOF
cat > src/app.ts <<'EOF'
import { existing } from './existing';
import { featureA } from './featureA';

export function run() {
  existing();
  featureA();
}
EOF
git add .
git commit -q -m 'feat: add featureA import'

# Back to main, add a different import on a sibling branch
git checkout -q main
git checkout -q -b feature/b
cat > src/featureB.ts <<'EOF'
export function featureB() {
  return 'B';
}
EOF
cat > src/app.ts <<'EOF'
import { existing } from './existing';
import { featureB } from './featureB';

export function run() {
  existing();
  featureB();
}
EOF
git add .
git commit -q -m 'feat: add featureB import'

# Merge feature/a into feature/b to produce conflict in src/app.ts
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

# Sanity: ensure conflict marker is present
if ! grep -q '<<<<<<<' src/app.ts; then
  echo "ERROR: expected conflict markers in src/app.ts" >&2
  exit 1
fi

echo "$REPO_DIR"
