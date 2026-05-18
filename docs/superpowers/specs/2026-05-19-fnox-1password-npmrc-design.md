---
title: fnox + 1Password Service Account による .npmrc registry token 管理
date: 2026-05-19
status: design
---

# 概要

`~/dotfiles/.npmrc` の Flatt Security private npm registry 用 token を、ローカル disk
の平文から取り除き、fnox + 1Password service account 経由で取得する仕組みを構築する。
本タスクは、今後の secret 全般を fnox + op に統一管理する基盤の最初の起点となる。

# 動機

- 現状の `.npmrc` は `//npm.flatt.tech/:_authToken=<plain>` を平文で保持。git 追跡対象
- AI ツール（Claude Code 等）の Read 系操作で容易に内容が漏出する
- AI ツール経由のマルウェアやサプライチェーン攻撃を見据え、env への露出も最小化したい
- 将来 op 以外の backend（age 単独 / AWS / GCP / sops 等）に切り替えうるので、
  **fnox を統一インターフェースとして固定**しておきたい
- 既存の mise+sops+age による env 漏出は別途解消する予定だが、新規 secret に関しては
  本タスク以降 fnox 経由で運用を開始する

# 設計

## 全体構成

```
ユーザー / AI ツールが npm / yarn / bun / npx / bunx / pnpm / pnpx を実行
  ↓
PATH 先頭の ~/dotfiles/bin/fnox-shims/<tool> (symlink)
  ↓
~/dotfiles/bin/_fnox_npm_shim (dispatcher)
  ↓
exec fnox exec -- mise x -- <tool> "$@"
  ↓
fnox exec が ~/.config/fnox/config.toml を読み込み
  ├─ age provider が age 鍵で SA token (ops_xxx) を復号
  ├─ op_personal provider が op CLI に SA token を渡して `op read op://...` 実行
  └─ FLATT_NPM_TOKEN を subprocess 環境変数として注入
  ↓
mise x が tool を解決し、env 継承で実体 npm を起動
  ↓
npm が .npmrc 内 `${FLATT_NPM_TOKEN}` を env から展開、registry にリクエスト
```

## A. fnox global config

**場所**: `~/dotfiles/.config/fnox/config.toml`
（dotfiles の `.config/` は install.sh で `~/.config/` に symlink される構造なので、
fnox からは `~/.config/fnox/config.toml` として参照される ＝ fnox の global config 規約と一致）

```toml
# Age 鍵で SA トークンを復号する provider
[providers.age]
type = "age"
recipients = ["age1<PUBLIC_KEY>"]
# 鍵ファイルは既存 sops 用ファイルを再利用（machine-local、gitignored）
key_file = "~/.config/mise/age.txt"

# Personal vault 用の 1Password service account
[providers.op_personal]
type = "1password"
token = { secret = "OP_SA_PERSONAL" }

[secrets]
# SA トークン本体は age 暗号化済み（disk 上は base64 暗号文のみ）
OP_SA_PERSONAL = { provider = "age", value = "<age-encrypted-blob>" }

# 実際に欲しい secret（op から live で fetch）
FLATT_NPM_TOKEN = { provider = "op_personal", value = "op://Personal/slhx4rnaex4ectm6hxblqyiu7y/credential" }
```

**性質**:
- このファイルには平文の秘匿値は含まれない（age 暗号文と op:// 参照のみ）
- git 追跡可
- 復号に必要なのは `~/.config/mise/age.txt`（gitignored、machine-local）
- 命名規約 `op_personal` の suffix により、将来 `op_work` 等の追加が衝突なく可能

## B. dispatcher 兼 deploy スクリプト

**場所**: `~/dotfiles/bin/_fnox_npm_shim`（git 追跡、実行権限）

```bash
#!/usr/bin/env bash
# fnox exec で wrap して呼ぶ tool 群の dispatcher。
# 起動時の $0 ファイル名から tool 名を判定し、mise x 経由で実体を呼ぶ。
# 親シェル env に secret を露出させず、tool 子プロセスにのみ注入する。
#
# 拡張: tool を増やす場合は FNOX_WRAPPED_TOOLS に追記して install.sh を再実行。

set -euo pipefail

# 単一の真実: fnox exec で wrap したい tool 名の列挙
FNOX_WRAPPED_TOOLS=(npm npx yarn bun bunx pnpm pnpx)

# --- Deploy モード: install.sh から呼ばれる ---
if [[ "${1:-}" == "--deploy" ]]; then
    bin_dir="$(cd "$(dirname "$0")" && pwd)"
    target_dir="${bin_dir}/fnox-shims"
    mkdir -p "$target_dir"
    self_name="$(basename "$0")"
    for tool in "${FNOX_WRAPPED_TOOLS[@]}"; do
        ln -snfv "../${self_name}" "${target_dir}/${tool}"
    done
    exit 0
fi

# --- 通常のディスパッチ ---
tool="${0##*/}"
exec fnox exec -- mise x -- "${tool}" "$@"
```

## C. shim 配置ディレクトリ

`~/dotfiles/bin/fnox-shims/` を install.sh の deploy ステップで作成。
中身は `../_fnox_npm_shim` への相対 symlink。

dispatcher script（`bin/_fnox_npm_shim`）は git 追跡対象。symlink は派生物として gitignore。

## D. mise の PATH 投入

`~/dotfiles/.config/mise/config.toml` の `[env]` セクションに 1 行追加:

```toml
[env]
SOPS_AGE_KEY_FILE = "{{config_root}}/.config/mise/age.txt"
_.file = { path = "~/dotfiles/.env.enc.json", redact = true }
_.path = ["~/dotfiles/bin/fnox-shims"]   # ← 追加
```

mise activate が fish/zsh/bash の rc で走るので、これらすべての対話シェルで
`~/dotfiles/bin/fnox-shims` が PATH 先頭に prepend される。
PATH は env 継承で非対話 subshell（AI ツールの `bash -c '...'` 含む）にも伝播するため、
shell 種別と対話/非対話を問わず一様に shim が拾われる。

mise 公式ドキュメント自身が、shell-aliases が非対話で機能しないケースの workaround として
この pattern を推奨している:

> "Use the underlying command directly in tasks, or add wrapper scripts to your PATH via `env._.path`."

## E. .npmrc の差し替え

```
registry=https://npm.flatt.tech/
//npm.flatt.tech/:_authToken=${FLATT_NPM_TOKEN}
```

- トークン文字列は placeholder のみ
- npm / yarn / bun / pnpm はすべて `.npmrc` の `${VAR}` 形式環境変数展開を native サポート
- permission は保守的に 600 維持（中身が placeholder のみとはいえ厳しい設定を維持）
- git tracking 継続

## F. .gitignore 更新

```gitignore
# fnox の global config はトラッキング対象（既存の .config/* + 個別 whitelist パターンに合わせる）
!.config/fnox

# 自動生成 shim symlink は管理外（glob で一括 ignore）
bin/fnox-shims/
```

## G. install.sh 拡張

末尾に deploy ステップを追加:

```bash
# fnox shim symlinks の deploy（idempotent）
if [[ -x "${DOT_DIRECTORY}/bin/_fnox_npm_shim" ]]; then
    "${DOT_DIRECTORY}/bin/_fnox_npm_shim" --deploy
fi
```

`ln -snfv` により再実行安全。`FNOX_WRAPPED_TOOLS` に tool を足して install.sh を再実行すれば
新しい shim が増える。

## H. Bootstrap 手順（ユーザー実装時の手作業）

1. 1Password 管理画面で service account `fnox-personal-npm`（仮名）を作成し、
   Personal vault への read-only access に絞る
2. 発行された `ops_xxx` トークンを安全に控える
3. 既存 age 公開鍵を抽出（age.txt の `# public key: age1...` 行から）:
   ```fish
   awk '/public key:/{print $NF}' ~/.config/mise/age.txt
   # → age1xxx... が出力される
   ```
4. `~/dotfiles/.config/fnox/config.toml` の `recipients = ["age1<PUBLIC_KEY>"]` を実値に置換
   （`key_file` も `~/.config/mise/age.txt` で固定済み）
5. SA トークンを age 暗号化して fnox config に書き込む:
   ```fish
   fnox set OP_SA_PERSONAL "ops_xxx" --provider age
   # ~/.config/fnox/config.toml の [secrets] に age 暗号化された値が自動追記される
   ```
   暗号化に必要な情報（recipients, key_file）は config.toml から自動で読まれる。
   FNOX_AGE_KEY_FILE 環境変数を別途設定する必要はない
6. `~/dotfiles/.npmrc` を placeholder 形式に書き換え（plain token を削除）
7. `~/dotfiles/.config/mise/config.toml` に `_.path = ["~/dotfiles/bin/fnox-shims"]` を追記
8. `~/dotfiles/.gitignore` を更新
9. `~/dotfiles/install.sh` の deploy ステップを追加
10. `bash ~/dotfiles/install.sh` を実行
11. 新しいシェルを開いて検証ステップへ

# セキュリティ特性

## 守れる

- disk 上に平文 token が存在しない（`.npmrc` は placeholder、`fnox.toml` は age 暗号文 + op:// 参照のみ）
- 親シェル env に token が乗らない（fnox exec で wrap した子プロセスにのみ注入）
- `env` / `printenv` / `set` / `/proc/self/environ` 等で読まれない
- AI ツールが `bash -c 'env | grep TOKEN'` を実行しても、親シェル env を継承するだけで token は無い
- service account なので op CLI が個人セッションに依存せず、TouchID プロンプトが運用中に出ない
- age 鍵ファイルが流出しない限り、リポ公開しても秘匿値は復元できない

## 守れない（明示的に受容するリスク）

- npm 子プロセスとその子孫プロセス（`package.json` scripts, postinstall hook 等）の env には
  FLATT_NPM_TOKEN が乗る。npm が `.npmrc` の `${VAR}` を展開するため原理的に避けられない
- 対策（`.npmrc` に `ignore-scripts=true` を入れる等）は本タスク範囲外、別タスクで検討
- 既存の mise activate + sops+age 由来の env 漏出は別タスクで対応予定。
  本タスクは新規 secret 経路の構築に集中する

# 検証手順

実装後に新しいシェルを開いて以下を確認:

1. **age 復号確認**:
   ```
   fnox get OP_SA_PERSONAL
   ```
   → `ops_xxx` で始まる文字列が返ること
   （`key_file` は config.toml に記述済みなので環境変数の追加設定は不要）
2. **op 連携確認**:
   ```
   fnox get FLATT_NPM_TOKEN
   ```
   → `tg_anon_xxx` で始まる npm token が返ること
3. **PATH 順序確認**:
   ```
   which npm
   ```
   → `~/dotfiles/bin/fnox-shims/npm` を指すこと
4. **env 隔離確認**:
   ```
   env | grep FLATT_NPM_TOKEN     # 何も出ない
   set | grep FLATT_NPM_TOKEN     # 何も出ない
   ```
5. **npm 子プロセス内で展開されるか**:
   ```
   npm config get //npm.flatt.tech/:_authToken
   ```
   → token 値が返る（npm 子プロセス内で env から `${VAR}` が展開される）
6. **registry 認証成功**:
   ```
   npm whoami --registry https://npm.flatt.tech/
   ```
   → 認証成功
7. **AI ツール経路（非対話 bash サブシェル）確認**:
   ```
   bash -c 'env | grep FLATT_NPM_TOKEN'    # 何も出ない
   bash -c 'npm whoami --registry https://npm.flatt.tech/'   # 認証成功
   ```

# トレードオフと棄却した代替

## 棄却: `fnox activate` の shell integration

- 親シェル env に `set -gx` で export される（`fnox activate fish` の hook-env 出力で実測確認済み）
- AI ツールが `env` で容易に読める、サブプロセス継承で漏れる → 脅威モデル違反

## 棄却: desktop+biometric via fnox onepassword provider (token なしモード)

- 実装は対応する（op CLI への shell-out 時に `OP_SERVICE_ACCOUNT_TOKEN` が optional）
- ただし fnox docs が明示的に推奨していない経路。将来仕様が固まる可能性あり
- 個人プランでも SA が作成可能と判明したため、docs 推奨どおりの SA 経路を採用

## 棄却: fish 関数のみの wrapper

- AI ツール（Claude Code 等）の非対話 `bash -c` には fish 関数が見えない

## 棄却: mise plugin (Tool / Backend / Env / asdf)

- mise plugin の種別に「既存 tool の呼び出しを wrap する」タイプが存在しない（docs 確認済み）

## 棄却: mise-env-fnox plugin

- jdx 本人が "I would probably advise avoiding this. fnox was built as a separate CLI for a reason." と非推奨

## 棄却: `op run` 直接利用

- op に依存する設計になり、他 backend（age 単独 / AWS / GCP / sops）への将来移行が困難
- 「fnox を統一インターフェースに固定する」という設計目的に反する

## 棄却: mise shell-aliases のみ

- 対話シェルでのみ機能、非対話 subshell には届かない（公式 docs に明記）

## 棄却: 全プロセス共通な `fnox activate --shims` のような仮想機能

- fnox 側に該当する subcommand 自体が存在しない（`fnox --help` 確認済み）

# Out of scope

以下は本タスクに含まず、別タスクで対応:

- `.npmrc` の `ignore-scripts=true` 設定（postinstall 経路の env 露出対策）
- 既存 mise `[env]` の sops+age 由来 env 漏洩問題の解消
  （mise config から sops 参照を消し fnox に統合する別タスク）
- `~/.mcp.json` の MCP server 起動を `fnox exec` 経由にする
- 他の既存 secret (`.env.enc.json` の中身など) の fnox 移行
- 複数 service account の追加（現設計は naming convention で multi-SA-ready）
- SA token のローテーション運用手順の自動化

# 拡張余地のメモ

- `op_personal` の命名規約により、後から `op_work` / `op_readonly` 等を衝突なく追加可能
- project-level の `fnox.toml` で provider override も可能（fnox の hierarchical config）
- age を keychain provider に置き換える選択肢もある（macOS Keychain で SA token を保持）
- 「数ヶ月後に見て分かる状態」担保: 真実は `_fnox_npm_shim` 内の `FNOX_WRAPPED_TOOLS` 配列ひとつ。
  追加は配列に 1 行 + install.sh 再実行のみで完結する

# 参考リンク

- fnox: https://fnox.jdx.dev/
- fnox 1Password provider: https://fnox.jdx.dev/providers/1password.html
- fnox hierarchical config: https://fnox.jdx.dev/guide/hierarchical-config.html
- fnox age provider: https://fnox.jdx.dev/providers/age.html
- mise env._.path: https://mise.jdx.dev/environments/#path
- mise shell-aliases limitations: https://mise.jdx.dev/shell-aliases.html#limitations
- 1Password service accounts: https://developer.1password.com/docs/service-accounts/
