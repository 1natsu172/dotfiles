---
description: Claude Code の settings.json（permissions / sandbox / hooks）を変更するときの鉄則
paths:
  - "**/.claude/settings.json"
  - "**/.claude/settings.local.json"
---

# Claude Code 設定（permissions / sandbox）変更の鉄則

- **仕様は記憶・独自ドキュメントを信用せず、毎回公式 Docs を WebFetch してから判断する**。仕様はバージョンで変わりドリフトするため、一次情報は常に公式 Docs:
  - permissions: <https://code.claude.com/docs/en/permissions>
  - sandbox: <https://code.claude.com/docs/en/sandboxing>
- `docs/claude-code-security.md` は **dotfiles 固有の判断**と**公式から自明でない検証済み挙動（delta）**だけを書く。仕様の写経はしない（書くとドリフトする）。
- permission rule は**実機で deny 検証してから確定**する（推測で書かない）。
  - **tool の write 防御は必ず `Edit(...)` で検証する。`Write(...)` は無機能**（組み込み Write tool も Bash redirect も gate しない。CC 2.1.210 実機確定・公式 Docs 明記で起動時 WARN の原因。詳細は `docs/claude-code-security.md` の `D3`）。`Write` だけで試すと「効かない」と誤認する。
- **dir symlink を経由するパス（`~/.config/**`・`~/.codex/**` 等、実体が dotfiles 側にあるもの）を deny するときは実体パス `~/dotfiles/...` で書き、`~/...` 綴りと併記しない**。symlink 綴りだけだと file tool しか守れず Bash と OS 層は無言で素通りし、併記は冗長なうえ「どちらが効いているか」を隠す（詳細・実測は `docs/claude-code-security.md` の `D10`）。ファイル単体の symlink（`~/.gitconfig` 等）と home の実ディレクトリ（`~/.ssh` 等）は `~/...` のままでよい。
- **綴りは hook（`claude-settings-symlink-guard`）が検査する**。settings を編集すると symlink 経由のパスが報告されるので、**報告が返ったら実体パスに直してから続ける**（無視して進めない）。手動確認は `bun ./node-scripts/src/claude-settings-symlink-guard.ts ~/.claude/settings.json`。仕組みと限界は `docs/claude-code-security.md` の「settings のパス綴りを hook で検査する」。
- **パス指定の deny は `//**/X`（FS 全体アンカー）で書く。`**/X`（相対アンカー）は使わない**。`**/` は層ごとに効き方が食い違う（ファイル型は Bash/OS 層のみ、ディレクトリ型は file tool 層のみ）うえ、**dotfiles 内で検証すると cwd と `~/.claude` が同一ツリーになり食い違いを検出できない**（`docs/claude-code-security.md` の `D11`）。
- **permission の検証は dotfiles の外に cwd を置いた「クリーンな別セッション」で行い、user に依頼する**。dotfiles 内だけの確認はアンカー由来の問題を見逃す。**subagent は代替にならない**（公式 Docs: subagent は親と同一プロセス・同一 sandbox 設定で動くため cwd 依存を再現できない）。手順は `docs/claude-code-security.md` の「別セッションでの実地検証」。
- **守る対象を具体パスで名指しできるなら、接頭辞を具体にする**（`~/dotfiles/.config/gh/**`）。`//**/<dir>/**` のように接頭辞までワイルドカードだと OS 層にはディレクトリ作成禁止までしか届かず、既存ディレクトリ配下への Bash 書き込みが残る（`docs/claude-code-security.md` の `D12`）。
- **user へ出す hook のメッセージは 1 行目に結論を詰める**（どのファイルの・何を・どう直すか）。表示は `[<hook の command>]: ` の接頭辞込み 200 文字で打ち切られるので、後ろから消えても困らない順に並べ、command 文字列も短く書く（`docs/claude-code-security.md` の `D15`）。モデルへ返る PostToolUse の stderr は全文なので、この制約は user 向け表示だけ。
- `update-config` skill の出力も鵜呑みにせず、上記（公式 Docs ＋実機検証）で裏取りする。
