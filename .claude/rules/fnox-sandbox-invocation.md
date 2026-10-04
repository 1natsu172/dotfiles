# token が要る npm / yarn / pnpm / bun は `fnox exec` で打つ

registry の token を要する操作（install・publish 等）は、素の `npm install` ではなく `fnox exec -- npm install` の形で打つ。素のラッパー呼び出しは sandbox 内に残り、fnox が呼ぶ op が TLS 検証に失敗して 401 になる。`fnox *` は `excludedCommands` に入っているので、この形なら sandbox 外で token を解決できる。token が要らないコマンドは素のままでよい。

背景: `~/dotfiles/docs/claude-code-security.md` の「fnox」節
