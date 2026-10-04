# Claude Code の命令ロード

仕様は公式 Docs（[memory](https://code.claude.com/docs/en/memory) / [hooks](https://code.claude.com/docs/en/hooks)）を見る。ここには実機で測った挙動と、それに基づく判断だけを書く。

## `paths` の解決規則

`.claude/rules/*.md` は `paths` があれば該当ファイルを file tool で開いたときに、無ければ起動時に載る。Bash の `cat` では載らない。

glob は project root（起動時の cwd）を基準に解決され、その配下しか捕捉しない。rule の置き場は関係なく、`~/.claude/rules/` の rule でも同じ。CC 2.1.220 で、dotfiles の外を cwd にしたセッションで測った。

| `paths` の書式 | project 配下の `.claude/settings.json` | project root の外 |
|---|---|---|
| `**/.claude/settings.json`・`.claude/settings.json`・`**/settings.json` | 発火 | 発火しない |
| `//**/.claude/settings.json` | 発火しない | 発火しない |
| 絶対パス・`~/` 始まり | 対象外 | 発火しない |

- permission の `//**/X` は `paths` では一度も発火しない。書式を流用しない
- project root の外（他 project から触る `~/.claude/settings.json` 等）はどう書いても捕捉できない。必要なら `paths` を外して常時ロードにする
- 契機がファイル編集でない rule（コマンドを打つ前に効かせたいもの、応答の文体）も常時ロードにするしかない。常時ロードは毎セッションのコンテキストを使うので短く保つ

## hook の `additionalContext`

- 履歴に attachment として残り、以降の全リクエストで再送される。prompt cache が下げるのは料金だけで、context window の占有は減らない。頻繁に注入すると compact が早まる
- `@path` は展開されない。`@` import は起動時のメモリファイル読み込みでしか効かない

## 検証のやり方

`paths` は cwd に依存するので、dotfiles の外を cwd にした別セッションで測る。dotfiles を cwd にすると rule の置き場と cwd が同じツリーに重なり、subagent は親と同じ cwd で動く。

- 判定はログで取る。検証用 project の `.claude/settings.json` に `InstructionsLoaded` hook を置き、`load_reason`（`path_glob_match` / `session_start`）と `file_path` を記録する。`session_start` の行が hook 自体が動いている証拠になる。取り損ねても transcript の `nested_memory` attachment に残る
- 書式の候補は使い捨ての probe rule を `~/.claude/rules/` に並べ、1 セッションでまとめて測る
- rule は 1 セッションに 1 回しか載らない。2 回目以降はログに出ないので、増えないことを「マッチしなかった」と読まない。同じ rule を複数の場所で踏ませるなら順番を決めるかセッションを分ける
- rule ファイル自体を Read / Write したセッションでは、本文が既に載っているので判定しない
