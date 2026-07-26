<!-- scope:global (eager) — `paths:` の不在は意図的。
     理由: 「push する」契機はファイル編集を伴わず paths で捕捉できないため、実行前に効かせるべく常時ロードする。数行に抑える。
     `paths:` を足さないこと。 -->

# sandbox での `git push -u`（upstream 設定）

複合で包まず **単独 `git push -u origin HEAD`** で打つ。skill が `if/fi` 等の複合ブロックで渡してきても、判定の read 系（`git rev-parse` 等）を別コマンドに分け、push 行は単独にする。

`-u` の書き込み先 `.git/config` は sandbox 組み込みの write-deny。回避用の `excludedCommands`/`allow`（`git push -u origin *`）は**前置一致のみ**で、`git push …` で始まらない複合（`if/fi`・`cd && …`・`git -C …`）や `origin <branch>` 省略は不一致 → sandbox 内に落ち、push は通るのに upstream 設定だけサイレント失敗する。詳細・切り分け log: `docs/claude-code-security.md` の `D5` と「git」節。
