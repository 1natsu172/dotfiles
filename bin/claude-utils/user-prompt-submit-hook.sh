#!/bin/bash

# ユーザーがプロンプトをサブミットした時に実行されるhook
# セッション開始時刻を記録し、既存のセッションデータをクリア

# 入力からセッションIDを取得
session_data=$(cat)
session_id=$(echo "$session_data" | jq -r '.session_id // empty')

if [ -z "$session_id" ]; then
    exit 0
fi

# tmpファイルのパス
tmp_file="${TMPDIR:-/tmp}/claude-code-duration-${session_id}.json"

# 現在のタイムスタンプをISO8601形式のUTC時刻で取得
# 例: "2025-08-21T18:04:18Z"
current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# セッションデータを作成・保存
cat > "$tmp_file" << EOF
{
  "sessionId": "$session_id",
  "startTimestamp": "$current_timestamp",
  "lastUpdate": "$current_timestamp",
  "duration": 0,
  "status": "active"
}
EOF

exit 0