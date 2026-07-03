#!/usr/bin/env bash
# Fixture 03: api-signature-degrade
# Auto-No: ours が関数シグネチャを変更、theirs は同関数の呼び出し側を別の意図で変更し
#         ており追従していない。片側採用ではどちらかが必ず壊れるためデグレ確実。
# 期待挙動: Phase 1 で Auto-No 判定 → 何も適用せず pair-resolve への引き継ぎを推薦。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-03-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src

cat > src/api.ts <<'EOF'
export function fetchUser(id: string) {
  return { id, name: 'placeholder' };
}
EOF

cat > src/page.ts <<'EOF'
import { fetchUser } from './api';

export function renderUser(id: string) {
  const user = fetchUser(id);
  return `User: ${user.name}`;
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-03",
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
git commit -q -m 'feat: initial api & page'

# feature/a: changes fetchUser signature to accept an options object.
# Does NOT update src/page.ts to follow the new signature.
git checkout -q -b feature/a
cat > src/api.ts <<'EOF'
export function fetchUser(opts: { id: string; locale?: string }) {
  return { id: opts.id, name: 'placeholder', locale: opts.locale ?? 'en' };
}
EOF
git add .
git commit -q -m 'refactor(api): fetchUser takes an options object'

# feature/b: keeps original fetchUser signature, changes the renderUser
# to display extra information by directly calling fetchUser(id) with the old API.
git checkout -q main
git checkout -q -b feature/b
cat > src/api.ts <<'EOF'
export function fetchUser(id: string) {
  return { id, name: 'placeholder', email: `${id}@example.invalid` };
}
EOF
cat > src/page.ts <<'EOF'
import { fetchUser } from './api';

export function renderUser(id: string) {
  const user = fetchUser(id);
  return `User: ${user.name} <${user.email}>`;
}
EOF
git add .
git commit -q -m 'feat(page): include email in renderUser'

# Merge feature/a into feature/b to produce a sigature conflict.
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/api.ts; then
  echo "ERROR: expected conflict markers in src/api.ts" >&2
  exit 1
fi

echo "$REPO_DIR"
