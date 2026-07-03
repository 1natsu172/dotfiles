#!/usr/bin/env bash
# Fixture 05: rebase-continue-with-validation-failure
# rebase 中で衝突解消は機械的に可能だが、解消後に typecheck が落ちる（暗黙の型不整合）。
# 期待挙動: Phase 2 で適用（ours/theirs どちらを採用しても構文 OK）→ Phase 3 で typecheck
#         失敗を検知 → bail-out。`rebase --continue` を実行しない。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-05-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src

# Initial commit: shared module providing a value of type number
cat > src/value.ts <<'EOF'
export const VALUE: number = 1;
EOF

# Initial caller treats VALUE as number
cat > src/caller.ts <<'EOF'
import { VALUE } from './value';

export function double(): number {
  return VALUE * 2;
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-05",
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
git commit -q -m 'feat: initial value & caller'

# main: caller refactored — no longer arithmetic, just returns VALUE.
cat > src/caller.ts <<'EOF'
import { VALUE } from './value';

export function describe(): string {
  return `value=${VALUE}`;
}
EOF
git add .
git commit -q -m 'refactor(caller): rename to describe and return string'

# feature: starts from initial, changes VALUE to a string (not a number anymore).
# This breaks the original `double()` arithmetic, which still exists in this branch.
git checkout -q -b feature HEAD~1
cat > src/value.ts <<'EOF'
export const VALUE: string = 'one';
EOF
git add .
git commit -q -m 'feat(value): change VALUE type from number to string'

# Now rebase feature onto main — conflict on src/caller.ts
# After resolution (taking either side or integration), src/value.ts will have type
# `string` while src/caller.ts (main side) does `${VALUE}` template — that part
# is fine syntactically. But the original caller had `VALUE * 2` typing — main
# branch removed that. To force a typecheck failure, add another caller on main
# that still relies on number arithmetic but is NOT touched in the conflict file.

# Reset and use a different layout: introduce src/math.ts on main that does VALUE * 2
# and rebase feature (which retypes VALUE to string) onto main.

git checkout -q main
cat > src/math.ts <<'EOF'
import { VALUE } from './value';

export function triple(): number {
  return VALUE * 3;
}
EOF
git add .
git commit -q -m 'feat: add math triple using VALUE'

git checkout -q feature
set +e
git rebase main >/dev/null 2>&1
REBASE_STATUS=$?
set -e

# If the rebase did not stop on a conflict, fail (we expect a conflict on src/value.ts
# or src/caller.ts due to overlapping edits, but VALUE retyping itself does not
# necessarily conflict because the file changed differently). Let's contrive a small
# textual conflict on src/value.ts to ensure rebase stops there.

if [ "$REBASE_STATUS" -eq 0 ]; then
  # Need to force a conflict. Recreate scenario with overlapping line edits.
  git rebase --abort >/dev/null 2>&1 || true
  git checkout -q main
  cat > src/value.ts <<'EOF'
// shared constant
export const VALUE: number = 1;
EOF
  git add .
  git commit -q -m 'docs(value): add header comment'

  git checkout -q feature
  cat > src/value.ts <<'EOF'
// shared constant (retyped to string)
export const VALUE: string = 'one';
EOF
  git add .
  git commit -q --amend --no-edit

  set +e
  git rebase main >/dev/null 2>&1
  REBASE_STATUS=$?
  set -e
fi

if [ "$REBASE_STATUS" -eq 0 ]; then
  echo "ERROR: rebase unexpectedly succeeded; expected a conflict in src/value.ts" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/value.ts; then
  echo "ERROR: expected conflict markers in src/value.ts" >&2
  exit 1
fi

# Sanity: ensure we are mid-rebase
if [ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ]; then
  echo "ERROR: expected to be mid-rebase" >&2
  exit 1
fi

echo "$REPO_DIR"
