# node-scripts

Claude Code 周辺の補助スクリプト（bun ランタイム）。statusline / hook の裏方や設定バックアップに使う。

```bash
bun install         # 依存のインストール
bun run typecheck   # 型チェック（tsc --noEmit / TypeScript 7）
bun run check       # biome の lint + format
bun run test        # テスト（bun test）
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
- **claude-code-spin-detector.ts** — transcript から「thinking 空転」（reasoning 非収束のターン）を検出し、
  `~/.claude/spin-incidents.jsonl` に追記して stderr で警告する。`Stop` フックから
  `bin/claude-utils/model-spin-detector/stop-hook.sh` 経由で呼ばれる。検出シグネチャ・閾値・赤旗時の対処
  フローは同ファイル冒頭のコメントにある。
- **claude-settings-symlink-guard.ts** — `settings.json` の deny / sandbox のパスが symlink を経由して
  いないか検査する。hook（PostToolUse / SessionStart）から呼ばれるほか、引数に
  settings ファイルを渡せば手動でも回せる。設計と実測は
  [docs/claude-code-security.md](../docs/claude-code-security.md) の「settings のパス綴りを hook で検査する」。
  ```bash
  bun ./node-scripts/src/claude-settings-symlink-guard.ts ~/.claude/settings.json
  ```

> 初期化は bun v1.2.13 の `bun init` ベース。TypeScript 7 移行に伴い `tsconfig.json` の `types` だけ
> テンプレートから乖離している（理由は同ファイルのコメント）。[Bun](https://bun.sh) ドキュメントも参照。
