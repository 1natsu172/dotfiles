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

### merge コミット

```text
Merge branch '<source>' into <target>

Resolved conflicts in:
- <path1> — <ours|integrated|theirs>
- <path2> — <ours|integrated|theirs>

auto-resolved by 1natsu-auto-resolve-conflicts
```

Git のデフォルトテンプレート（`Merge branch '...' into ...`）はそのまま採用。空行を挟んで解消サマリ、最後にフットプリント。

### rebase 中のコミット

rebase ではコンフリクト解消後に `git rebase --continue` を実行する。元のコミットメッセージは Git が保持してくれるが、解消の事実を残すため `--edit` 相当のメッセージ追加を行う：

```text
<元のコミットメッセージ>

[Conflict resolution]
- <path1> — <ours|integrated|theirs>
- <path2> — <ours|integrated|theirs>

auto-resolved by 1natsu-auto-resolve-conflicts
```

実装上は `GIT_SEQUENCE_EDITOR` を介さず、`--continue` 直前に `git commit --amend -m "<full message>"` で書き換える。元メッセージを失わないこと。

### cherry-pick の継続

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

`auto-resolved by 1natsu-auto-resolve-conflicts` の文字列は **完全一致** で残す。trailer 形式（例: `Auto-Resolved-By: 1natsu-auto-resolve-conflicts`）にはしない理由：

- 後から `git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts"` で確実に検索できる
- trailer は CI が落とすことがある一方、本文末尾の単純な行は保存性が高い
- 監査時に grep だけで本スキル経由のコミットを抽出できる

## 不要な内容を含めない

- Co-Authored-By 行は付けない（人間の協働ではないため）
- 絵文字は付けない（リポジトリの慣習に依存しないようにする）
- 「自動で」「お任せで」のような口語表現は本文に含めない
- フットプリント以外に AI に関する記述は含めない（バージョン番号や日時もフットプリント文字列に含めず、必要なら git log で確認可能なため）

## 検証

コミット後、以下で正しく適用されたか確認できる：

```bash
git log -1 --format=%B | tail -1
# → "auto-resolved by 1natsu-auto-resolve-conflicts" が出力される

git log --grep="auto-resolved by 1natsu-auto-resolve-conflicts" --oneline
# → 本スキル経由の全コミットを抽出
```
