#!/usr/bin/env bash

# Sample script for testing gwte
# This script demonstrates basic functionality

echo "🔧 Sample script executing in: $(pwd)"
echo "📅 Current date: $(date)"
echo "🌿 Current branch: $(git branch --show-current 2>/dev/null || echo 'Not a git repository')"
echo "📊 Directory contents:"
# shellcheck disable=SC2012  # gwte の動作確認用に ls の見た目をそのまま出すのが目的。
ls -la | head -5
echo "✅ Sample script completed successfully!"
