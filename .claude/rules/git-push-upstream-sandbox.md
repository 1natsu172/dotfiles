# sandbox での `git push -u`（upstream 設定）

複合で包まず **単独 `git push -u origin HEAD`** で打つ。skill が `if/fi` 等の複合ブロックで渡してきても、判定の read 系（`git rev-parse` 等）を別コマンドに分け、push 行は単独にする。

`-u` の書き込み先 `.git/config` は sandbox 組み込みの write-deny。回避用の `excludedCommands`/`allow`（`git push -u origin *`）は**前置一致のみ**で、`git push …` で始まらない複合（`if/fi`・`cd && …`・`git -C …`）や `origin <branch>` 省略は不一致 → sandbox 内に落ち、push は通るのに upstream 設定だけサイレント失敗する。詳細・切り分け log: memory `bash-command-execution-control`。
