#!/usr/bin/env bash
# Fixture 10: rebase-1stage-success（Point 3 の rebase=1段が正しく振る舞うか）
# rebase 中のコンフリクトが綺麗に解消でき typecheck も通るケース。
# 期待挙動: 両側の追記を統合解消し `git rebase --continue` で **1段**（単親の rebased コミット）
#           として畳む。merge のような2段（マーカー入りスナップショット）にはしない。
#           履歴に [conflict snapshot] コミットや conflict-snapshot フットプリントが現れないこと。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-10-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src
cat > src/features.ts <<'EOF'
export const features: string[] = [
  'base',
];
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-10",
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
git commit -q -m 'feat: initial features list'

# feature をここ（M0）で分岐
git branch feature

# main が先に進む: 'main' を追加（M1）
cat > src/features.ts <<'EOF'
export const features: string[] = [
  'base',
  'main',
];
EOF
git add .
git commit -q -m 'feat: add main feature on main'

# feature 側: 'feat' を追加（F1）。M0 起点なので main の 'main' を知らない。
git checkout -q feature
cat > src/features.ts <<'EOF'
export const features: string[] = [
  'base',
  'feat',
];
EOF
git add .
git commit -q -m 'feat: add feat feature on feature'

# feature を main に rebase -> F1 の replay で features.ts が衝突
set +e
git rebase main >/dev/null 2>&1
REBASE_STATUS=$?
set -e

if [ "$REBASE_STATUS" -eq 0 ]; then
  echo "ERROR: rebase unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/features.ts; then
  echo "ERROR: expected conflict markers in src/features.ts" >&2
  exit 1
fi

# rebase 進行中であることを確認
if [ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ]; then
  echo "ERROR: expected an in-progress rebase" >&2
  exit 1
fi

echo "$REPO_DIR"
