# Phase A: stale PR の base 追従（未コンフリクト状態からの起点作り）

`1natsu-auto-resolve-conflicts` の Phase A で参照する。ローカルはまだ衝突していないが、PR が stale（`mergeable:false`）になっていて base ブランチに追従するとコンフリクトが起きる、というケースで **コンフリクトを意図的に発生させてから通常フローに合流する** 手順。

## いつ Phase A を通るか

- `git status` に unmerged paths が **ない**（merge/rebase/cherry-pick/stash pop が進行中でない）
- かつユーザーの意図が「現在のブランチ/PR を base に統合できる状態にする」こと。次のどちらの形でもトリガーになる:
  - **症状提示** — 「PR が stale」「mergeable=false」「base とコンフリクトしてマージできない」
  - **目標提示** — 「この PR を base にマージできる状態にして」「最新の base に追従して」「base に取り込めるように」

すでにコンフリクト状態なら Phase A は飛ばして Phase 0 へ。

### 「コンフリクトが無い」で早合点しない

ユーザーが base 統合を意図しているのにローカルに衝突が無いとき、**「解消対象なし」と即断しない**。多くの場合「まだ base を取り込んでいないだけで、取り込むと衝突する（PR が base より遅れている）」状態。base を取得して乖離を観測し（下記）、遅れていれば追従する。これが本スキルの肝。

逆に、base 統合の意図がまったく読み取れない（単に clean なブランチで普通に作業中など）なら、勝手に base を merge してはいけない。状況を報告するか1回確認する。

### 乖離の観測（追従が必要かの裏取り）

base を決めたら、思い込みで merge せず観測事実で判断する:

```bash
git fetch origin <base>                 # remote が無ければ省略
git log --oneline <base>..HEAD          # PR 側にしかないコミット（PR の中身）
git log --oneline HEAD..<base>          # base 側にしかないコミット（未取り込み分）
```

- **HEAD..<base> に未取り込みコミットがある（HEAD が base に遅れている）** → 追従が必要。`git merge` で取り込む。
- **遅れていない（既に base を含む）** → 追従不要。「統合済み・追従不要」と報告して終了する。

## 既定の追従戦略：base を feature にマージ

```bash
git fetch origin <base>
git merge origin/<base>
```

この戦略を既定にする理由：

- **force-push 不要** — feature ブランチの履歴を書き換えないので、PR の既存レビューコメントが行に紐づいたまま残る（rebase だと force-push で剥がれる）。
- **追記型で監査しやすい** — GitHub の「Update branch」ボタンと同じ挙動（base を head にマージ）。
- **Phase 4 の2段コミットと整合** — 発生するのは merge コンフリクトなので、解消は merge の2段コミット（`references/two-stage-commit.md`）で綺麗に残せる。

## 前提確認（着手前のガード）

1. **進行中の git 操作がない** — `git status` に「rebasing」「merging」等が出ていない。
2. **ワーキングツリーが clean** — 未コミットの変更（untracked / unstaged）がない。あれば責任分離が困難なため、Phase 0 の早期 bail-out と同じ理由で着手前に bail-out し、「先に commit / stash してほしい」と伝える。
3. **現在ブランチが PR の head である** — detached HEAD やリリースブランチ上でないことを `git rev-parse --abbrev-ref HEAD` で確認。

## base ブランチの決定（優先順）

### 1. gh CLI ＋ PR が紐づく場合（最優先）

```bash
gh pr view --json baseRefName,mergeable,mergeStateStatus,headRefName
```

- `baseRefName` を base に採用。
- `mergeable`/`mergeStateStatus` も取得し、「本当に追従が必要か（`CONFLICTING` / `BEHIND` 等）」の根拠として報告に含める。`MERGEABLE` でクリーンなら追従しても衝突しない可能性が高い旨を添える。
- gh 未インストール / 未認証 / PR 非紐づけなら次へフォールバック。

### 2. 上流追跡 / リポジトリ default

```bash
# 上流追跡ブランチ
git rev-parse --abbrev-ref --symbolic-full-name @{upstream}   # 例: origin/main
# リポジトリの default ブランチ
git symbolic-ref refs/remotes/origin/HEAD                      # 例: refs/remotes/origin/main
```

上流が `origin/<base>` を指していればそれを、無ければ default ブランチ（典型的には `main` / `master`）を base 候補にする。ただし「上流＝同名 feature の追跡」になっているだけのこともあるので、**default ブランチと食い違う場合はユーザーに確認**する。

### 3. いずれも不明

ユーザーに1回だけ確認する（Phase A は唯一ユーザー確認を取り得る場面の一つ）：

> 追従先の base ブランチを特定できませんでした。どのブランチに追従しますか？（例: `origin/main`）

## 追従の適用と分岐

```bash
git fetch origin <base>
git merge origin/<base>
```

**remote が無い / origin が無い場合**: `git fetch origin` は失敗する。その場合は fetch を飛ばし、**ローカルの base ブランチを直接取り込む**（`git merge <base>`）。ローカル `<base>` が無ければユーザーに base を確認する。リモート追従が本来必要なケース（ローカル base が古い）では「ローカル base が最新か」を `git log` で軽く確認し、古ければユーザーに伝える。要は「取り込む先（origin/<base> かローカル <base> か）」を環境に合わせて選ぶ。

- **コンフリクトなしで完了** — base がクリーンに取り込めた。`git merge` が自動でマージコミットを作る（または fast-forward）。解消対象のコンフリクトは無いので、**作成されたマージコミットを報告して終了**する。「mergeable:false だったが、最新 base ではテキスト衝突せず追従できた」旨を添える。2段コミットは行わない（衝突が無いため）。
- **コンフリクト発生** — 期待どおり起点ができた。**Phase 0 に合流**し、以降は通常の merge コンフリクトとして Phase 0（早期 bail-out チェック）→ Phase 1（トリアージ）→ Phase 2（解消・機能保持チェック）→ Phase 3（検証）→ Phase 4（2段コミット）まで進める。

## rebase 慣習が明確な場合の例外

リポジトリ / PR が明確に rebase 運用（squash ではなく rebase-merge を既定にしている、直近の PR 追従が rebase で行われている等）で、かつユーザーが force-push を許容している場合に限り、`git rebase origin/<base>` を選んでもよい。その場合 Phase 4 は rebase の1段コミットになる（2段は適用されない）。**判断に迷うなら既定の merge を選ぶ**（force-push の副作用が無く安全側）。

## pair スキルでの Phase A

`1natsu-pair-resolve-conflicts` も Phase A 相当を持つが、**fetch / merge を実行する前に人間の承認を取る**点が異なる（base ブランチの提示 → 承認 → 追従実行）。auto は承認なしで自走する。
