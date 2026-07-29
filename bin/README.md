# bin/ - ユーティリティスクリプト集

開発作業を効率化するためのスクリプト群。fnox 関連スクリプト（秘匿情報の注入）は設計の詳細を
[docs/fnox-token-management.md](../docs/fnox-token-management.md) に集約しており、ここでは役割の一覧に留める。

## ディレクトリ構成

```
bin/
├── README.md
├── clean-old-branches             # 古い Git ブランチの安全な削除
├── difiti                         # fzf で commit 範囲を選び difit で差分表示
├── gwte                           # Git Worktree 一括コマンド実行
├── sample-script.sh               # gwte 動作確認用サンプル
├── install-fnox-shell-wrappers    # fnox シェル関数ラッパーの生成（冪等）
├── fnox-wrappers.sh               # ↑の生成物。PM を `fnox exec` で包む POSIX 関数
├── parallel-video-download        # → video-utils/ への symlink
├── setup-scripts/
│   └── subtree-manager.sh         # Git subtree の設定駆動管理
├── claude-utils/
│   ├── debug-hook.sh              # Claude Code フックのデバッグ
│   ├── mcp-auth-header.sh         # remote(HTTP) MCP の認証ヘッダ生成（headersHelper）
│   └── duration-logic-hooks/      # Claude Code セッション時間計測
│       ├── user-prompt-submit-hook.sh
│       ├── agent-in-progress-hook.sh
│       └── finished-responding-hook.sh
└── video-utils/
    ├── parallel-video-download    # yt-dlp + aria2c で動画を並列ダウンロード
    └── urls.txt.example           # ↑の URL リスト雛形
```

サブディレクトリは、直下がフラットで煩雑になるのを避けるためと、スクリプト付属の README や
サンプルファイルを同居させるために切っている。

PATH が通っているのは `bin/` 直下だけで、サブディレクトリは追加しない。コマンドとして直接
叩きたいものは `bin/` 直下に相対 symlink を張る。PATH のエントリを増やさずにコマンド名だけを
増やせる。サブディレクトリ内のスクリプトを設定ファイルから呼ぶ場合は絶対パスを使う
（`.mcp.json` の `headersHelper` 等）。

## bash のバージョン方針

macOS 同梱の `/bin/bash` は 3.2 固定なので、Brewfile で bash 5 を入れている。shebang は
`#!/usr/bin/env bash` に揃えてあり、PATH 先頭が `/opt/homebrew/bin` なので通常はこちらが
使われる。ただし **`env bash` の解決先は呼び出し元の PATH 次第**で、どちらが動くかは
起動経路で変わる。そのため要求バージョンを一律にせず、呼ばれ方で 2 段に分けている。

**bash 4.4+ を要求する（PATH が保証される経路）**

`gwte` / `clean-old-branches` / `setup-scripts/subtree-manager.sh` /
`video-utils/parallel-video-download`。人がシェルから叩くので mise を活性化した PATH を
前提にできる。冒頭に `BASH_VERSINFO` を見るガードを置き、3.2 で起動されたら実行前に終了
させる（途中で壊れると原因が分かりにくいため）。4.4 を下限にしたのは、`set -u` 下での空配列
の展開（`"${arr[@]}"`）が 4.3 以前では unbound variable で落ちるため。

**bash 3.2 互換を維持する（PATH が不定、または bash 5 より前に走る経路）**

- `claude-utils/` 配下 — Claude Code の hooks と `headersHelper`。`settings.json` /
  `.mcp.json` から絶対パスで起動されるため、PATH は Claude Code のプロセス次第になる。
  GUI から起動された場合は `/usr/bin:/bin` だけになり `/bin/bash` に落ちる
- `credential-helper.sh` — git が呼ぶ。`#!/bin/sh` で POSIX の範囲に留める
- `install-fnox-shell-wrappers` と repo ルートの `install.sh` — README のセットアップ手順で
  `brew bundle` より前に走る。新規マシンではまだ bash 5 が存在しない
- `sample-script.sh` と `difiti` — bash 4 以降の機能を使わないので、要求を上げる理由がない

`fnox-wrappers.sh` は fish / zsh / bash の rc から source される生成物なので POSIX 関数のみ。

**shellcheck は zsh を扱えない**（`SC1071` で拒否）。zsh で書くと静的検査が効かなくなるので、
**zsh 固有の機能が要らないなら bash で書く**。禁止はしておらず必要なら置ける（lint は shebang
を見て理由付きで対象外にする）。shfmt は zsh を扱えるので、zsh のスクリプトに整形だけ掛けたく
なったら `mise-tasks/lint/shell` の振り分けを shellcheck 用と shfmt 用に分ける。

整形は shfmt のデフォルト（タブ）に揃える。shfmt はコマンドラインに整形フラグを 1 つでも
渡すと EditorConfig の設定を全て無視する仕様なので、フラグは意図的に渡さない。

この方針は `mise run lint:shell`（実体は `mise-tasks/lint/shell`）が検査し、`lefthook.yml` から
pre-commit で走る。整形のずれは不一致のファイルと修正コマンドを出して落ちる。3.2 互換の検査は
静的解析なので実行時にしか現れない差は取りこぼす。3.2 で動くことの保証ではない。

## Git 管理ツール

### clean-old-branches - 古いブランチの削除

指定日数より古いローカルブランチを安全に削除する。

```bash
clean-old-branches [days] [--force]
```

```bash
clean-old-branches        # 30 日より古いブランチを対話的に削除
clean-old-branches 60     # 60 日より古いブランチを対話的に削除
clean-old-branches 30 --force  # 確認なしで強制削除
```

- `main`/`master`/`develop`/`dev`/`staging`/`production` は保護される
- マージされていないブランチ・worktree でチェックアウト中のブランチは削除されない（安全機能）

### difiti - commit 範囲のインタラクティブ差分

`git log` から fzf で from / to の 2 commit を選び、外部ビューア `difit` で `<to>..<from>~1` の差分を開く。

```bash
difiti
```

- `difit` コマンドが PATH 上に必要

### gwte - Git WorkTree Executor

複数の Git worktree に対して同じコマンドを一括実行する。

```bash
gwte [OPTIONS]
```

```bash
gwte --interactive --command "git status"      # 対話的に worktree を選択して実行
gwte --all --command "npm test" --dry-run      # 全 worktree でテスト（ドライラン）
gwte --all --command "npm run build"           # 全 worktree でビルド
```

- `--all` または `--interactive` のいずれかが必須
- `--dry-run` で事前確認を推奨

### subtree-manager.sh - Git Subtree 管理

Git subtree を設定ファイル駆動で管理する。

```bash
./setup-scripts/subtree-manager.sh <command> [arguments]
```

```bash
./setup-scripts/subtree-manager.sh list                          # 設定済み subtree の一覧
./setup-scripts/subtree-manager.sh add claude-agents-wshobson     # 特定の subtree を追加
./setup-scripts/subtree-manager.sh add-all                        # 全 subtree を追加（既存は無視）
./setup-scripts/subtree-manager.sh update claude-agents-wshobson  # 特定の subtree を更新
./setup-scripts/subtree-manager.sh update-all                     # 全 subtree を更新
```

- スクリプト内の `SUBTREE_CONFIGS` 配列での事前設定が必要（設定済みのみ操作可能）

## fnox（秘匿情報の注入）

パッケージマネージャ（npm/yarn/pnpm/bun 等）を `fnox exec` で包み、registry token を呼び出しごとに
ツールの env にだけ注入するシェル関数ラッパー。PATH shim ではなく**各シェルが読むファイルのシェル関数**で配る。

- **install-fnox-shell-wrappers**: 単一の `TOOLS` 列（このスクリプト内が唯一の真実）から、各シェル用の
  ラッパーファイルを冪等に生成する。生成物は `bin/fnox-wrappers.sh`（zsh/bash が `source`）と
  `.config/fish/conf.d/fnox-wrappers.fish`（fish が自動 source）。hand-maintained な rc は触らない。
- **fnox-wrappers.sh**: 上記の生成物。`npm() { fnox exec -- npm "$@"; }` 形式の POSIX 関数。
  `command <tool>` で bypass、版解決は mise に委譲。

設計判断（なぜ PATH shim をやめたか・版解決・トレードオフ・無効化手順）は
[docs/fnox-token-management.md](../docs/fnox-token-management.md) を参照。

## Claude Code 関連ツール

これらのフックスクリプトは `dotfiles/.claude/settings.json` の `hooks` に**正規のイベント名**で配線する
（フックは CLAUDE.md ではなく settings.json に書く。`command` type の command hook として登録）。

### duration-logic-hooks/ - セッション時間計測

Claude Code セッションの開始〜終了の時間を計測・記録し、statusline 表示用データ（`${TMPDIR}/claude-code-duration-{sessionId}.json`）を生成する。3 スクリプトをセットで配線する:

| スクリプト | 配線するイベント（settings.json `hooks`） |
|-----------|------------------------------------------|
| `user-prompt-submit-hook.sh` | `UserPromptSubmit` |
| `agent-in-progress-hook.sh` | `PreToolUse` / `PostToolUse` / `SubagentStop` |
| `finished-responding-hook.sh` | `Stop` |

- 基本的にフック経由でのみ動き、手動実行はほぼしない
- 中断されたセッション（interrupt）も正しく処理される。時間は UTC・ミリ秒で計測

### debug-hook.sh - フックのデバッグ

フック実行時の入力データを JSON（`debug-claude-hook-{sessionId}.json`）に出力してデバッグする。
確認したいイベント（例 `UserPromptSubmit`）の下に `settings.json` の `hooks` で command hook として
一時登録して使う。実行ディレクトリにセッションごとの履歴が配列で蓄積される。

### mcp-auth-header.sh - remote MCP 認証ヘッダ生成

remote(HTTP) MCP の認証ヘッダを接続時に動的生成する汎用 helper（Claude Code の `headersHelper`）。
fnox の `mcp` profile から secret を 1 本だけ live fetch し `{"<header>":"<scheme><token>"}` を stdout に出す。
どのサーバがどの secret を使うかは `.mcp.json` 側に引数で併記する。背景・profile 分離の理由は
[docs/fnox-token-management.md](../docs/fnox-token-management.md)「remote(HTTP) MCP への token 注入」を参照。

## 動画ツール

### video-utils/parallel-video-download - 並列動画ダウンロード

`urls.txt`（雛形: `urls.txt.example`）の URL を yt-dlp + aria2c で並列ダウンロードする。
進捗トラッキングと失敗 URL のリカバリ付き。依存: `yt-dlp`, `aria2c`。

## テスト・サンプル

### sample-script.sh - gwte の動作確認用

現在のパス・日時・Git ブランチ・ディレクトリ内容を表示するだけのサンプル。
gwte が正しく動くかのテストや、worktree での動作確認に使う。

```bash
./sample-script.sh
```

## 関連ドキュメント

- Claude Code フック: <https://code.claude.com/docs/en/hooks>
- Git subtree: <https://git-scm.com/docs/git-subtree>
- Git worktree: <https://git-scm.com/docs/git-worktree>
