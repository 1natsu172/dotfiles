# dotfiles

macOS の個人 dotfiles。`install.sh` が各設定を `~` へ symlink する。セットアップ手順と各ツールの運用方針は [README.md](./README.md)、`bin/` のスクリプトは [bin/README.md](./bin/README.md) にある。

## 触る前に読む doc

| 触るもの | doc |
|---|---|
| `.claude/settings.json`（permissions / sandbox / hooks） | [docs/claude-code-security.md](./docs/claude-code-security.md) |
| `.claude/rules/` の `paths` | [docs/claude-code-instruction-loading.md](./docs/claude-code-instruction-loading.md) |
| `.npmrc`・`.bunfig.toml`・pnpm の config | [docs/supply-chain-defenses.md](./docs/supply-chain-defenses.md) |
| fnox の config・npm 系ラッパー・MCP の認証 | [docs/fnox-token-management.md](./docs/fnox-token-management.md) |
| `lefthook.yml` の gitleaks | [docs/token-leak-prevention.md](./docs/token-leak-prevention.md) |
| `config.fish`・`.zshrc`・`.bashrc`・mise の `[env]` | [docs/shell-env-management.md](./docs/shell-env-management.md)、[docs/herdr-session-lifecycle.md](./docs/herdr-session-lifecycle.md) |
| `Brewfile` | [docs/homebrew-maintenance-ops.md](./docs/homebrew-maintenance-ops.md) |
| `bin/` の shell script | [bin/README.md の「bash のバージョン方針」](./bin/README.md#bash-のバージョン方針) |

## 前提

- `~/.claude` は `dotfiles/.claude` への symlink なので、`.claude/rules/` と `.claude/CLAUDE.md` は全プロジェクトで読まれる。dotfiles だけに関わる指示はこのファイルに書く
- `AGENTS.md` はこのファイルへの symlink。Claude Code 固有の指示は書かない
- 追跡対象は `.gitignore` の allowlist で決まる。ツールの state・cache・認証ファイルは追跡しない
- shell script の整形は shfmt、検査は `mise run lint:shell` で、どちらも pre-commit で走る
