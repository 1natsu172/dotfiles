---
description: Claude Code の settings.json（permissions / sandbox）を変更するときの鉄則
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
  - **tool の write 防御は必ず `Edit(...)` で検証する。`Write(...)` は組み込み Write tool に効かない**（Bash redirect 専用）。`Write` だけで試すと「効かない」と誤認する。
- `update-config` skill の出力も鵜呑みにせず、上記（公式 Docs ＋実機検証）で裏取りする。
