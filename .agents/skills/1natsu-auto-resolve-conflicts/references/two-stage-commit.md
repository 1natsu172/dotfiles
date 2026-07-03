# 履歴優先の2段コミット（merge / stash）

`1natsu-auto-resolve-conflicts` の Phase 4 で、merge コンフリクトを **①マーカー入りコミット → ②解消コミット** の2段で残すための手順。

## なぜ2段にするのか

AI が解消してコミットすると、ふつうは「マーカーを消した後のコード」が1コミット積まれるだけ。すると `git log` には解消後の姿しか残らず、**どのマーカーをどう解消したのか（解消そのものの diff）が履歴から消える**。後で不具合が出た時、レビュワーは「どの解消判断でミスが入ったか」を辿れない。

2段にすると：

- **①スナップショットコミット** = git がそのまま吐いた衝突状態（マーカー入り）。merge では2親を持つマージコミットになる。
- **②解消コミット** = ①を親に持ち、マーカーを除去して整合させたコード。

`git diff <①>..<②>` が **解消内容そのもの**になり、レビュワーは解消判断だけを切り出して読める。

## 適用範囲

- **merge** — 2段（①マージコミット〈マーカー入り〉→②解消コミット）。クリーンに成立する。
- **stash pop** — コミットを作らない操作なので2段は適用しない（①②が成立しない）。解消済みファイルを `git add` するに留める。
- **rebase / cherry-pick** — **2段にしない**（1段）。理由は下記。

### rebase / cherry-pick を2段にしない理由

rebase/cherry-pick は「コミットを1つずつ replay する」操作で、2段にするにはマーカー入りのまま `--continue` して replay 後コミットにマーカーを焼き込むことになる。すると：

1. マーカー入りの壊れたコミットが**元の機能コミットのメッセージを名乗ったまま**履歴に残り、意味が壊れる
2. `git bisect` が壊れたコミットを踏んで誤判定する（rebase を選ぶ動機を潰す）
3. 競合コミット数だけ「壊れ＋解消」ペアが増殖する
4. force-push 必須なので、壊れた履歴を強制 push することになり既存レビューコメントも剥がれる
5. pre-commit / CI が各コミットで落ちる

これらは Point「履歴優先」が目指す監査性の真逆。rebase/cherry-pick は1段＋解消サマリ（コミットメッセージ）＋必要時 `git range-diff` / reflog で監査する。

## merge の2段コミット手順

前提：Phase 2 を通して **`git add` は一切していない**ため、index には unmerged stages（ベース／ours／theirs の3版）がそのまま残っている。Phase 3 の検証も通過済みで、ワーキングツリーは解消後の状態。

**設計の要**: マーカー入りの衝突原文を自前のファイルに退避しておく必要はない。**git の index が真実の源**で、`git checkout --merge -- <files>` を使えば index の unmerged stages からいつでも衝突原文を再生成できる。退避するのは「解消後の内容」だけで、それも**一意ディレクトリ（`mktemp -d`）**に置く（固定パスは並列実行で衝突する）。

移植性のため bash4 専用の `mapfile` や配列は使わず、対象一覧を一時ファイルに落として `while read` で回す（bash 3.2 / zsh / sh で動く）。

```bash
# 0) 対象集合を「Phase 4 開始時点でまだ add していない unmerged ファイル」として一度だけ確定する。
#    テキスト解消したファイルも、Auto-Regenerate で再生成した lockfile も、add していなければ
#    index に unmerged stages が残っているのでこの一覧に入る。
#    この同一の LIST を save → checkout --merge → restore の3ステップ全てで使う。
#    （集合がズレると再生成 lockfile を取りこぼし、マーカー入り原文で上書きしてしまう。）
LIST="$(mktemp "${TMPDIR:-/tmp}/conflict-list-XXXXXX")"
git diff --name-only --diff-filter=U > "$LIST"
SAVE="$(mktemp -d "${TMPDIR:-/tmp}/resolved-XXXXXX")"

# 1) 検証済みの「解消後の内容」を一意ディレクトリへ退避（テキスト解消＋再生成 lockfile を全件）
#    `--` を付け、`-foo` のような先頭ハイフンのパスをオプションと誤解釈させない
while IFS= read -r f; do
  mkdir -p -- "$SAVE/$(dirname "$f")"
  cp -- "$f" "$SAVE/$f"
done < "$LIST"

# 2) ①スナップショットコミット: index の unmerged stages からマーカー入り原文を git に再生成させてコミット
while IFS= read -r f; do
  git checkout --merge -- "$f"   # working tree に <<<<<<< 入りの衝突原文が戻る
  git add -- "$f"
done < "$LIST"
git commit --no-verify -F - <<'MSG'
Merge branch '<source>' into <target> [conflict snapshot]

Raw conflict state before resolution. The next commit resolves the markers.

conflict-snapshot by 1natsu-auto-resolve-conflicts
MSG
# → 2親（HEAD と MERGE_HEAD）を持つマージコミットが作られ、中身はマーカー入り。
#   merge が完了し MERGE_HEAD はクリアされる。

# 3) ②解消コミット: 退避した解消後を全件書き戻してコミット（再生成 lockfile もここで復元される）
while IFS= read -r f; do
  cp -- "$SAVE/$f" "$f"
  git add -- "$f"
done < "$LIST"
git commit -F - <<'MSG'
Resolve merge conflicts

- src/app.ts — integrated: ...
- README.md — integrated: ...

auto-resolved by 1natsu-auto-resolve-conflicts
MSG
# → ①を親に持つ通常コミット。マーカー除去済み。

# 4) 後片付け（解消後内容＝機密を含みうるソースを残さない）
rm -rf "$SAVE" "$LIST"
```

### ポイント

- **`--no-verify` は①のみ**。マーカー入りコードは pre-commit hook（lint・markerチェック等）に弾かれるため。②はフックを通常どおり通す（解消後の内容にフックがかかる）。
- **フットプリントを①②で分ける**。①は `conflict-snapshot by 1natsu-auto-resolve-conflicts`、②は `auto-resolved by 1natsu-auto-resolve-conflicts`。これにより既存の監査 grep `git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts"` は**解消コミットだけ**を拾い、スナップショットを誤検出しない。
- **衝突原文は git の index から再生成する（`git checkout --merge`）**。自前の固定パスに退避するとプロセス並列実行や複数解消で上書き衝突を起こす。退避するのは解消後の内容だけで、それも `mktemp -d` の一意ディレクトリに置き、最後に `rm -rf` する。
- **lockfile 等（Auto-Regenerate）も同じ FILES 集合に含める**。手順1で「再生成済みの内容」を `$SAVE` に退避し、手順3でそれを書き戻すので、①スナップショットでは生の衝突として現れても **②解消コミットでは再生成済み lockfile が正しく復元される**。要は **save / checkout--merge / restore の3ステップで必ず同じ `FILES` を使う**こと。lockfile だけ手順2の `git checkout --merge` から外すと、unmerged のまま残って①の `git commit` が unmerged paths エラーで失敗するので、外してはいけない。

## 検証

```bash
# トポロジー: 最新（解消コミット）は1親、その親（スナップショット）は2親
git log --pretty='%h %p %s' -3
# 解消の diff が辿れる
git diff HEAD^..HEAD                  # ← マーカー除去＝解消内容
# マーカー有無は「コミットの diff」ではなく「ツリー内容」で見る（git show HEAD だと diff の -<<<<<<< 行を誤って拾う）
git show HEAD:<file>  | grep -c '<<<<<<<'   # 解消コミットの中身: 0
git show HEAD^:<file> | grep -c '<<<<<<<'   # スナップショットの中身: >0
```

## bail-out との関係

スナップショットコミット（①）は **Phase 4 の最初・検証通過後**に取る。Phase 0〜3 のどこで bail-out しても①はまだ作られていないため、bail-out 時の状態（解消済み・ステージング前 / 未解消マーカー残置）は従来どおりで、`references/handoff-to-pair-resolve.md` のテンプレートはそのまま使える。2段コミットが bail-out プロトコルを複雑化することはない。

## 混合 bail-out（一部だけ自動解消）の場合

Auto-OK の一部だけを解消し残りを pair に渡す混合 bail-out では、**2段コミットを行わない**。解消済みファイルをワーキングツリーに残したまま commit せず handoff する（従来挙動）。2段は「全ファイルを自動解消しきった merge」でのみ適用する。
