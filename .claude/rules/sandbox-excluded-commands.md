# `excludedCommands` に挙げたコマンドは単独で打つ

`gh`・`fnox`・`git push -u origin` は settings の `excludedCommands` で sandbox の対象から外しているが、外れるのはコマンド全体がこれらだけでできているときに限る。パイプ、ファイルへのリダイレクト、`$(...)`、heredoc、ほかのコマンドとの連結が入ると全体が sandbox 内で動き、gh と fnox は認証設定を読めずに失敗し、`git push -u` は upstream の設定だけが黙って失敗する。

- 同じコマンド同士の `&&` `;` と `2>&1` は通る
- gh の出力の加工は `--jq` か `--template` で行う
- PR や issue の本文は Write tool でファイルに書き、`--body-file <path>` で渡す
- token が要る npm / pnpm / yarn / bun は `fnox exec -- <pm> ...` と打つ。シェル関数のラッパー経由だと送信される文字列が `npm ...` になり、除外に当たらない
- `git push -u origin HEAD` は `cd` や `git -C` で包まず、remote 名も省かない
- skill が複合コマンドで渡してきても、判定用のコマンドとは分けて実行する
- これらのコマンドが複合の形で失敗したら、`dangerouslyDisableSandbox` で再実行せず単独の形に書き直す。再実行すると、連結したほかのコマンドまで sandbox の外で動く

背景: `~/dotfiles/docs/claude-code-security.md` の `D5` と `D19`
