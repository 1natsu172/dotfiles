#!/usr/bin/env bash

# Claude Code Stop hook: thinking 空転（reasoning 非収束）検出の薄いアダプタ
# 本体・検出ロジック・赤旗時フローのドキュメントは node-scripts 側を参照
exec bun "$HOME/dotfiles/node-scripts/src/claude-code-spin-detector.ts"
