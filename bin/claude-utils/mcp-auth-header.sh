#!/usr/bin/env bash
# Claude Code の headersHelper（.mcp.json / ~/.claude.json の mcpServers）用・汎用版。
# remote(HTTP) MCP の認証ヘッダを「接続時に」動的生成する。fnox の mcp profile から secret を
# 1本だけ live fetch し、{"<header>":"<scheme><token>"} を stdout に出力する。
#
# usage（headersHelper の値として呼ぶ）:
#   <path>/mcp-auth-header.sh <SECRET_NAME> [header] [scheme]
#     例) GITHUB_MCP_TOKEN               -> {"Authorization":"Bearer <token>"}
#         SOME_API_KEY  X-API-Key  ''    -> {"X-API-Key":"<token>"}
#   どのサーバがどの secret を使うかは、サーバを定義する .mcp.json 側に引数で併記する
#   （マッピングを設定に co-locate し、スクリプトは値に依存しない汎用プリミティブに保つ）。
#
# なぜ env 注入でなく headersHelper か / profile 分離の理由 / 移植性の放棄は
# docs/fnox-token-management.md「remote(HTTP) MCP への token 注入（headersHelper）」を参照。
#
# 仕様(Claude Code MCP Docs #use-dynamic-headers-for-custom-authentication):
#   stdout に string の k-v JSON / shell 実行・10秒 timeout / 接続毎(session start・reconnect)に実行。
set -euo pipefail

# Dock 起動の claude 等、最小 PATH でも解決できるよう必要な場所を明示する。
#   mise shims: fnox を版追従で解決（~/.local/share/mise/shims/fnox -> mise が dispatch） / homebrew: jq
export PATH="${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin"

secret="${1:?usage: mcp-auth-header.sh <SECRET_NAME> [header] [scheme]}"
header="${2:-Authorization}"
scheme="${3-Bearer }"   # 既定は 'Bearer '。明示的に '' を渡せば scheme 無し（生 token）

# mcp profile から単一 secret を解決する。
#   --profile mcp: MCP 用 token は mcp profile に置き、npm 等の default `fnox exec` の解決スコープから隔離。
#   --no-defaults は付けない: default [secrets] を継承して provider 認証用 SA token(OP_SA) を解決させる
#     （各 profile での OP_SA 再宣言を不要にするため。fnox get は要求 secret ＋ その認証依存のみ解決し、
#      FLATT 等 default の他 secret は巻き込まない）。
#   set -e + 単一 get: 解決失敗時は即非0終了＝空ヘッダを吐いてサイレント 401 になるのを防ぐ（fail-fast）。
# token はこの一時プロセス内に留まり、env にも出力 JSON 以外にも残さない。
token="$(fnox get "$secret" --profile mcp)"
exec jq -nc --arg h "$header" --arg v "${scheme}${token}" '{($h): $v}'
