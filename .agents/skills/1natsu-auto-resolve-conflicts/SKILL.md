---
name: 1natsu-auto-resolve-conflicts
description: Gitのコンフリクト解消をAI単独で完全自動化する自走スキル。merge / rebase / cherry-pick / stash pop で衝突した時、コミット履歴と変更意図を読み取って解消し、検証コマンドを自動検出して実行し、コミット/--continue まで一気に完了させる。ユーザーが「自動でコンフリクト解消」「コンフリクト解消お任せ」「auto resolve conflicts」「コミット/--continue まで自動」等、AI 主導の自動化・自走を示唆する発話で使用する。AIがコンフリクト検知時にユーザーが自動化を示唆した場合も本スキルへ移行する。デグレ防止が最優先のため、安全に解消できないと判断したら途中で `1natsu-pair-resolve-conflicts` へ引き継ぐ。**人間と一緒に1ファイルずつ承認しながら解消したい場合は本スキルではなく `1natsu-pair-resolve-conflicts` を使うこと。**
license: MIT
metadata:
  author: 1natsu
  version: "1.1.3"
---

# Auto Resolve Conflicts（自動コンフリクト解消）

コミット履歴・diff・検証結果という観測事実だけを根拠に、コンフリクトを **解消 → 検証 → ステージング → コミット/--continue** までAI単独で完了させる自走モード。

姉妹スキル `1natsu-pair-resolve-conflicts`（人間と1ハンクずつ承認を取りながら解消する協調モード）と対をなす。本スキルは「AIが責任を持って一気にやり切る」が役割で、安全に判断できない場面では潔く pair モードへ引き渡す。

## 役割分担

- **本スキル**: 解消方針の決定・適用・検証・コミット/--continue の実行までAIが担当する。**人間に承認は求めない**（検証コマンドが見つからない場合の例外を除く）
- **bail-out**: デグレ懸念があると判定したら、安全に解消できた部分はそのまま残し、未着手分を `1natsu-pair-resolve-conflicts` に引き継ぐ

## 対話ルール

基本は出力のみで進める。ユーザーへの確認はデグレに直結する場面（bail-out への移行、検証コマンドが見つからない場合）に限定する。確認が必要な時はプラットフォームが提供する対話型の選択UIを使う。

## モードの開始

### ユーザーからの明示的な起動

以下のようなフレーズで要求された場合、即座にモードに入る：

- 「自動でコンフリクト解消して」「コンフリクト解消お任せ」「auto resolve」
- 「黙って解消して」「コミットまで自動でやって」「--continue まで一気に」「自走で解消」

### AIからの提案

コンフリクト状態を検知し、かつユーザーが「自動で」「お任せ」「自走」を示唆した場合は本スキルへの移行を**提案する**（勝手に入らない）。明確な意思表示がなければ、まず `1natsu-pair-resolve-conflicts` か本スキルかをユーザーに 1 回確認する。

提案の例：

> コンフリクトが発生しています。自動モードで解消からコミットまでやり切りますか？デグレ懸念があれば途中で pair モードに切り替えます。

### 起動直後の宣言

モードに入ったら、必ず以下を1メッセージで宣言する：

- 自動モードで進めること
- 解消・検証・コミット/--continue まで自走すること
- デグレ懸念がある場面では `1natsu-pair-resolve-conflicts` に切り替えること

## Phase 0: 状況把握と早期 bail-out チェック

### 状況把握

```bash
# 現在の操作種別（merge / rebase / cherry-pick / stash pop）
git status

# rerere の状態
git config rerere.enabled
git rerere status  # 有効な場合
```

rerere が有効で自動解消が適用されている場合は、その内容を診断対象に含める。rerere が怪しい挙動をしているなら `git rerere forget <file>` での取り消しを検討する。rerere が無効でも有効化を提案しない（ユーザー判断領域）。

### 早期 bail-out チェック

以下のいずれかに該当したら、Phase 1 に入る前に即 bail-out する：

- 巨大バイナリ・生成物・スナップショットの両側変更（`dist/`, `build/`, `*.png`, `*.pdf`, `*.snap`）
- submodule の競合（`Subproject commit` 行の両側変更）
- DB マイグレーション系（`migrations/`, `prisma/migrations/`, `alembic/versions/`）
- 依存関係 **manifest** の両側変更で Auto-No 判定（同ライブラリの異バージョン指定、片側削除と片側更新の競合 等）。`package.json` の `dependencies` セクション、`Cargo.toml [dependencies]`、`pyproject.toml`、`go.mod`、`Gemfile` 等
- security-critical（`auth`, `crypto`, `secrets`, `RBAC`, `IAM`, `.env*` 名前を含む）
- 「deleted by us / by them」と「modified」の組み合わせ
- 作業ツリーがコンフリクト解消対象以外で汚染（`git status` で untracked / unstaged の他要因変更がある）

**lockfile（パッケージマネージャが生成する依存解決ファイル全般）の両側変更は早期 bail-out にしない**。代表例として `bun.lock` / `bun.lockb` / `pnpm-lock.yaml` / `yarn.lock` / `package-lock.json` / `Cargo.lock` / `go.sum` / `poetry.lock` / `uv.lock` / `Gemfile.lock` / `composer.lock` / `mix.lock` / `flake.lock` 等があるが、**ファイル名一覧で判定するのではなく**「機械生成・対応 manifest あり・対応するパッケージマネージャあり・再生成コマンドと frozen 検証手段が揃う」という **性質** で Auto-Regenerate に該当するか判定する。lockfile はテキストマージで整合性を壊しやすく、対応するパッケージマネージャで再生成するのがベストプラクティス。詳細な判定原則と対応表は `references/lockfile-regeneration.md` を参照。

詳細な判定基準と検出方法は `references/bailout-rules.md` を参照する。

## Phase 1: 全体俯瞰とトリアージ

### コンフリクト全体の把握

```bash
# コンフリクトファイル一覧
git diff --name-only --diff-filter=U

# 操作種別ごとの両側コミット履歴
# merge:
git log --oneline HEAD...MERGE_HEAD -- <files>
# rebase:
git log --oneline REBASE_HEAD~1..REBASE_HEAD -- <files>
# cherry-pick:
git log --oneline CHERRY_PICK_HEAD -- <files>
```

### Auto-OK / Auto-Risky / Auto-Regenerate / Auto-No 分類

ファイルごと（必要に応じてハンクごと）に以下の4段階で分類する：

- **Auto-OK** — import文だけの競合、機械的な改名、両側追記の順序統合、設定ファイルの別キー追加など、明らかに安全に自動解消できるもの
- **Auto-Regenerate** — lockfile 等の機械生成依存解決ファイル。対応 manifest が安全に解決できるなら、対応するパッケージマネージャ（`bun install` / `pnpm install` / `cargo generate-lockfile` / `go mod tidy` / `poetry lock --no-update` / `uv lock` など、エコシステムごとの再生成コマンド）で **再生成** する。手動マージは絶対にしない。**ファイル名一覧で判定するのではなく**、機械生成性 + 対応 manifest の存在 + 再生成コマンドと frozen 検証の有無 という性質で判定するため、対応表外の未知 lockfile も性質を満たせば対象に含める。`references/lockfile-regeneration.md` 参照
- **Auto-Risky** — 1ファイル内ハンク数 ≥ 4、同一行近傍の両側変更、テストファイル、公開エクスポート定義ファイルなど、慎重判断が必要なもの。複数該当で bail-out
- **Auto-No** — 関数シグネチャ変更と呼び出し側の不整合、両側で同関数の本体を異なる方向に書き換え、依存 manifest の同ライブラリ異バージョン競合など。1つでも該当したら全体 bail-out

詳細な判定基準と具体的な検出コマンドは `references/bailout-rules.md` を参照する。

### トリアージ結果の宣言

分類が終わったら、1メッセージで以下を提示する：

- ファイル数 N 件のうち、Auto-OK が M 件、Auto-Regenerate が G 件、Auto-Risky が R 件、Auto-No が K 件
- 取り得る進路（全自動 / 再生成併用 / 混合 bail-out / 全体 bail-out）の判定結果と理由
- 自動解消対象・再生成対象・bail-out 対象ファイルの一覧

Auto-No が 1 件でもある場合は **全体 bail-out** が原則。ただし Auto-OK / Auto-Regenerate と独立に解消できることが明確な場合（同じファイルではない、依存関係がない）は、安全な部分だけ適用する **混合 bail-out** を選んでもよい。デグレ懸念が拭えなければ全体 bail-out を選ぶ。

## Phase 2: 自動解消ループ

各ファイルを **直列**（並列にしない）で処理する。並列化は依存関係の見落としを生み、デグレ防止原則に反する。

**処理順序の推奨**: 同じ Phase 2 ループ内では、**Auto-OK の manifest を先に解消 → Auto-Regenerate を実行 → 残りの Auto-OK を解消** の順で進めると、lockfile の再生成が最新の manifest を反映でき、整合性が高まる。

### Auto-OK ファイルごとの処理ステップ

各ファイルに対して以下のサイクルを回す：

1. **履歴調査** — `git log -p HEAD -- <file>` と `git log -p MERGE_HEAD -- <file>`（操作種別に応じてリビジョン名を変える）で両側の変更履歴を読み、コミットメッセージと周辺コードから変更意図を抽出する
2. **意図推定** — 各ハンクについて「ours は何をしたかったか」「theirs は何をしたかったか」を1行ずつ言語化する。意図が読み取れないハンクは **Auto-No に再分類** して bail-out
3. **解消方針決定** — 「ours採用 / theirs採用 / 統合 / 一方を基準に他方の意図を移植」のいずれかを選ぶ。判断根拠は意図推定の結果のみ
4. **解消適用** — コンフリクトマーカーを除去して解消後のコードを書き込む。**この時点では `git add` しない**
5. **局所検証** — 解消したファイルの構文を軽く確認する（言語に応じて `tsc --noEmit <file>`、`python -m py_compile <file>`、`go vet <pkg>`、`cargo check -p <pkg>` 等）。失敗したら **即 bail-out**
6. **進捗ログ** — `<file>: ours採用 / 統合 / theirs採用 — <一行根拠>` の形式で1行サマリを出力

### Auto-Regenerate ファイルの処理ステップ

lockfile 等は手動マージしない。詳細手順と対応表は `references/lockfile-regeneration.md` を参照。要点のみ：

1. **性質の確認** — 機械生成 / 対応 manifest あり / 対応ツールあり / 再生成・frozen 検証の手段あり、を満たすか確認。満たさなければ Auto-No に降格して bail-out
2. **対応 manifest の確認** — 該当 lockfile に紐づく manifest（`package.json` / `Cargo.toml` / `pyproject.toml` 等）が決定済みか確認。未解消なら先に Auto-OK ループで解消
3. **lockfile を一度削除（または競合状態のまま）** — `rm <lockfile>` でクリーンに再生成する方が確実
4. **再生成コマンド実行** — エコシステムに応じた再生成コマンド（lockfile-regeneration.md 対応表参照、未知ファイルは公式 docs / `--help` で確認）
5. **frozen 検証** — エコシステム標準の immutable / frozen / locked 検証コマンドで manifest との整合を確認。失敗したら **bail-out**
6. **進捗ログ** — `<lockfile>: regenerated via <command> (<frozen-verification> verified)` の形式で出力

### ループ中の bail-out

- 局所検証が失敗
- 履歴を読んでも意図が判明しない
- 当初 Auto-OK と判定したが、適用過程で Auto-No 相当の問題（呼び出し側の不整合等）が発覚

これらが起きたら **そのファイルを未解消のまま** 残し、混合 bail-out に切り替える。それまでに適用した他ファイルはそのまま残す。

## Phase 3: 検証コマンドの自動検出と実行

### 検出フロー

1. リポジトリ直下のマーカーファイルを列挙（`package.json`, lockfile 各種, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`, `Justfile`, `.pre-commit-config.yaml`）
2. モノレポ判定（`pnpm-workspace.yaml`, `turbo.json`, `nx.json`, ルート `package.json` の `workspaces`）
3. パッケージマネージャ判定（lockfile 優先順位: `bun.lockb` > `pnpm-lock.yaml` > `yarn.lock` > `package-lock.json`）
4. 検証カテゴリ（typecheck / lint / test / build）のコマンドを抽出

詳細は `references/verification-detection.md` を参照する。言語別の優先コマンド表とフォールバックを記載している。

### 実行ポリシー

- **順序**: typecheck → lint → test → build（速いものから、失敗で stop-the-line）
- **タイムアウト**: 各カテゴリ デフォルト 5 分。超過したら bail-out
- **対象範囲**: モノレポでは変更ファイルが属する workspace に限定
- **失敗時**: 自動修正は試みず、失敗ログを添えて即 bail-out
- **flaky 疑い**: 過去実行で失敗履歴のあるテスト名や、`docker` / `db` / `network` を含むテスト名は環境依存の疑いがあるため、失敗時は人間判断のため bail-out

### 検証コマンドが見つからない場合

検出に失敗した場合は **唯一の例外** としてユーザーに 3 択を提示する：

1. 検証なしで Phase 4 に進む（自己責任）
2. `1natsu-pair-resolve-conflicts` に渡す
3. 検証コマンドを教える（受け取って実行）

それ以外の場面ではユーザー確認を取らない。

## Phase 4: ステージング・コミット / --continue

### ステージング

解消済みファイルのみを `git add` する：

```bash
git add <resolved-file-1> <resolved-file-2> ...
```

未解消のファイル（混合 bail-out 時）はステージングしない。

### 操作種別ごとの完了処理

- **merge** — `git commit`。コミットメッセージは Git の自動生成テンプレートに、解消の要約と本スキルのフットプリントを追加（`references/commit-message-template.md` 参照）
- **rebase** — `git rebase --continue`。Git が次のコンフリクトで止まった場合、Phase 0 から再帰的に処理する
- **cherry-pick** — `git cherry-pick --continue`
- **stash pop** — ステージングのみ実施。stash の性質上 commit はしない

### 完了報告

3 点をまとめて出力する：

1. **解消サマリ** — 各ファイルでどう解消したかの一行リスト
2. **検証結果** — 実行した検証コマンドと結果（pass/fail/skip）
3. **完了アクション** — 何のコマンドで完了したか（commit hash や rebase 状態）

## bail-out プロトコル

### 動作

bail-out が発動したら：

1. **既に適用済みのファイルはワーキングツリーに残す**（git add 済みかどうかは適用時点での状態を維持する）
2. **未解消ファイルと bail-out 理由を構造化して出力**
3. **`1natsu-pair-resolve-conflicts` への引き継ぎプロンプトを生成**

引き継ぎプロンプトのテンプレートは `references/handoff-to-pair-resolve.md` にある。操作種別 × bail-out 理由のマトリクスで定義しているので、当てはまるテンプレートを使う。

### Phase 4 後の bail-out

検証コマンドが落ちて Phase 3 で bail-out する場合、Phase 2 までの解消は **適用済みでステージング前**。ロールバックは強制せず、ユーザーが `git reset` するか pair で続行するかを選択できるよう、ハンドオフプロンプトに状態説明を含める。

### bail-out は失敗ではない

「安全に判断できなかったので人間に渡す」は本スキルの正しい振る舞い。デグレを起こす自動コミットより、bail-out の方が常に望ましい。

## 核心ルール

- **デグレ防止が最優先** — 速度や完了率より、安全に解消できる確信が持てるかを優先する。迷ったら bail-out
- **観測根拠主義** — コミット履歴・diff・テスト結果という事実のみを判断根拠にする。「たぶん」「おそらく」は bail-out のサイン
- **不確実性の正直な報告** — 確信が持てない判断を「自動解消した」と報告しない。曖昧さは bail-out 理由として明示する
- **自動コミットの責任** — 本スキルが作ったコミットは AI が責任を負う。コミットメッセージにはフットプリント（`references/commit-message-template.md`）を必ず残し、後から監査できるようにする
- **bail-out しても恥じない** — pair モードへの引き渡しは安全運用の一部であり、後退ではない
- **検証なしのコミットはしない** — 唯一の例外は Phase 3 の検証コマンド未検出時のユーザー確認のみ。それ以外で検証をスキップしない
- **rerere は尊重する** — rerere の自動解消は人間が過去に下した判断の蓄積。怪しい場合は `git rerere forget` で取り消す前に観測事実で根拠を示す
- **AI が勝手に rerere を有効化しない** — 設定変更はユーザーの責任領域

## 参考ドキュメント

- `references/bailout-rules.md` — Auto-No/Risky/Regenerate/OK の詳細条件と検出方法
- `references/lockfile-regeneration.md` — lockfile 等の自動再生成フローとパッケージマネージャ別コマンド表
- `references/verification-detection.md` — 言語・パッケージマネージャ別の検証コマンド表
- `references/handoff-to-pair-resolve.md` — bail-out 時の引き継ぎプロンプトテンプレート
- `references/commit-message-template.md` — 自動コミットメッセージの規約とフットプリント

## 関連スキル

- `1natsu-pair-resolve-conflicts` — 人間と1ファイル/1ハンクずつ承認を取りながら解消する協調モード。本スキルが bail-out した時の引き継ぎ先
