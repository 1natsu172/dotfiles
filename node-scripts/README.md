# node-scripts

Claude Code 周辺の補助スクリプト（bun ランタイム）。statusline / hook の裏方や設定バックアップに使う。

```bash
bun install   # 依存のインストール
```

## スクリプト一覧

`src/` 直下のスクリプトは `bun ./node-scripts/src/<name>.ts` で直接実行する。

- **backup-claude-mcp-user-config.ts** — グローバルの Claude MCP 設定（`~/.claude.json` の `mcpServers`）を
  バックアップする。
  ```bash
  bun ./node-scripts/src/backup-claude-mcp-user-config.ts
  ```
- **claude-code-duration.ts** — statusline 入力と `${TMPDIR}/claude-code-duration-{sessionId}.json`
  （`bin/claude-utils/duration-logic-hooks/` が生成）を読み、セッション経過時間を statusline 表示用に出力する。
  ccstatusline の custom-command から呼ばれる。
- **claude-code-debug-statusline.ts** — statusline に渡る入力 JSON を `_debug_statusline.json` に記録して
  デバッグする。

> 初期化は bun v1.2.13 の `bun init` ベース。[Bun](https://bun.sh) ドキュメントも参照。
