#!/usr/bin/env bash
# Fixture 06: lockfile-regenerate
# Auto-OK + Auto-Regenerate: package.json は両側で別ライブラリを追加（dependencies 統合）。
# package-lock.json は両側で異なる解決済みエントリを持つため衝突するが、ベストプラクティス
# 通り `npm install` で再生成する。
# 期待挙動: package.json を統合 → package-lock.json を再生成 → frozen 検証 →
#         （ネットワーク不可なら Auto-No 扱いで bail-out。評価時はこのケースを許容する）

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-06-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

cat > package.json <<'EOF'
{
  "name": "fixture-06",
  "private": true,
  "version": "0.0.0",
  "dependencies": {
    "lodash": "4.17.21"
  }
}
EOF

cat > package-lock.json <<'EOF'
{
  "name": "fixture-06",
  "version": "0.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "fixture-06",
      "version": "0.0.0",
      "dependencies": {
        "lodash": "4.17.21"
      }
    },
    "node_modules/lodash": {
      "version": "4.17.21",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz",
      "integrity": "sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg=="
    }
  }
}
EOF

git add .
git commit -q -m 'feat: initial deps'

# feature/a: add ramda (independent library)
git checkout -q -b feature/a
cat > package.json <<'EOF'
{
  "name": "fixture-06",
  "private": true,
  "version": "0.0.0",
  "dependencies": {
    "lodash": "4.17.21",
    "ramda": "0.29.1"
  }
}
EOF
cat > package-lock.json <<'EOF'
{
  "name": "fixture-06",
  "version": "0.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "fixture-06",
      "version": "0.0.0",
      "dependencies": {
        "lodash": "4.17.21",
        "ramda": "0.29.1"
      }
    },
    "node_modules/lodash": {
      "version": "4.17.21",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz",
      "integrity": "sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg=="
    },
    "node_modules/ramda": {
      "version": "0.29.1",
      "resolved": "https://registry.npmjs.org/ramda/-/ramda-0.29.1.tgz",
      "integrity": "sha512-OfxIeWzd4xdUNxlWhgFazxsA/nl3SH6bib6Q1PwUUTMt3SAOPi4FxoSBLbyhRclrZ9sX/xtg/iQyFa6stPXLuA=="
    }
  }
}
EOF
git add .
git commit -q -m 'feat: add ramda dependency'

# feature/b: add date-fns (different independent library)
git checkout -q main
git checkout -q -b feature/b
cat > package.json <<'EOF'
{
  "name": "fixture-06",
  "private": true,
  "version": "0.0.0",
  "dependencies": {
    "lodash": "4.17.21",
    "date-fns": "3.0.0"
  }
}
EOF
cat > package-lock.json <<'EOF'
{
  "name": "fixture-06",
  "version": "0.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "fixture-06",
      "version": "0.0.0",
      "dependencies": {
        "lodash": "4.17.21",
        "date-fns": "3.0.0"
      }
    },
    "node_modules/lodash": {
      "version": "4.17.21",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz",
      "integrity": "sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg=="
    },
    "node_modules/date-fns": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/date-fns/-/date-fns-3.0.0.tgz",
      "integrity": "sha512-9ZipUL1BFK6Bs3Z08IWWKHM62OiCaRfk6Z+aS/IfPJBxGhNRY0yxzaECNl7GYS5Y6Rcgo2xPBGGqIB6cu30NIA=="
    }
  }
}
EOF
git add .
git commit -q -m 'feat: add date-fns dependency'

# Merge feature/a into feature/b — both package.json and package-lock.json conflict.
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected conflicts" >&2
  exit 1
fi

CONFLICTS=$(git diff --name-only --diff-filter=U)
if ! echo "$CONFLICTS" | grep -q '^package\.json$'; then
  echo "ERROR: expected conflict in package.json" >&2
  exit 1
fi
if ! echo "$CONFLICTS" | grep -q '^package-lock\.json$'; then
  echo "ERROR: expected conflict in package-lock.json" >&2
  exit 1
fi

echo "$REPO_DIR"
