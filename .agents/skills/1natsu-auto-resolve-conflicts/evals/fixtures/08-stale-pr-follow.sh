#!/usr/bin/env bash
# Fixture 08: stale-pr-follow（base 追従の起点作り / Point 2 = Phase A）
# 現在ブランチ feature/x は clean で、まだコンフリクトしていない。しかし base（main）が
# 先に進んでおり、main を取り込むと src/app.ts でコンフリクトが起きる（stale PR 相当）。
# 期待挙動: Phase A で base=main を特定し `git merge main` で追従してコンフリクトを発生させ、
#           両側の import を統合して解消、merge の2段コミットまで完了する。
# 注: 使い捨てローカルリポジトリなので origin remote は無い。base はローカル main。
#     PR/gh が無い前提なので、base 検出は default ブランチ（main）にフォールバックする。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-08-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

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
  "name": "fixture-08",
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

# feature/x: PR ブランチ。featureX を追加してコミット（base から分岐）。
git checkout -q -b feature/x
cat > src/featureX.ts <<'EOF'
export function featureX() {
  return 'X';
}
EOF
cat > src/app.ts <<'EOF'
import { existing } from './existing';
import { featureX } from './featureX';

export function run() {
  existing();
  featureX();
}
EOF
git add .
git commit -q -m 'feat: add featureX import (PR branch)'

# base(main) が PR 作成後に進む: featureMain を同じ領域に追加（取り込むと衝突）。
git checkout -q main
cat > src/featureMain.ts <<'EOF'
export function featureMain() {
  return 'M';
}
EOF
cat > src/app.ts <<'EOF'
import { existing } from './existing';
import { featureMain } from './featureMain';

export function run() {
  existing();
  featureMain();
}
EOF
git add .
git commit -q -m 'feat: add featureMain import on base'

# PR ブランチに戻る。ここが起点: clean で未コンフリクト、ただし main より遅れている。
git checkout -q feature/x

# Sanity: 現在は clean（unmerged paths なし）であること
if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
  echo "ERROR: expected a clean (non-conflicting) starting state" >&2
  exit 1
fi
if grep -q '<<<<<<<' src/app.ts; then
  echo "ERROR: did not expect conflict markers at start" >&2
  exit 1
fi
# Sanity: feature/x は main より遅れている（main 側に未取り込みコミットがある）
if [ -z "$(git log --oneline feature/x..main)" ]; then
  echo "ERROR: expected feature/x to be behind main (a follow should be needed)" >&2
  exit 1
fi

echo "$REPO_DIR"
