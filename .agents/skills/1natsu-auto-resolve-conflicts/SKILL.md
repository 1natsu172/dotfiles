---
name: 1natsu-auto-resolve-conflicts
description: Gitのコンフリクト解消をAI単独で完全自動化する自走スキル。merge / rebase / cherry-pick / stash pop で衝突した時、履歴と変更意図を読み、両側の機能を壊さず統合し、検証を自動実行して --continue まで完了する。すでに衝突している場合に加え、stale な PR（mergeable:false）で未コンフリクトの状態からでも base 追従で衝突を発生させて解消する。merge は解消履歴を追えるよう2段コミットで残す。「自動でコンフリクト解消」「コンフリクト解消お任せ」「auto resolve conflicts」「stale な PR を base 追従して解消」「mergeable false を直して」等、AI主導の自動化・自走を示唆した時に使う。デグレ防止が最優先で、安全に解消できなければ `1natsu-pair-resolve-conflicts` へ引き継ぐ。**1ファイルずつ承認しながら解消したい場合は本スキルでなく `1natsu-pair-resolve-conflicts` を使う。**
license: MIT
metadata:
  author: 1natsu
  version: "1.2.0"
---

# Auto Resolve Conflicts（自動コンフリクト解消）

コミット履歴・diff・検証結果という観測事実だけを根拠に、コンフリクトを **解消 → 検証 → ステージング → コミット/--continue** までAI単独で完了させる自走モード。

姉妹スキル `1natsu-pair-resolve-conflicts`（人間と1ハンクずつ承認を取りながら解消する協調モード）と対をなす。本スキルは「AIが責任を持って一気にやり切る」が役割で、安全に判断できない場面では潔く pair モードへ引き渡す。

## このスキルが言う「解消」の定義

コンフリクトマーカー（`<<<<<<<` / `=======` / `>>>>>>>`）を消すことはゴールではない。**マーカーの除去 + 両側の機能を壊さない整合したコードの統合** が揃って初めて「解消」と呼ぶ。ours と theirs が**それぞれ別の機能を実装している**のに、片側を丸ごと捨ててマーカーだけ消すのは「解消」ではなく**デグレ**である。コミット履歴から「両側が何を実現したかったか」を読み取り、その意図が解消後コードに**両方とも生き残っている**ことを担保する（Point: [相互機能保持]）。

## 起点の2パターン

本スキルは2つの起点から開始できる：

1. **すでにコンフリクト状態** — `git status` に unmerged paths がある（merge/rebase/cherry-pick/stash pop 進行中）。→ Phase 0 から始める。
2. **未コンフリクト状態だが追従が必要** — stale な PR（`mergeable:false`）等で、ローカルはまだ衝突していないが base ブランチに追従するとコンフリクトが起きる。→ **Phase A** で base 追従してコンフリクトを発生させてから Phase 0 に合流する。

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
- 「stale な PR を base 追従して解消して」「mergeable false を直して」「base に追従してコンフリクト直して」（→ 未コンフリクト状態なら Phase A から）
- 「この PR を base にマージできる状態にして」「最新の base に追従して」（目標だけの依頼。未コンフリクトでも base より遅れていれば Phase A から）

### AIからの提案

コンフリクト状態を検知し、かつユーザーが「自動で」「お任せ」「自走」を示唆した場合は本スキルへの移行を**提案する**（勝手に入らない）。明確な意思表示がなければ、まず `1natsu-pair-resolve-conflicts` か本スキルかをユーザーに 1 回確認する。

提案の例：

> コンフリクトが発生しています。自動モードで解消からコミットまでやり切りますか？デグレ懸念があれば途中で pair モードに切り替えます。

### 起動直後の宣言

モードに入ったら、必ず以下を1メッセージで宣言する：

- 自動モードで進めること
- 起点（すでにコンフリクト状態か / Phase A で base 追従して発生させるか）
- 解消・検証・コミット/--continue まで自走すること
- デグレ懸念がある場面では `1natsu-pair-resolve-conflicts` に切り替えること

## Phase A: 追従の起点作り（未コンフリクト状態からの起動時のみ）

`git status` に unmerged paths が**なく**、かつユーザーの意図が **「現在のブランチ/PR を base に統合できる状態にする」** である場合に実行する。すでにコンフリクト状態なら本フェーズは飛ばして Phase 0 へ進む。

**意図の汲み取り（重要）**: ユーザーは必ずしも「base を merge してコンフリクトを発生させて」と機構を指示してこない。次のような **目標・症状** も Phase A のトリガーになる:

- 症状の提示 — 「PR が stale」「GitHub で mergeable=false」「base とコンフリクトしてマージできない」
- 目標の提示 — 「この PR を base にマージできる状態にして」「最新の base に追従して」「base に取り込めるようにして」

「コンフリクトを直して」と言われてローカルに衝突が無い時は、**即「解消対象なし」と結論づけず**、まず「base に対して遅れていて、取り込むと衝突する状態ではないか」を疑う。これが本スキルの期待挙動。ただし、base 統合の意図がまったく読み取れない（単に clean なブランチで作業中など）場合は、勝手に base を merge せず状況を報告するか1回確認する（不用意な merge はしない）。

目的は **base ブランチへの追従でコンフリクトを意図的に発生させ、その後 Phase 0 以降の通常フローに合流する** こと。追従戦略は **base を現在ブランチにマージ**（`git merge origin/<base>`）を既定とする。force-push 不要で PR のレビュー履歴・コメントが剥がれず、Phase 4 の2段コミットとも相性が良い。

### 手順

1. **前提確認** — `git status` で「merge/rebase 等が進行中でない」「ワーキングツリーが clean（未コミット変更がない）」を確認する。汚染があれば Phase 0 の早期 bail-out と同じ理由（責任分離困難）で着手前に bail-out する。
2. **base ブランチ決定** — `gh pr view --json baseRefName,mergeable,mergeStateStatus`（gh があり PR が紐づく場合）→ 上流追跡 `@{upstream}` / リポジトリ default（`git symbolic-ref refs/remotes/origin/HEAD`）→ いずれも不明ならユーザーに1回だけ確認、の順で決める。
3. **乖離の観測（追従が必要かの裏取り）** — base を取得（`git fetch origin <base>`。remote が無ければ省略）した上で、`git log --oneline <base>..HEAD` と `git log --oneline HEAD..<base>` で乖離を見る。**HEAD が base に対して遅れている（base 側に未取り込みのコミットがある）**なら追従が必要と確定する。既に base を含んでいて遅れていないなら「追従不要・統合済み」と報告して終了する（観測事実で判断し、思い込みで merge しない）。
4. **追従の適用** — `git merge origin/<base>`（remote が無ければローカル base を直接 `git merge <base>`）。
   - **コンフリクトなしで完了** — base が綺麗に取り込めた。追従が完了した旨（作成された merge コミット）を報告して終了する。解消対象のコンフリクトは無い。
   - **コンフリクト発生** — 期待どおり。これで起点ができたので **Phase 0 に合流** し、以降は通常の merge コンフリクトとして解消・検証・2段コミットまで進める。

詳細な base 検出ロジック（gh の有無、PR 非紐づけ時のフォールバック、remote が無い場合、rebase 慣習が明確な場合の例外）は `references/stale-pr-follow.md` を参照する。

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

### ループ全体の鉄則: `git add` しない（2段コミットと bail-out の生命線）

Phase 2 全体を通して **`git add` は一切しない**。これにより index には unmerged stages（git が記録した両側＋ベースの3版）がそのまま残る。merge の2段コミットでは、解消後に **`git checkout --merge -- <file>` で index から「マーカー入りの衝突原文」を git に再生成させて**スナップショットコミットを作る（手順は `references/two-stage-commit.md`）。マーカー原文を自前のファイルに退避しておく必要はなく、git の index が真実の源になる。bail-out 時に再衝突状態へ戻せる退路も同じ仕組みで保たれる。

> 衝突原文を一時ファイルに退避する設計は採らない（固定パスは並列実行で衝突し、状態が壊れやすい）。原文は常に `git checkout --merge` で index から復元する。

### Auto-OK ファイルごとの処理ステップ

各ファイルに対して以下のサイクルを回す：

1. **履歴調査** — `git log -p HEAD -- <file>` と `git log -p MERGE_HEAD -- <file>`（操作種別に応じてリビジョン名を変える）で両側の変更履歴を読み、コミットメッセージと周辺コードから変更意図を抽出する
2. **意図推定** — 各ハンクについて「ours は何をしたかったか」「theirs は何をしたかったか」を1行ずつ言語化する。意図が読み取れないハンクは **Auto-No に再分類** して bail-out
3. **解消方針決定（片側採用妥当性チェックを通す）** — 「ours採用 / theirs採用 / 統合 / 一方を基準に他方の意図を移植」のいずれかを選ぶ。ただし **`ours採用` / `theirs採用`（＝片側を丸ごと捨てる）を選んでよいのは、捨てる側に固有の機能・意味的変更が無いと観測事実で言える場合に限る**。具体的には捨てる側が「純粋なリネーム / フォーマット / 空白・コメントのみ / 採用する側の完全な部分集合（採用側が上位互換）」のいずれか。**両側がそれぞれ別の機能・分岐・ロジックを足している場合、片側採用は機能欠落＝デグレなので選んではならない。統合か移植を選ぶ。** 安全に統合できないなら **Auto-No に再分類して bail-out**（推測で混ぜない）
4. **解消適用** — コンフリクトマーカーを除去して解消後のコードを書き込む。**この時点では `git add` しない**
5. **機能保持チェック（相互機能保持ゲート）** — 解消後コードに対し、両側 diff から抽出した「追加された関数・メソッド・エクスポート・条件分岐・設定キー・テストケース」を1件ずつ照合し、**両側の固有機能が解消後コードに残っている**（または採用側に上位互換として吸収されている）ことを確認する。片側の固有機能が理由なく消えていたら、それはデグレ。当該ファイルを **Auto-No に再分類して bail-out** する。判断は「たぶん残っている」ではなく、シンボル名・分岐条件を実際に grep して確認する
6. **局所検証** — 解消したファイルの構文を軽く確認する（言語に応じて `tsc --noEmit <file>`、`python -m py_compile <file>`、`go vet <pkg>`、`cargo check -p <pkg>` 等）。失敗したら **即 bail-out**
7. **進捗ログ** — `<file>: ours採用 / 統合 / theirs採用 — <一行根拠（片側採用なら「捨てた側に固有機能なし」の根拠を含める）>` の形式で1行サマリを出力

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
- **機能保持チェックで、片側の固有機能が解消後コードから失われていた**（相互機能保持の破れ＝デグレ）
- 当初 Auto-OK と判定したが、適用過程で Auto-No 相当の問題（呼び出し側の不整合等）が発覚

これらが起きたら **そのファイルを未解消のまま** 残し（解消を書き込み済みなら `git checkout --merge -- <file>` で再衝突状態に戻す）、混合 bail-out に切り替える。それまでに適用した他ファイルはそのまま残す。

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

## Phase 4: コミット / --continue（履歴優先の2段構成）

ここまでで全ファイルが解消済み・検証通過済み・**ステージング前**（index は unmerged stages のまま）になっている。完了処理は操作種別で分岐する。

**なぜ2段か** — AI が「マーカーを消したコミット」を1つ積むだけだと、git ログには解消後の姿しか残らず、**どのマーカーをどう解消したのか（解消の diff）が履歴から追えない**。問題が起きた時にレビュワーが「どの解消でミスが入ったか」を辿れない。そこで merge/stash では **①コンフリクト発生状態（マーカー入り）をコミット → ②マーカー解消をコミット** の2段にし、①→②の diff として解消内容を履歴に残す。

### merge — 2段コミット

`references/two-stage-commit.md` の手順に従う。要点（状態は git index に持ち、自前の固定パス退避はしない）：

1. **解消内容を一意ディレクトリへ退避** — 検証済みのワーキングツリー（解消後）を `mktemp -d` で作った**一意の**ディレクトリにコピー（並列実行で衝突しないよう固定パスは使わない）。
2. **①スナップショットコミット** — `git checkout --merge -- <conflicted-files>` で index の unmerged stages から **マーカー入りの衝突原文を git に再生成**させ、`git add <conflicted-files>` → `git commit --no-verify`。これが **2親を持つマージコミット**で、中身はマーカー入り。フットプリントは `conflict-snapshot by 1natsu-auto-resolve-conflicts`（hook がマーカーを弾くため `--no-verify`）。
3. **②解消コミット** — 退避した解消内容を書き戻し、`git add <files>` → `git commit`。これは①を親に持つ通常コミットで、マーカーは除去済み。メッセージは解消サマリ＋フットプリント `auto-resolved by 1natsu-auto-resolve-conflicts`（`references/commit-message-template.md` 参照）。

結果、`git log` は「マージコミット（マーカー入り）→ 解消コミット」となり、`git diff <マージコミット>..<解消コミット>` が解消内容そのものになる。混合 bail-out（一部のみ解消）の場合は2段にせず、解消済みファイルを残したまま commit せず handoff する（従来どおり）。

### stash pop

stash pop は性質上コミットを作らない。解消済みファイルを `git add` するに留め、2段コミットは適用しない（コミットが無いので①②が成立しない）。スナップショット退避も結果として使わない。

### rebase / cherry-pick — 1段（解消サマリで監査）

2段にすると replay 中のコミットにマーカーが焼き込まれ、元コミットの意味破壊・bisect 破壊・履歴増殖・force-push 増幅を招くため、**従来どおり1コミットに解消を畳む**。

1. **ステージング** — `git add <resolved-file-1> <resolved-file-2> ...`（未解消ファイルは add しない）
2. **継続** — `git rebase --continue` / `git cherry-pick --continue`。元コミットメッセージは `--continue` が保持する。**`--continue` の前に `git commit --amend` を実行してはならない**（その時点の HEAD は replay 対象ではなく一つ前の既存コミットで、上書きすると履歴を破壊する）。フットプリント `auto-resolved by 1natsu-auto-resolve-conflicts` は既定では**完了報告に記す**（コミットへ無理に注入しない）。コミットにも残したい場合は cherry-pick なら `--continue` 後に `git commit --amend`、rebase は replay コミットが HEAD である時に限り amend する。詳細・禁止事項は `references/commit-message-template.md` 参照。
3. rebase で Git が次のコンフリクトで止まった場合、**Phase 0 から再帰的に処理**する。
4. 監査性は解消サマリ＋（必要時）`git range-diff` / reflog で代替する。

### 完了報告

3 点をまとめて出力する：

1. **解消サマリ** — 各ファイルでどう解消したかの一行リスト
2. **検証結果** — 実行した検証コマンドと結果（pass/fail/skip）
3. **完了アクション** — 何のコマンドで完了したか（2段の場合は snapshot コミットと解消コミットの両 hash、rebase なら状態）

## bail-out プロトコル

### 動作

bail-out が発動したら：

1. **既に適用済みのファイルはワーキングツリーに残す**（git add 済みかどうかは適用時点での状態を維持する）
2. **未解消ファイルと bail-out 理由を構造化して出力**
3. **`1natsu-pair-resolve-conflicts` への引き継ぎプロンプトを生成**

引き継ぎプロンプトのテンプレートは `references/handoff-to-pair-resolve.md` にある。操作種別 × bail-out 理由のマトリクスで定義しているので、当てはまるテンプレートを使う。

### Phase 3 検証失敗後の bail-out

検証コマンドが落ちて Phase 3 で bail-out する場合、Phase 2 までの解消は **適用済みでステージング前**（2段コミットの①スナップショットはまだ取っていない＝merge コミットは未作成）。ロールバックは強制せず、ユーザーが `git reset` / `git checkout --merge` するか pair で続行するかを選択できるよう、ハンドオフプロンプトに状態説明を含める。

### bail-out は失敗ではない

「安全に判断できなかったので人間に渡す」は本スキルの正しい振る舞い。デグレを起こす自動コミットより、bail-out の方が常に望ましい。

## 核心ルール

- **デグレ防止が最優先** — 速度や完了率より、安全に解消できる確信が持てるかを優先する。迷ったら bail-out
- **相互機能保持** — マーカーを消すことはゴールではない。ours と theirs が別々の機能を実装しているなら、片側採用は機能欠落＝デグレ。両側の機能が解消後コードに保持されることを担保する（片側採用は「捨てる側に固有機能なし」と観測できる時だけ）。安全に統合できなければ bail-out
- **観測根拠主義** — コミット履歴・diff・テスト結果という事実のみを判断根拠にする。「たぶん」「おそらく」は bail-out のサイン
- **不確実性の正直な報告** — 確信が持てない判断を「自動解消した」と報告しない。曖昧さは bail-out 理由として明示する
- **履歴優先の解消記録** — merge/stash では「マーカー入りコミット → 解消コミット」の2段で残し、解消の diff を履歴から辿れるようにする。rebase/cherry-pick は履歴・bisect を壊さないため1段＋解消サマリで監査する
- **自動コミットの責任** — 本スキルが作ったコミットは AI が責任を負う。コミットメッセージにはフットプリント（`references/commit-message-template.md`）を必ず残し、後から監査できるようにする
- **bail-out しても恥じない** — pair モードへの引き渡しは安全運用の一部であり、後退ではない
- **検証なしのコミットはしない** — 唯一の例外は Phase 3 の検証コマンド未検出時のユーザー確認のみ。それ以外で検証をスキップしない
- **rerere は尊重する** — rerere の自動解消は人間が過去に下した判断の蓄積。怪しい場合は `git rerere forget` で取り消す前に観測事実で根拠を示す
- **AI が勝手に rerere を有効化しない** — 設定変更はユーザーの責任領域

## 参考ドキュメント

- `references/bailout-rules.md` — Auto-No/Risky/Regenerate/OK の詳細条件と検出方法
- `references/stale-pr-follow.md` — Phase A の base ブランチ検出と追従（未コンフリクト状態からの起点作り）
- `references/two-stage-commit.md` — Phase 4 の履歴優先2段コミットの手順（merge/stash）
- `references/lockfile-regeneration.md` — lockfile 等の自動再生成フローとパッケージマネージャ別コマンド表
- `references/verification-detection.md` — 言語・パッケージマネージャ別の検証コマンド表
- `references/handoff-to-pair-resolve.md` — bail-out 時の引き継ぎプロンプトテンプレート
- `references/commit-message-template.md` — 自動コミットメッセージの規約とフットプリント

## 関連スキル

- `1natsu-pair-resolve-conflicts` — 人間と1ファイル/1ハンクずつ承認を取りながら解消する協調モード。本スキルが bail-out した時の引き継ぎ先
