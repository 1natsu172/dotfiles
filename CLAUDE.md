# dotfiles

macOS の個人 dotfiles。シェル・各種ツール・AI エージェントの設定を、`install.sh` が `~` へ symlink して配る。

<!-- このファイルは dotfiles を作業対象にしたときだけロードされる project scope の index。
     全プロジェクト共通の作業ルールは `.claude/CLAUDE.md`（実体は ~/.claude/CLAUDE.md）にあるので、ここには書かない。
     `AGENTS.md` はこのファイルへの symlink で、AGENTS.md 系のツールも同じ index を読む。ツール固有の指示を書かないこと。 -->

## 設計判断の在り処

コードや設定ファイルからは読み取れない設計判断・検証済みの挙動は `docs/` にある。**該当する設定を触る前に読むこと。**

- [docs/claude-code-security.md](./docs/claude-code-security.md) — Claude Code の sandbox / permission 設計、脅威モデル、公式 Docs から自明でない検証済み挙動（`D` 付きの delta 表）
- [docs/supply-chain-defenses.md](./docs/supply-chain-defenses.md) — npm / bun / pnpm のサプライチェーン多層防御。保持期間・postinstall・proxy registry
- [docs/fnox-token-management.md](./docs/fnox-token-management.md) — 秘匿情報を disk に置かず、実行時に消費プロセスへ注入する仕組み
- [docs/herdr-session-lifecycle.md](./docs/herdr-session-lifecycle.md) — herdr の server が detach を跨いで生存するため、シェル設定の変更が反映されない問題と対処。**config.fish / PATH を触ったら読むこと**
- [docs/shell-env-management.md](./docs/shell-env-management.md) — PATH / 環境変数を mise に集約する方針、`brew shellenv` と `mise activate` の順序制約、fish の二重 activate。**config.fish / .zshrc / .bashrc / mise の config.toml を触る前に読むこと**

## この repo を触るときの前提

- `~/.claude` は `dotfiles/.claude` への symlink。したがって `.claude/rules/` は **user-level rules ＝全プロジェクトでロードされる**。dotfiles 固有の内容をそこに置かない（置き場はこのファイル）
- `.claude/settings.json`（permissions / sandbox）の変更は `.claude/rules/claude-code-settings.md` に従う。仕様は記憶や本 repo の doc でなく公式 Docs を一次情報にし、実機で検証してから確定する
- 追跡対象は `.gitignore` の allowlist 方式。ツールの state / cache / 認証ファイルは追跡しない
- セットアップ手順・macOS の手動設定・各ツールの運用方針は [README.md](./README.md)
- `bin/` の自作スクリプトの一覧と役割は [bin/README.md](./bin/README.md)（PATH は mise の `_.path` で通している）
- shell script は要求 bash バージョンが 2 段（対話起動 = 4.4+、PATH 不定な hook / helper と bootstrap = 3.2 互換）。**`bin/` を触る前に [bin/README.md の「bash のバージョン方針」](./bin/README.md#bash-のバージョン方針) を読むこと。** 検査は `mise run lint:shell`（実体 `mise-tasks/lint/shell`）が pre-commit で走る。sandbox で `sync hooks: ❌ operation not permitted` が出ても commit は成功している（`D16`）
