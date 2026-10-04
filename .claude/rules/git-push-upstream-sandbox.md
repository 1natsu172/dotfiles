# upstream を設定する push は単独の `git push -u origin HEAD` で打つ

`if` / `&&` / `cd` / `git -C` で包んだり remote 名を省いたりしない。`.git/config` は sandbox が書き込みを禁じており、`excludedCommands` の `git push -u origin *` に前方一致しない形だと sandbox 内で実行される。その場合 push は成功するが upstream の設定だけが黙って失敗する。skill が複合コマンドで渡してきても、判定用の読み取りコマンドと push を別々に実行する。

背景: `~/dotfiles/docs/claude-code-security.md` の `D5`
