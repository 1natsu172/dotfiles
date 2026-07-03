# 検証コマンド自動検出ガイド

`1natsu-auto-resolve-conflicts` の Phase 3 で参照する。プロジェクト構造から `typecheck` / `lint` / `test` / `build` のコマンドを抽出し、変更ファイルが属する範囲に絞って実行するためのフロー。

## 検出フロー全体像

1. リポジトリ直下のマーカーファイルを列挙
2. モノレポか単一プロジェクトかを判定
3. パッケージマネージャを判定（複数候補がある場合は lockfile で確定）
4. 言語/エコシステム別の検証カテゴリを抽出
5. 変更ファイルの所属 workspace に絞り込み
6. 順序通り実行

## マーカーファイル一覧

リポジトリ直下に存在するか `find` で確認する：

| マーカー | 言語/エコシステム |
|---------|-------------------|
| `package.json` | Node.js / JS / TS |
| `bun.lockb` | Bun |
| `pnpm-lock.yaml` + `pnpm-workspace.yaml` | pnpm（モノレポ可） |
| `yarn.lock` | Yarn |
| `package-lock.json` | npm |
| `pyproject.toml` | Python（uv / poetry / hatch / setuptools） |
| `requirements*.txt` | Python（pip） |
| `Pipfile` | Python（pipenv） |
| `Cargo.toml` + `Cargo.lock` | Rust |
| `go.mod` | Go |
| `Gemfile` | Ruby |
| `composer.json` | PHP |
| `Makefile` | 任意のビルドターゲット |
| `Justfile` / `justfile` | just タスクランナー |
| `mise.toml` / `.mise.toml` | mise タスク |
| `.pre-commit-config.yaml` | pre-commit hooks |
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `lerna.json` | Lerna |

## モノレポ判定

以下が存在すればモノレポと判定し、変更ファイルが属する workspace に絞って検証する：

- `pnpm-workspace.yaml`
- `turbo.json`
- `nx.json`
- `lerna.json`
- ルート `package.json` の `workspaces` フィールド
- `Cargo.toml` の `[workspace]` セクション
- `go.work`

### モノレポでの絞り込み手順

1. `git diff --name-only --diff-filter=U` で変更ファイル一覧を取得
2. 各ファイルが属する workspace（`packages/X`, `apps/Y` 等）を判定
3. workspace ごとに該当する検証コマンドを実行（例: `pnpm --filter X test`, `turbo run test --filter=X`, `nx test X`, `cargo test -p X`）
4. workspace 横断の依存（`packages/shared` を `apps/web` から参照等）がある場合は、依存元 workspace も検証対象に含める

## パッケージマネージャ判定（JS/TS）

複数の lockfile が混在することがあるため、以下の優先順位で確定する：

1. `bun.lockb` → bun
2. `pnpm-lock.yaml` → pnpm
3. `yarn.lock` → yarn（v1 / berry は別途判定）
4. `package-lock.json` → npm

`packageManager` フィールドが `package.json` にあればそれを優先する。

実行コマンドの形式：

| pm | typecheck | lint | test | build |
|----|----------|------|------|-------|
| bun | `bun run typecheck` | `bun run lint` | `bun test` または `bun run test` | `bun run build` |
| pnpm | `pnpm typecheck` | `pnpm lint` | `pnpm test` | `pnpm build` |
| yarn | `yarn typecheck` | `yarn lint` | `yarn test` | `yarn build` |
| npm | `npm run typecheck` | `npm run lint` | `npm test` | `npm run build` |

## 言語別の検証カテゴリ抽出

### JS / TS

`package.json` の `scripts` から以下のキーを優先順に探す：

- typecheck: `typecheck`, `type-check`, `tsc`, `check-types`
  - 見つからず `tsconfig.json` がある場合 → `tsc --noEmit` をフォールバック
- lint: `lint`, `eslint`, `lint:js`, `lint:ts`, `check`
- test: `test`, `test:unit`, `test:ci`
  - vitest/jest が devDependencies にある場合のフォールバック実行可
- build: `build`, `build:check`, `compile`

### Python

`pyproject.toml` の以下を確認：

- `[tool.pytest.ini_options]` または `pytest.ini` がある → `pytest` 実行可
- `[tool.ruff]` または `ruff.toml` がある → `ruff check` 実行可
- `[tool.mypy]` または `mypy.ini` がある → `mypy .` 実行可
- `[tool.pyright]` または `pyrightconfig.json` がある → `pyright` 実行可

実行ラッパー判定：

- `uv.lock` がある → `uv run pytest` のように `uv run` を前置
- `poetry.lock` がある → `poetry run pytest` のように `poetry run` を前置
- いずれもない → `python -m pytest` 等を直接実行

カテゴリ別優先コマンド：

| カテゴリ | コマンド候補 |
|---------|-------------|
| typecheck | `mypy .` / `pyright` |
| lint | `ruff check .` / `flake8` / `pylint` |
| test | `pytest` / `python -m pytest` |
| build | `python -m build` （配布用パッケージのみ） |

### Go

```bash
go vet ./...        # typecheck/lint 兼用
go build ./...      # build
go test ./...       # test
```

モノレポ（`go.work`）では `go work sync` 後、`go test ./...` で全 workspace 対象。変更モジュールに絞る場合は `go test ./path/to/module/...`。

### Rust

```bash
cargo check                   # typecheck
cargo clippy -- -D warnings   # lint
cargo test                    # test
cargo build                   # build
```

モノレポ（workspace）では `cargo test -p <crate>` で対象 crate に絞る。

### Make / Justfile

`Makefile` または `Justfile` を読み、以下のターゲット名を優先順で探す：

- typecheck: `typecheck`, `check-types`, `check`
- lint: `lint`, `check-lint`
- test: `test`, `check`, `tests`
- build: `build`, `compile`

`make <target>` または `just <target>` で実行。

### pre-commit

`.pre-commit-config.yaml` がある場合、変更ファイルに対して：

```bash
pre-commit run --files <file1> <file2> ...
```

これは lint カテゴリの一部として実行。

## 実行ポリシー

### 実行順序

1. **typecheck** — 速い、構文・型エラーを早期検出
2. **lint** — 中速、スタイルや軽微なバグを検出
3. **test** — 遅い、振る舞いを検証
4. **build** — 最も遅い、最終的な成果物の妥当性

各カテゴリで失敗したら **stop-the-line**。後続カテゴリは実行しない。

### タイムアウト

各カテゴリ デフォルト 5 分。超過したら kill して bail-out。プロジェクトが大規模で 5 分が短すぎる場合は、SKILL.md の核心ルールに従いユーザー判断を仰ぐ。

### 対象範囲の絞り込み

- モノレポ: 変更ファイルが属する workspace のみ
- monolith: リポジトリ全体
- テストが極端に遅い場合: 変更ファイルから影響範囲を推定し、関連テストファイルのみ実行（Vitest の `--related`、Jest の `--findRelatedTests`、pytest の `--testmon` 等）

### 失敗時の扱い

失敗したら **自動修正は試みない**。失敗内容を以下の形式でハンドオフプロンプトに含める：

```
カテゴリ: <typecheck|lint|test|build>
コマンド: <実行コマンド>
終了コード: <code>
標準出力（末尾30行）: <output>
標準エラー（末尾30行）: <stderr>
```

### flaky / 環境依存テストの扱い

以下のパターンに該当するテストの失敗は **環境依存の疑い** として扱い、人間判断のため bail-out：

- テスト名やファイル名に `docker`, `db`, `database`, `network`, `e2e`, `integration` を含む
- 過去の CI ログで失敗履歴がある（取得可能な場合のみ）

これらは「コンフリクト解消が原因」とは断定できないため、デグレ防止原則に従い人間に渡す。

## lockfile 再生成と検証の関係

lockfile（`bun.lockb` / `pnpm-lock.yaml` / `yarn.lock` / `package-lock.json` / `Cargo.lock` / `go.sum` / `poetry.lock` / `uv.lock` / `Gemfile.lock` / `composer.lock` / `mix.lock` / `flake.lock`）がコンフリクトしたケースは、本ドキュメントの検証カテゴリではなく `references/lockfile-regeneration.md` の **Auto-Regenerate** フローで処理する：

1. Phase 2 で manifest 側を Auto-OK 解消
2. Phase 2 内で lockfile を `<pm> install` で再生成
3. `<pm> install --frozen-lockfile`（または `npm ci` / `cargo build --locked` / `go mod verify` / `uv sync --frozen` / `pnpm install --frozen-lockfile` 等）で **lockfile が manifest と整合**することを確認
4. その上で本ドキュメントの Phase 3 検証（typecheck → lint → test → build）を通常通り実行

frozen 検証で失敗した場合は、本ドキュメントの「失敗時の扱い」と同じく即 bail-out する。

## 検証コマンドが見つからない場合

検出フローで何も見つからなかった場合は、SKILL.md の Phase 3 の指示通りユーザーに 3 択を提示する：

1. 検証なしで Phase 4 に進む（自己責任）
2. `1natsu-pair-resolve-conflicts` に渡す
3. 検証コマンドを教える

これは **本スキルで唯一ユーザー確認を取る場面**。

## デグレ切り分けのテクニック

検証が失敗した時、原因が「コンフリクト解消の誤り」か「マージ前から壊れていた」かを切り分けたい場合：

1. `git stash` で解消結果を退避
2. `git checkout HEAD~1` で merge 前の片側に戻す（操作種別に応じて適切なリビジョン）
3. 同じ検証コマンドを実行
4. 失敗するなら元から壊れていた可能性がある（その旨を bail-out 理由に含める）

ただし切り分けは時間がかかるため、デフォルトでは **失敗 = 即 bail-out** に倒す。切り分けを試みるのはユーザーが指示した場合のみ。
