# 自動コミットメッセージ規約

`1natsu-auto-resolve-conflicts` が Phase 4 で `git commit` を実行するときのメッセージフォーマット。auto モードで作成されたコミットを後から監査・特定できるようにフットプリントを必ず残す。

## 基本フォーマット

```text
<title-line>

<body>

auto-resolved by 1natsu-auto-resolve-conflicts
```

- title-line（1行目）: Git の自動生成タイトルを尊重しつつ、コンフリクト解消の要点を加える
- body: 解消サマリ（オプション、複数ファイルの場合は推奨）
- フットプリント（最終行）: `auto-resolved by 1natsu-auto-resolve-conflicts` を必ず付与

## 操作種別ごとのテンプレート

### merge — 2段コミット（履歴優先）

merge は **①マーカー入りのスナップショットコミット → ②解消コミット** の2段で残す（手順は `references/two-stage-commit.md`）。コミットメッセージとフットプリントも2段で分ける。

**①スナップショットコミット**（2親を持つマージコミット、中身はマーカー入り。`--no-verify` で作成）:

```text
Merge branch '<source>' into <target> [conflict snapshot]

Raw conflict state before resolution. The next commit resolves the markers.

conflict-snapshot by 1natsu-auto-resolve-conflicts
```

**②解消コミット**（①を親に持つ通常コミット、マーカー除去済み）:

```text
Resolve merge conflicts

- <path1> — <ours|integrated|theirs>
- <path2> — <ours|integrated|theirs>

auto-resolved by 1natsu-auto-resolve-conflicts
```

Git のデフォルトテンプレート（`Merge branch '...' into ...`）は①のタイトルに活かし、`[conflict snapshot]` を付けて「これは生の衝突状態」と明示する。解消サマリは②に置く。

**フットプリントを2段で分ける理由**: ①は `conflict-snapshot by ...`、②は `auto-resolved by ...`。これにより既存の監査 grep `git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts"` が**解消コミットだけ**を拾い、スナップショットコミットを誤検出しない。`git diff <①>..<②>` が解消内容そのものになる。

> **stash pop はコミットを作らない**ため2段は適用せず、フットプリントも不要（完了報告テキストにのみ記載）。**rebase / cherry-pick は1段**で、下記テンプレートを使う。

### rebase 中のコミット（1段。破壊的 amend を絶対にしない）

rebase ではコンフリクト解消後に `git add` → `git rebase --continue` を実行する。`--continue` が replay 対象コミットを元メッセージのまま作成する。

> **危険・禁止**: `--continue` の **前** に `git commit --amend` を実行してはならない。コンフリクトで停止した時点では replay 対象コミットはまだ作られておらず、HEAD は**ひとつ前（base 側）の既存コミット**を指している。そこで amend すると **無関係な既存コミットを上書きして履歴を破壊する**（複数コミットの rebase では元コミットが消失し、共有後なら force-push で共有履歴まで壊れる）。

解消の事実を残すフットプリントの付け方:

- **既定（推奨）**: コミットには無理に注入せず、**完了報告のテキスト**に解消サマリと `auto-resolved by 1natsu-auto-resolve-conflicts` を記す。rebase は履歴を書き換える運用で、解消の監査は `git range-diff` / reflog / 報告で行う方針（SKILL.md Phase 4 の rebase=1段の考え方と一致）。
- **コミットにも残したい場合のみ**: `git rebase --continue` が当該 replay コミットを作成し、**それが HEAD になっている時に限り** `git commit --amend` で追記する。rebase がそのまま後続コミットまで進んで完了した場合、HEAD は別のコミットになっているので amend しない（対象を取り違える）。判断がつかなければ既定（報告に記す）に倒す。

```text
<元のコミットメッセージ>

[Conflict resolution]
- <path1> — <ours|integrated|theirs>

auto-resolved by 1natsu-auto-resolve-conflicts
```

### cherry-pick の継続（1段）

`git add` → `git cherry-pick --continue`。cherry-pick は単一コミットの適用なので、`--continue` が作成したコミットがそのまま HEAD になる。フットプリントを残す場合は **`--continue` の後**に `git commit --amend` で追記してよい（HEAD が当該コミットで一意なため安全）。`--continue` の前に amend しないこと。

```text
<元のコミットメッセージ>

(cherry picked from commit <hash>)

[Conflict resolution]
- <path1> — <ours|integrated|theirs>

auto-resolved by 1natsu-auto-resolve-conflicts
```

Git が `(cherry picked from commit ...)` を自動付与する場合があるため、解消サマリとフットプリントは末尾に追加する。

### stash pop（コミットなし）

stash pop はコミットを作らないため、コミットメッセージのフットプリントは不要。完了報告のテキストにのみ `auto-resolved by 1natsu-auto-resolve-conflicts` を含める。

## 解消サマリの書式

各ファイル 1 行で記述する：

```
- <relative-path> — <ours|integrated|theirs>: <一行根拠>
```

- `ours` / `integrated` / `theirs` は採用方針を明示（小文字推奨）
- 一行根拠は省略可だが、判断が複雑な場合（統合）は付けることを推奨

例：

```
- src/auth/jwt.ts — integrated: JWT署名ロジック(ours) + 期限切れハンドリング(theirs) を統合
- README.md — integrated: 両側の追記セクションを順序統合
- src/utils/date.ts — ours: theirs はリネームのみで意味的変更なし
```

### Auto-Regenerate（lockfile 再生成）の表記

lockfile 等を `<pm> install` で再生成した場合は、解消方針として **`regenerated`** を使い、再生成コマンドと frozen 検証の確認結果を1行に含める：

```
- pnpm-lock.yaml — regenerated via `pnpm install` (frozen-lockfile verified)
- package.json — integrated: 両側で別ライブラリを追加、両方の dependencies を統合
- Cargo.lock — regenerated via `cargo generate-lockfile` (`cargo build --locked` verified)
- go.sum — regenerated via `go mod tidy` (`go mod verify` verified)
```

これにより監査時に「手動マージしていない」「frozen 検証を通している」ことが grep で確認できる。

## Conventional Commits との整合

リポジトリが Conventional Commits を採用している場合、merge コミットには通常 type プレフィックスを付けない（`Merge branch ...` のまま）。ただしカスタマイズが入っている場合は `git log --oneline -10` で過去の merge コミットを確認し、慣習に倣う：

- 慣習が `Merge branch '...'` のまま → そのまま使う
- 慣習が `chore(merge): ...` 等 → 追従する

cherry-pick / rebase で作られるコミットは元のメッセージ（既に Conventional Commits 形式である前提）を維持する。

## フットプリントの厳格性

`auto-resolved by 1natsu-auto-resolve-conflicts`（解消コミット）と `conflict-snapshot by 1natsu-auto-resolve-conflicts`（merge 2段のスナップショットコミット）の文字列は **完全一致** で残す。trailer 形式（例: `Auto-Resolved-By: 1natsu-auto-resolve-conflicts`）にはしない理由：

- 後から `git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts"` で確実に検索できる
- trailer は CI が落とすことがある一方、本文末尾の単純な行は保存性が高い
- 監査時に grep だけで本スキル経由のコミットを抽出できる
- 2つのフットプリントを使い分けることで、「解消コミット」と「生の衝突スナップショット」を grep で区別できる（`auto-resolved by ...` は解消コミットだけを拾う）

## 不要な内容を含めない

- Co-Authored-By 行は付けない（人間の協働ではないため）
- 絵文字は付けない（リポジトリの慣習に依存しないようにする）
- 「自動で」「お任せで」のような口語表現は本文に含めない
- フットプリント以外に AI に関する記述は含めない（バージョン番号や日時もフットプリント文字列に含めず、必要なら git log で確認可能なため）

## 監査の所在（v1.2.0 で merge の監査面が変わった点に注意）

merge を2段にしたことで、**フットプリントの所在が変わった**:

- **解消コミット**（merge では①スナップショットの子＝1 parent の通常コミット / rebase・cherry-pick では replay コミットまたは報告）に `auto-resolved by 1natsu-auto-resolve-conflicts`。
- **スナップショットコミット**（merge の2 parent マージコミット。中身はマーカー入り）に `conflict-snapshot by 1natsu-auto-resolve-conflicts`。

旧来「マージコミット自体が解消済み・フットプリント付き」を前提にした監査（例: `git log --merges --grep="auto-resolved by ..."`、あるいは「マージコミットはマーカーを含まない」を assert する CI）は**前提が変わる**ので注意:

- 解消コミットは通常コミットなので `--merges` では拾えない。抽出は **`git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts"`（`--merges` を付けない）** を使う。
- マージコミット（スナップショット）は**意図的にマーカーを含む**。マーカー検査 CI は、`conflict-snapshot by 1natsu-auto-resolve-conflicts` を持つマージコミットを除外するか、`HEAD`（解消後ツリー）に対して検査する。
- 「2段で解消された merge」を特定したいなら `git log --grep="conflict-snapshot by 1natsu-auto-resolve-conflicts"` でスナップショットを拾い、その子が解消コミット。

## 検証

コミット後、以下で正しく適用されたか確認できる：

```bash
git log -1 --format=%B | tail -1
# → "auto-resolved by 1natsu-auto-resolve-conflicts" が出力される（最新が解消コミットのとき）

git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts" --oneline
# → 本スキル経由の解消コミットを抽出（--merges は付けない）

git show HEAD:<file> | grep -c '<<<<<<<'
# → 解消後ツリーにマーカーが無いことを確認（0）。git show HEAD だと diff の -<<< 行を拾うので :file を使う
```
