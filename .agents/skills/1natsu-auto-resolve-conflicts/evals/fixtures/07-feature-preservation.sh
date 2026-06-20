#!/usr/bin/env bash
# Fixture 07: feature-preservation（相互機能保持 / Point 1）
# 両側がそれぞれ別の機能（関数＋その呼び出し）を同一ファイルの同一領域に追加。
# 片側採用すると他方の機能（関数定義と呼び出し）が丸ごと消える＝デグレ。
# 期待挙動: 両側の機能を統合（両関数を残し summary が両方を参照）して解消し2段コミット。
#           もし統合の安全性に確信が持てなければ bail-out も可（ただし片側採用で機能を
#           黙って捨てるのは NG）。

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-07-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src
cat > src/cart.ts <<'EOF'
export interface Cart {
  items: number[];
}

export function summary(cart: Cart): string {
  const count = cart.items.length;
  return `items: ${count}`;
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-07",
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
git commit -q -m 'feat: initial cart with summary'

# feature/a: subtotal 機能を追加（関数 subtotal ＋ summary での参照）
git checkout -q -b feature/a
cat > src/cart.ts <<'EOF'
export interface Cart {
  items: number[];
}

export function subtotal(cart: Cart): number {
  return cart.items.reduce((a, b) => a + b, 0);
}

export function summary(cart: Cart): string {
  const count = cart.items.length;
  return `items: ${count}, subtotal: ${subtotal(cart)}`;
}
EOF
git add .
git commit -q -m 'feat: add subtotal to cart summary'

# feature/b: maxItem 機能を追加（関数 maxItem ＋ summary での参照）
git checkout -q main
git checkout -q -b feature/b
cat > src/cart.ts <<'EOF'
export interface Cart {
  items: number[];
}

export function maxItem(cart: Cart): number {
  return Math.max(...cart.items);
}

export function summary(cart: Cart): string {
  const count = cart.items.length;
  return `items: ${count}, max: ${maxItem(cart)}`;
}
EOF
git add .
git commit -q -m 'feat: add maxItem to cart summary'

# Merge feature/a into feature/b -> conflict in src/cart.ts
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/cart.ts; then
  echo "ERROR: expected conflict markers in src/cart.ts" >&2
  exit 1
fi

echo "$REPO_DIR"
