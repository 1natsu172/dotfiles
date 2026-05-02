# bail-out 判定ルール

`1natsu-auto-resolve-conflicts` の Phase 0 / Phase 1 / Phase 2 で参照する判定基準と、その具体的な検出手段。

判定は **Auto-No（即 bail-out）→ Auto-Risky（複数該当で bail-out）→ Auto-Regenerate（自動再生成）→ Auto-OK（自動解消）** の優先順位で適用する。1つでも Auto-No に該当すれば、他に Auto-OK / Auto-Regenerate の特徴があっても bail-out が優先する。

## Auto-No: 1つでも該当したら bail-out 確定

### 1. 公開 API / 関数シグネチャの片側変更と呼び出し側の不整合

**条件**: ours または theirs のどちらかが関数のシグネチャ（引数・戻り値・例外型）を変更しており、もう片方の変更がその新シグネチャに追従していない。

**検出**:
- ours の diff から変更された関数の signature を抽出（言語ごとに `function`, `def`, `func`, `fn`, `interface` 等で grep）
- theirs の diff で同関数を呼び出している箇所を検索
- 呼び出し側が新シグネチャと一致しているか目視確認

**判断**: 一方を採用するともう一方の実装が壊れる典型例。デグレ確実。

### 2. 同関数の本体を両側で異なる方向に書き換え

**条件**: 同じ関数・メソッドの実装本体を ours/theirs が論理的に矛盾する方向に変更している（例: 一方は同期処理に簡略化、他方は非同期化）。

**検出**:
- 同じ関数定義の両側の diff を比較
- 単純な追記・削除ではなく、ロジック分岐の変更が両側にある場合

**判断**: 統合は実質的にビジネス判断であり、AI が独断する範疇を超える。

### 3. security-critical なファイル

**条件**: パスやファイル名に以下のキーワードを含むファイルが両側で変更されている：

- `auth`, `authn`, `authz`, `oauth`, `jwt`, `session`
- `crypto`, `cipher`, `hash`, `password`
- `secret`, `credential`, `token`, `apikey`, `api_key`
- `rbac`, `iam`, `permission`, `role`
- `.env`, `.env.*`, `secrets/`, `vault/`
- `cors`, `csrf`, `csp`

**検出**: `git diff --name-only --diff-filter=U` の結果に上記キーワードを含むパスがないか grep。

**判断**: セキュリティ系の競合は人間の最終判断が必須。誤った自動解消は本番事故に直結する。

### 4. DB マイグレーション系

**条件**: 以下のディレクトリ配下のファイルが両側で変更されている：

- `migrations/`, `db/migrations/`, `prisma/migrations/`
- `alembic/versions/`
- `schema.rb`, `schema.prisma`, `schema.sql`
- `db/migrate/` (Rails)
- `*.sql` でファイル名に日付プレフィックスがあるもの

**判断**: マイグレーションの実行順序や副作用は静的に判定不能。両側でスキーマを変えていれば、適用順序で結果が変わる。

### 5. 依存関係 manifest の両側変更（lockfile は別カテゴリ）

**対象（manifest 側のみ）**: 以下のファイルが両側でコンフリクトしているケース。

- JS/TS: `package.json` の `dependencies` / `devDependencies` / `peerDependencies`
- Python: `pyproject.toml` の `[project] dependencies` / `[tool.poetry] dependencies`、`requirements*.txt`、`Pipfile`
- Rust: `Cargo.toml` の `[dependencies]` / `[dev-dependencies]`
- Go: `go.mod`
- Ruby: `Gemfile`
- PHP: `composer.json`
- Elixir: `mix.exs`

**条件**:

- 同一ライブラリの異なるバージョンを両側が指定している
- 同一ライブラリを片側が削除し、他方が更新・利用追加している
- 同一セクション（`dependencies` / `devDependencies` 等）の重複領域に両側変更がある

**検出**: `git diff` のハンクが上記 manifest の依存セクションに掛かっているか。

**判断**: バージョン解決方針（互換性維持 / アップグレード / 削除）はビジネス判断を伴うため AI 単独で決められない。

**例外（Auto-OK 寄りの典型）**: 両側がそれぞれ**独立した別ライブラリ**を追加しただけで、依存セクション内のハンクが純粋な行追加 → これは `Auto-OK` に分類して manifest を統合する。lockfile も対応して `Auto-Regenerate` で再生成。

**注意**: lockfile（`*.lock*`, `*-lock.*`, `package-lock.json`, `Cargo.lock`, `go.sum` 等）の両側変更は **本ルールに含めない**。lockfile は後述の **Auto-Regenerate** カテゴリで扱い、再生成パスを通す。

### 6. 生成物・バイナリ・大きなファイルの両側変更

**条件**:

- ビルド成果物: `dist/`, `build/`, `out/`, `target/`, `.next/`, `coverage/`
- 生成スナップショット: `*.snap`, `__snapshots__/`, `*.golden`
- バイナリ: `*.png`, `*.jpg`, `*.pdf`, `*.zip`, `*.tar.gz`, `*.so`, `*.dll`, `*.dylib`, `*.exe`
- ファイルサイズが 1MB 超

**検出**: パス名のパターンマッチ + `git diff --stat` でサイズ確認。

**判断**: 機械生成物は手動マージの対象外。元のソースを直して再生成すべき。

### 7. submodule の競合

**条件**: `Subproject commit` 行が両側で異なる commit を指している。

**検出**: コンフリクトしているファイルの内容に `<<<<<<< HEAD` の直後に `Subproject commit` が現れる。

**判断**: submodule の commit 選択は親リポジトリの意図に依存し、片側採用の安全性を検証する手段がない。

### 8. 「deleted by us / by them」と「modified」の組み合わせ

**条件**: `git status` で以下が混在：

- `deleted by us:` / `deleted by them:` / `both deleted:`
- 同時に他のファイルで `both modified:`

**検出**: `git status --porcelain=v2` の `u` レコードを解析。

**判断**: 「消すか残すか」はリファクタや機能廃止の意図を伴い、観測事実だけでは判定不能。

### 9. 規模超過

**条件**:

- コンフリクトファイル数 ≥ 10
- 1ファイル内のコンフリクトハンク数 ≥ 8（`git diff --check` または `<<<<<<<` の出現回数で計測）

**判断**: 規模が大きいほど見落としリスクが累積する。デグレ確率を下げるには人間の確認が必須。

### 10. 作業ツリーが他要因で汚染

**条件**: コンフリクト以外に未追跡（untracked）または未ステージ（modified, not staged）の変更がある。

**検出**: `git status --porcelain` で `??`（untracked）や `M `, ` M`（unstaged modified）が、コンフリクト解消対象ファイル以外に存在。

**判断**: 解消結果と既存変更の責任分離が困難。clean な状態でやり直す方が安全。

### 11. 履歴から両側の意図が読み取れない

**条件**: `git log --oneline` で両側のコミットメッセージを確認したとき、以下のいずれか：

- メッセージが空
- `WIP`, `wip`, `tmp`, `temp`, `fix`, `update`, `change` 等の単一動詞のみ
- マシン生成（`Merge branch ...`, `Update X.Y.Z` の自動 PR）のみ

**検出**: コミットメッセージの先頭行を正規表現でフィルタ。

**判断**: 意図不明の変更を統合すると、原作者の意図と異なる結果になりうる。

### 12. 局所構文チェックに失敗

**条件**: Phase 2 Step 5 の局所検証（言語別の構文チェック）が失敗。

**検出**: 適用後のファイルに対して `tsc --noEmit <file>` / `python -m py_compile <file>` / `go vet <pkg>` / `cargo check -p <pkg>` を実行し、終了コード非ゼロ。

**判断**: 構文すら通らない解消は明らかに誤り。bail-out 一択。

## Auto-Regenerate: パッケージマネージャで再生成

機械的に自動生成されるファイル（lockfile 等）は **手動マージしない**。直接編集はベストプラクティスに反し、依存解決の整合性を壊す典型例。代わりに対応するパッケージマネージャで再生成する。

詳細な再生成手順・コマンド・対応 manifest の対応表は `references/lockfile-regeneration.md` を参照。

### 該当ファイル（典型例、2026-05 時点）

- JS/TS: `bun.lock`（v1.2+）/ `bun.lockb`（legacy）, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`
- Python: `poetry.lock`, `uv.lock`, `Pipfile.lock`
- Rust: `Cargo.lock`
- Go: `go.sum`
- Ruby: `Gemfile.lock`
- PHP: `composer.lock`
- Elixir: `mix.lock`
- Nix: `flake.lock`

**注**: 上記は更新時点で頻出する例。**ファイル名一覧で判定するのではなく**、`references/lockfile-regeneration.md` の「判定の原則（ファイル名ではなく性質で判定する）」セクションに従い、機械生成性 + 対応 manifest + 対応ツール + 再生成・frozen 検証手段の有無 という **性質判定** を一次基準にする。新ツール（pixi, rye, 新興言語ツールチェーン等）や既存ツールの新形式（例: Bun の `bun.lockb` → `bun.lock` への移行）にも、性質を満たせば対応できる。性質が判定できなければ Auto-No にエスカレートして bail-out する。

### 再生成パスを通せる前提条件

以下を**すべて**満たすときに `Auto-Regenerate` で進める。1つでも欠ければ `Auto-No` にエスカレートして bail-out する。

- 対応 manifest（`package.json` / `Cargo.toml` 等）が両側変更で **Auto-No に該当しない**（変更なし、片側のみ変更、または両側変更でも Auto-OK 判定が可能）
- パッケージマネージャ実行環境が整っている（`<pm> install` が動かせる）
- ネットワーク（または既存キャッシュ）で依存解決が完結する

### 再生成後の検証

`<pm> install --frozen-lockfile`（または等価の immutable / locked 検証コマンド）で **再生成された lockfile が manifest と整合**することを確認してから Phase 4 に進む。検証失敗なら bail-out。

### 自動生成系のその他の対象

直接編集すべきでない自動生成物（コード生成 / プロトコル / スナップショット等）は引き続き `Auto-No` 扱い。再生成スクリプトがリポジトリ内に明示的に存在し、実行コストが現実的な場合のみ `Auto-Regenerate` 拡張対象として個別判断する。

## Auto-Risky: 複数該当で bail-out

以下のいずれかに該当する場合は慎重に進める。**2つ以上該当したら bail-out** に倒す。

### 1. 1ファイル内ハンク数 ≥ 4

**検出**: コンフリクトファイル内の `<<<<<<<` 出現回数。

**判断**: ハンクが多いほど統合判断のミスが累積する。

### 2. 同一行近傍の両側変更

**条件**: ours と theirs のハンクが互いに 5 行以内で隣接している。

**検出**: `git diff --check` で「<<<<<<<」と「=======」の行間隔を計測。

**判断**: 隣接ハンクは統合時に改行・スコープを誤りやすい。

### 3. テストファイルの競合

**条件**: パスに `test/`, `tests/`, `__tests__/`, `spec/`, `.test.`, `.spec.`, `_test.go`, `_spec.rb` を含む。

**検出**: パスのパターンマッチ。

**判断**: テストの片側採用は「テストは通るが要件を満たしていない」状態を生みやすい。

### 4. 公開エクスポート定義ファイル

**条件**: `index.ts`, `index.js`, `mod.rs`, `__init__.py`, `lib.rs`, `main.go` の競合。

**検出**: ファイル名のパターンマッチ。

**判断**: エクスポートの増減は API の変化と等価。慎重判断が必要。

### 5. CI/CD 設定ファイル

**条件**: `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, `Dockerfile`, `docker-compose*.yml`, `kubernetes/`, `helm/` 等の両側変更。

**判断**: CI/CD の挙動変更はリリースに直結。慎重判断が必要。

## Auto-OK: 自動解消の典型

以下のパターンは安全に自動解消できる典型例。Phase 1 のトリアージで Auto-OK と判定したら、Phase 2 の各ステップを通常通り進める。

### 1. import / use 文のみの競合

**条件**: コンフリクトハンクの内容が `import`, `from ... import`, `use`, `require`, `#include` のみ。本体ロジックの変更を含まない。

**解消方針**: 両側の import を統合し、言語慣習に従って整列（アルファベット順 / 標準ライブラリ優先）。

### 2. 機械的な改名・lint 由来のフォーマット差分

**条件**: 一方の変更が変数名のリネームやフォーマッタ由来（インデント、引用符、セミコロン）のみ。

**判断**: フォーマッタを正とする側を採用。

### 3. 一方が意味的変更、他方が空白/コメント変更

**条件**: ours または theirs のどちらかが空白・コメントのみで、もう一方が実コードを変更。

**解消方針**: 実コード側を採用。

### 4. README / docs / CHANGELOG の追記同士

**条件**: ドキュメントファイル（`*.md`, `docs/`）で両側がそれぞれ別セクションを追記し、隣接行で衝突。

**解消方針**: 順序を保ちながら統合（時系列、見出しレベル、アルファベット順のいずれか文書の慣習に合わせる）。

### 5. 設定ファイルで両側が別キーを追加

**条件**: JSON / YAML / TOML 設定ファイルで、ours と theirs がそれぞれ独立したキーを追加し、隣接行で衝突。

**解消方針**: 両側のキーを統合。同じキーに異なる値を設定している場合は Auto-No 扱い。

## 判定優先順位

複数のルールに該当する場合、以下の優先順位で適用する：

1. Auto-No のいずれかに該当 → 即 bail-out（他のルールは見ない）
2. Auto-Risky に 2 つ以上該当 → bail-out
3. Auto-Risky に 1 つだけ該当 → Auto-OK / Auto-Regenerate パターンに合致するか再確認
4. Auto-Regenerate に該当 + 前提条件を満たす → パッケージマネージャで再生成 → frozen 検証
5. Auto-OK に該当 → 自動解消

迷ったら一段安全側（より bail-out 寄り）に倒すこと。
