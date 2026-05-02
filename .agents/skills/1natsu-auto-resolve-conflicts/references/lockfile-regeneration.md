# Lockfile 再生成ガイド

`1natsu-auto-resolve-conflicts` の Phase 0 / Phase 1 で参照する。**lockfile（および機械的に自動生成される依存解決ファイル）は手動マージしない**のが共通プラクティス。コンフリクト発生時は対応するパッケージマネージャで再生成する。

## なぜ手動マージしないか

lockfile は依存グラフ全体の整合性を表現する機械生成ファイルで、行単位のテキストマージはハッシュ値・依存ツリーの順序・解決済みバージョンの整合性を簡単に壊す。`<<<<<<<` を消して両側を残すと「インストールできるが lockfile が嘘をついている」状態になり、CI で `--frozen-lockfile` 相当のチェックを通らないか、最悪の場合実行時に依存解決の不整合で破綻する。

正しい手順は：
1. **manifest 側のコンフリクトを先に解決**（または manifest が両側で変更されていないことを確認）
2. **lockfile を削除またはコンフリクト状態のまま `<pm> install` を実行**して再生成させる
3. **再生成された lockfile が想定通りか確認**（`--frozen-lockfile` でインストールできるか、あるいは差分が論理的に妥当か）

## 判定の前提条件

lockfile を「Auto-Regenerate」（自動再生成パスで進める）と判定できるのは、以下を**すべて**満たす場合に限る。

- 対応する manifest（後述の対応表）が **両側で変更されていない、または既にコンフリクト解消済み**
- パッケージマネージャ実行環境がリポジトリ内で構築可能（lockfile を信頼できる方法で再生成できる）
- ネットワークアクセスが可能、または既存のキャッシュで再生成が完結する

これらが満たせない場合は **Auto-No 扱いに戻して bail-out**。手動編集は決して試みない。

## 判定の原則（ファイル名ではなく性質で判定する）

このドキュメント末尾の対応表は **2026-05 時点での既知例のスナップショット** に過ぎない。新しいパッケージマネージャや lockfile 形式（例: 既存ツールの新形式、新興言語のツールチェーン）が登場したり、既存ツールが lockfile 形式を変更（例: Bun の `bun.lockb` → `bun.lock`）した場合、対応表は陳腐化する。

そこで一覧と完全一致するファイル名で判定するのではなく、以下の **性質判定** を一次基準にする。

### Auto-Regenerate に分類できる lockfile の性質

未知のファイルでも、以下の要件を満たせば Auto-Regenerate 候補として扱う：

1. **機械生成の見た目**: ハッシュ値・解決済みバージョン・依存ツリーの整列など、人間が手書きしないであろう構造化データ
2. **対応する manifest がリポジトリ内に同居**: 同じ依存を人間可読で宣言しているソース・オブ・トゥルースが特定できる
3. **対応するパッケージマネージャの足跡**: リポジトリ内のドキュメント、CI スクリプト、`scripts/` セクション、Dockerfile、`mise.toml` 等から「どのツールがこのファイルを生成しているか」が判別できる
4. **再生成コマンドが推測可能**: ツール名がわかれば `--help` / 公式 docs から「lockfile 再生成」のためのコマンドが特定できる
5. **frozen / immutable 検証コマンドがある**: 再生成後に「manifest と整合しているか」を確認する非破壊コマンドが提供されている

5 つすべてを満たさない場合は **Auto-No** にエスカレートして bail-out する。

### 未知の lockfile 候補に出会ったときの手順

1. ファイル先頭〜中盤を 50 行ほど読み、機械生成の特徴（ハッシュ、resolved URL、決定論的な順序）を確認
2. リポジトリ内の README / docs / CI / `scripts/` をざっと grep し、該当ファイルを生成・参照しているコマンドを特定
3. ツール名が判明したら `<tool> --help`、公式ドキュメント、docs サイト（context7 など）で **lockfile 再生成 / frozen 検証** のコマンドを確認
4. ドライラン的に再生成コマンドを実行（`--dry-run` フラグがあれば優先）し、影響範囲が想定通りか確認
5. 自信があれば本実行 → frozen 検証
6. ツール特定に失敗、再生成コマンドが推測できない、frozen 検証手段がない、いずれかに該当 → **Auto-No で bail-out**（コミットメッセージに「未知の lockfile 形式」と理由を残す）

### 対応表との関係

下記の対応表は典型例として **すぐに参照できる近道** を提供するが、対応表に **載っていないファイル = Auto-No** ではない。性質判定でクリアできれば対応表外でも Auto-Regenerate として扱える。逆に対応表に載っていても上記性質を満たさない状況（ツールが利用不可、ネットワーク不能など）なら Auto-No に降格する。

## エコシステム × パッケージマネージャ別の対応表

| Lockfile | 対応 manifest | 再生成コマンド | frozen 検証 |
|----------|--------------|---------------|------------|
| `bun.lock`（テキスト形式、Bun v1.2 以降の既定）<br>`bun.lockb`（バイナリ形式、v1.1 以前の既定 / 移行前プロジェクト） | `package.json` | `bun install` | `bun install --frozen-lockfile` |
| `pnpm-lock.yaml` | `package.json`（`packageManager` フィールドや `pnpm-workspace.yaml`） | `pnpm install` | `pnpm install --frozen-lockfile` |
| `yarn.lock` (v1) | `package.json` | `yarn install` | `yarn install --frozen-lockfile` |
| `yarn.lock` (berry / v2+) | `package.json`, `.yarnrc.yml` | `yarn install` | `yarn install --immutable` |
| `package-lock.json` | `package.json` | `npm install`（または `npm install --package-lock-only` で node_modules を作らず lockfile のみ更新） | `npm ci`（node_modules を作る完全インストール） / または `npm install --package-lock-only` を再実行して **diff なし** を確認（lockfile-manifest 整合性のみのチェック、オフライン/CI 制約環境向け） |
| `Cargo.lock` | `Cargo.toml`（必要なら workspace 全体） | `cargo generate-lockfile`（最小） / `cargo update --workspace`（依存も最新化） | `cargo build --locked` |
| `go.sum` | `go.mod` | `go mod tidy` | `go mod verify` + `go build` |
| `poetry.lock` | `pyproject.toml` | `poetry lock --no-update`（依存範囲を変えずに lockfile のみ再生成） | `poetry install --no-root --sync`（CI では `--no-update` 後の差分なし確認） |
| `uv.lock` | `pyproject.toml` | `uv lock` | `uv sync --frozen` |
| `Pipfile.lock` | `Pipfile` | `pipenv lock` | `pipenv install --deploy --ignore-pipfile` |
| `Gemfile.lock` | `Gemfile` | `bundle install` | `bundle install --frozen` |
| `composer.lock` | `composer.json` | `composer update --lock` | `composer install` |
| `mix.lock` (Elixir) | `mix.exs` | `mix deps.get` | `mix deps.get --check-locked` |
| `flake.lock` (Nix flakes) | `flake.nix` | `nix flake lock` | `nix flake check` |

**注**: 上記は 2026-05 時点で頻出するもの。エコシステムは進化するため、ファイル名が一致しなくても **性質判定**（前節）で Auto-Regenerate として扱える場合がある。逆にツール側のメジャー変更（例: Bun が将来 `bun.lockb` を完全廃止する、Cargo workspace の lockfile 仕様変更）が起きた場合、コマンドや検証手段が表と乖離する可能性があるので、迷ったら一次情報（公式 docs）に当たる。

「機械生成・直接編集非推奨」のその他のファイル（参考）:

- 各種 IDE / linter / formatter の自動生成設定（`.eslintcache`, `.tsbuildinfo` など）→ 通常 `.gitignore` 対象。コミット下にあれば「生成物」として Auto-No 寄り
- protobuf 等の自動生成コード（`*_pb2.py`, `*.pb.go`）→ ソース `.proto` を解消後に再生成
- 自動生成 GraphQL スキーマ / OpenAPI クライアント → 同上、ソース定義から再生成
- スナップショット（`__snapshots__/`, `*.snap`, `*.golden`）→ Auto-No（`bailout-rules.md` 既存ルール）

## 再生成フローの詳細

### Step 1: manifest の状態確認

```bash
# 例: JS/TS の場合
git diff --diff-filter=U --name-only | grep -E '^(package\.json|.*/package\.json)$'
git status --porcelain package.json
```

manifest が両側で変更されている場合：
- `dependencies` / `devDependencies` / `peerDependencies` のセクションに両側変更が入っているか確認
- 両側が同一ライブラリの異なるバージョンを指定 → Auto-No（破壊的変更の可能性、人間判断）
- 両側がそれぞれ別ライブラリを追加（独立追加） → Auto-OK（manifest を統合してから lockfile 再生成）
- 片側のみが manifest 変更、他方は lockfile のみ（不整合の典型） → manifest を採用したうえで lockfile 再生成

### Step 2: lockfile の安全な再生成

manifest が決定したら：

```bash
# 例: pnpm の場合
rm -f pnpm-lock.yaml         # 一旦削除（コンフリクトマーカー入りでも install で再生成されるが、削除した方が確実）
pnpm install                  # 新しい lockfile を生成
```

### Step 3: frozen 検証

```bash
# 再生成した lockfile が manifest と整合しているか確認
pnpm install --frozen-lockfile
# Exit code 0 なら整合。非ゼロなら何かおかしい → bail-out
```

### Step 4: 監査ログ

`Phase 4` のコミットメッセージで、lockfile を再生成した旨を必ず記録する。例:

```text
Merge branch 'feature/a' into feature/b

Resolved conflicts in:
- package.json — integrated: 両側で別ライブラリを追加、両方の dependencies を統合
- pnpm-lock.yaml — regenerated via `pnpm install` (frozen-lockfile verified)

auto-resolved by 1natsu-auto-resolve-conflicts
```

## 判定フローのまとめ

```
コンフリクトに lockfile が含まれる
  ├── 対応 manifest が両側変更で Auto-No（同ライブラリの異バージョン等）
  │      → 全体 bail-out
  ├── 対応 manifest が両側変更だが Auto-OK（独立追加の統合等）
  │      → manifest を Auto-OK 解消 → lockfile を再生成 → frozen 検証
  ├── 対応 manifest は片側のみ変更 / 変更なし
  │      → 該当 manifest を採用 / そのまま → lockfile を再生成 → frozen 検証
  └── 対応するパッケージマネージャが実行できない / ネットワーク不可
         → Auto-No 扱いで bail-out

frozen 検証に失敗 → bail-out
frozen 検証に成功 → 通常の Phase 3 検証へ進む（typecheck / lint / test など）
```

## モノレポでの注意

- pnpm workspaces / yarn workspaces / npm workspaces / Cargo workspace / Go workspaces (`go.work`) では **ルートの lockfile のみがコミットされる**のが普通。子パッケージで lockfile が衝突して見えるなら、まずその lockfile が本当にコミット対象か確認する
- ルート lockfile を再生成する際は **すべての workspace の manifest を信頼できる状態にしてから** 実行する（一部 workspace に未解消コンフリクトが残ったまま install すると lockfile に整合しない状態が記録される）

## ネットワークアクセスがない / オフライン環境 / サンドボックス環境

- pnpm / yarn / bun の **store / cache が既に依存を持っている場合** はオフラインでも再生成可能（`pnpm install --offline` 等）
- なければ Auto-No 扱いで bail-out。「再生成しようとしたがネットワーク不可で失敗」を bail-out 理由として明示する

### npm のキャッシュパスが書き込めない場合

サンドボックス・CI 等で `~/.npm`（既定キャッシュ）が EPERM になる場合、`--cache <writable-path>` でリダイレクトすることで突破できる。例:

```bash
npm install --package-lock-only --cache /tmp/claude/npm-cache-<unique>
```

`<writable-path>` は当該環境で書き込み可能で、可能なら一意性のあるパスを選ぶ（同時実行・キャッシュ競合の回避）。

### node_modules インストール不要なケース

lockfile-manifest の **整合性チェックだけ** が目的なら、`npm ci` は重い（node_modules を完全に再構築する）。`npm install --package-lock-only` を 2 回走らせて **diff が出ないこと** を確認すれば、frozen 等価のチェックとして機能する。CI 等で node_modules が不要かつ高速性が欲しいときに有効。

## 失敗時の扱い

`<pm> install` がエラーで終了した場合：

- Exit code と stderr 末尾 30 行を bail-out 理由に含める
- ロールバックは強制しない（lockfile は元に戻すか、空のまま pair に渡すかをユーザー判断）
- handoff プロンプトには「lockfile の再生成に失敗。pair で manifest 側の整合性確認 → 再生成リトライまたはバージョン固定方針を相談してほしい」を含める
