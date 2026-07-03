#!/usr/bin/env bash
# Fixture 09: silent-feature-drop-trap（相互機能保持の本命テスト / Point 1）
# 両側が「同じ return オブジェクトに別々のキーを1行ずつ足す」だけの、一見「片側を採れば済む」
# ように見えるコンフリクト。だが片側採用すると他方が追加したキー（機能）がサイレントに消える。
# 消費側 src/app.ts は timeout しか参照しないので、retry/cache を落としても **typecheck は通る**
# （＝Phase 3 検証では検出できない）。したがって相互機能保持ゲートだけが落ちを捕まえられる。
# 期待挙動: 両キー（retry + cache）を保持して統合解消。片側採用で一方のキーを捨てたら誤り。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-09-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src
cat > src/config.ts <<'EOF'
export function buildConfig() {
  return {
    timeout: 30,
  };
}
EOF

# 消費側は timeout しか使わない => retry/cache を落としても型エラーにならない（サイレント）
cat > src/app.ts <<'EOF'
import { buildConfig } from './config';

export function start(): number {
  const cfg = buildConfig();
  return cfg.timeout;
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-09",
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
git commit -q -m 'feat: initial buildConfig with timeout'

# feature/a: retry 機能を追加（return オブジェクトに retry: 3）
git checkout -q -b feature/a
cat > src/config.ts <<'EOF'
export function buildConfig() {
  return {
    timeout: 30,
    retry: 3,
  };
}
EOF
git add .
git commit -q -m 'feat: add retry option to config'

# feature/b: cache 機能を追加（return オブジェクトに cache: true）
git checkout -q main
git checkout -q -b feature/b
cat > src/config.ts <<'EOF'
export function buildConfig() {
  return {
    timeout: 30,
    cache: true,
  };
}
EOF
git add .
git commit -q -m 'feat: add cache option to config'

# Merge feature/a into feature/b -> src/config.ts の return 付近で衝突
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/config.ts; then
  echo "ERROR: expected conflict markers in src/config.ts" >&2
  exit 1
fi

echo "$REPO_DIR"
