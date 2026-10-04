---
description: Claude Code の settings.json（permissions / sandbox / hooks）を変更するときの規則
paths:
  - "**/.claude/settings.json"
  - "**/.claude/settings.local.json"
---

# Claude Code の settings 変更

- 仕様は記憶で判断せず、公式 Docs（[permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing) / [hooks](https://code.claude.com/docs/en/hooks)）を読んでから決める。`update-config` skill の出力も同じく裏を取る
- permission rule は実機で deny されることを確かめてから確定する。検証は dotfiles の外を cwd にした別セッションで user に依頼する。dotfiles 内では cwd と `~/.claude` が同じツリーに重なり、subagent は親と同じ cwd で動くので、照合の起点に由来する問題が再現しない
- 公式 Docs から読み取れない挙動は `~/dotfiles/docs/claude-code-security.md` の delta 表にある。特に踏みやすいもの:
  - write の deny は `Edit(...)` で書く。`Write(path)` は何も止めない（`D3`）。hook の `if` は逆で、Write tool を捕まえるには `Write(...)` が要る（`D18`）
  - dotfiles に実体があるパスは `~/dotfiles/...` で書く。dir symlink 経由の綴りは file tool にしか効かない（`D10`）。違反は `claude-settings-symlink-guard` hook が報告するので、報告が出たら直してから進める
  - パス指定の deny は `//**/X` で書き、`**/X` は使わない（`D11`）。守る対象を名指しできるなら接頭辞を具体パスにする（`D12`）
