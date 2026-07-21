#!/bin/sh
set -eu

# Claude Code 配下でのみ osxkeychain の store/erase を no-op にする。
# 理由: Claude Code の Bash sandbox(Seatbelt) が keychain 書き込みを拒否するため
#   store が必ず失敗し `fatal: failed to store: 100001` を吐く（get=認証は通る cosmetic）。
# get は常に osxkeychain へ委譲＝認証は不変。
# 通常ターミナル(CLAUDECODE 未設定)では全操作を委譲＝資格情報キャッシュを壊さない。
# set -u 対策: CLAUDECODE/$1 は ${VAR:-} で参照する（素の参照は通常ターミナルで unbound で落ちる）。
# pipefail は非 POSIX(dash に無い)＋パイプ無しなので付けない。
[ "${1:-}" = get ] && exec git credential-osxkeychain get
[ -z "${CLAUDECODE:-}" ] && exec git credential-osxkeychain "$1"
exit 0
