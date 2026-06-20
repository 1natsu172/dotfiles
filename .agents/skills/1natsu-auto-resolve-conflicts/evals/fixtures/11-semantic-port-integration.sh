#!/usr/bin/env bash
# Fixture 11: semantic-port-integration（相互機能保持の本命・難ケース / Point 1）
# リアルなプロダクトで起きる「構造リファクタ × 機能追加」の競合。
#
#  - commit A (feature/a): インラインの handleClick に、クロージャ変数 history への記録と
#    handleReset を追加（クロージャ依存の機能追加）。消費側 app.ts も handleReset()/history() を使う。
#  - commit B (feature/b): リファクタ＆抽象化。ハンドラを makeHandlers(state) に抽出し、
#    インラインクロージャを state オブジェクトに畳む（構造が変わる）。
#
# テキストマージでは統合できない。正解は「B のリファクタ後に A を書いていたら」という目線で、
# A の history/reset を B の makeHandlers(state) 構造へ **移植** すること。
#
# 失敗モード:
#   - B を丸採用 -> app.ts(A由来) が handleReset/history を要求し typecheck 失敗（検出可）
#   - A を丸採用 -> typecheck は通るが B のリファクタ（makeHandlers/state）がサイレント消失（ゲートの出番）
#   - テキストで混ぜる -> クロージャ参照が壊れ typecheck 失敗
#   - 正しい移植     -> 両方の意図を満たし typecheck 通過（唯一の完全正解）

set -euo pipefail

FIXTURE_TMP="${AUTO_RESOLVE_FIXTURE_TMP:-/tmp/claude/auto-resolve-fixtures}"
if ! mkdir -p "$FIXTURE_TMP" 2>/dev/null; then
  FIXTURE_TMP="${TMPDIR:-/tmp}/auto-resolve-fixtures"
  mkdir -p "$FIXTURE_TMP"
fi
REPO_DIR="$(mktemp -d "$FIXTURE_TMP/fixture-11-XXXXXX")"
cd "$REPO_DIR"

git init -q --initial-branch=main
git config user.email 'fixture@example.invalid'
git config user.name  'Fixture Bot'
git config commit.gpgsign false

mkdir -p src
# Base: インラインの handleClick とクロージャ count
cat > src/counter.ts <<'EOF'
export function createCounter(start: number) {
  let count = start;

  const handleClick = () => {
    count += 1;
  };

  return {
    handleClick,
    get: () => count,
  };
}
EOF

cat > src/app.ts <<'EOF'
import { createCounter } from './counter';

export function demo() {
  const c = createCounter(0);
  c.handleClick();
  return c.get();
}
EOF

cat > package.json <<'EOF'
{
  "name": "fixture-11",
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
git commit -q -m 'feat: initial inline counter'

# feature/a: クロージャ依存の機能追加（history 記録 + handleReset）。消費側も新APIを使う。
git checkout -q -b feature/a
cat > src/counter.ts <<'EOF'
export function createCounter(start: number) {
  let count = start;
  const history: number[] = [];

  const handleClick = () => {
    count += 1;
    history.push(count);
  };

  const handleReset = () => {
    count = 0;
    history.length = 0;
  };

  return {
    handleClick,
    handleReset,
    get: () => count,
    history: () => history,
  };
}
EOF
cat > src/app.ts <<'EOF'
import { createCounter } from './counter';

export function demo() {
  const c = createCounter(0);
  c.handleClick();
  c.handleReset();
  return { count: c.get(), history: c.history() };
}
EOF
git add .
git commit -q -m 'feat: track click history and add reset handler'

# feature/b: リファクタ＆抽象化。ハンドラを makeHandlers(state) に抽出し state オブジェクトへ畳む。
git checkout -q main
git checkout -q -b feature/b
cat > src/counter.ts <<'EOF'
type State = { count: number };

function makeHandlers(state: State) {
  const handleClick = () => {
    state.count += 1;
  };
  return { handleClick };
}

export function createCounter(start: number) {
  const state: State = { count: start };
  const handlers = makeHandlers(state);

  return {
    ...handlers,
    get: () => state.count,
  };
}
EOF
# app.ts は base のまま（B は消費側を変えていない）
git add .
git commit -q -m 'refactor: extract memoizable handlers into makeHandlers(state)'

# Merge feature/a into feature/b
#   counter.ts: 両側が base から書き換え -> 衝突
#   app.ts: A だけが変更 -> 衝突せず A 版が採られる（handleReset/history を要求する）
set +e
git merge --no-edit feature/a >/dev/null 2>&1
MERGE_STATUS=$?
set -e

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "ERROR: merge unexpectedly succeeded; expected a conflict" >&2
  exit 1
fi

if ! grep -q '<<<<<<<' src/counter.ts; then
  echo "ERROR: expected conflict markers in src/counter.ts" >&2
  exit 1
fi
# app.ts は衝突しておらず A 版（handleReset/history を使う）であること
if grep -q '<<<<<<<' src/app.ts; then
  echo "ERROR: did not expect conflict markers in src/app.ts" >&2
  exit 1
fi
if ! grep -q 'handleReset' src/app.ts; then
  echo "ERROR: expected app.ts to require the new API (handleReset)" >&2
  exit 1
fi

echo "$REPO_DIR"
