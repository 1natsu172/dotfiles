---
title: fnox + 1Password Service Account + macOS Keychain による .npmrc registry token 管理
date: 2026-05-19
status: design
---

# 概要

`~/dotfiles/.npmrc` の Flatt Security private npm registry 用 token を、ローカル disk
の平文から取り除き、fnox + 1Password service account 経由で取得する仕組みを構築する。
SA トークンの bootstrap となる age 秘密鍵自体も disk 上に露出させず、macOS Keychain に
格納する provider chaining 構成とする。

本タスクは、今後の secret 全般を fnox + op に統一管理する基盤の最初の起点となる。

# 動機

- 現状の `.npmrc` は `//npm.flatt.tech/:_authToken=<plain>` を平文で保持。git 追跡対象
- AI ツール（Claude Code 等）の Read 系操作で容易に内容が漏出する
- AI ツール経由のマルウェアやサプライチェーン攻撃を見据え、env への露出も最小化したい
- 将来 op 以外の backend（age 単独 / AWS / GCP / sops 等）に切り替えうるので、
  **fnox を統一インターフェースとして固定**しておきたい
- 既存の mise+sops+age による env 漏出は別途解消する予定だが、新規 secret に関しては
  本タスク以降 fnox 経由で運用を開始する
- 既存の age 秘密鍵ファイル（`~/.config/mise/age.txt`）は sops のために存続するが、
  新規導入する fnox 経路では disk 上の鍵ファイル参照を作らない（鍵は keychain にコピーして利用）

# 前提検証（済）

- Claude Code は常時 sandbox enabled で運用している
- sandbox 内プロセスから macOS Keychain（securityd）にアクセスできるかを検証し、**到達可能**を確認
  （`security` CLI / `fnox get` の両方で sandbox 内から keychain item を読めた）
- よって keychain → age → op の chain は sandbox 内でもそのまま機能し、`fnox exec -- claude`
  による境界 env 注入や claude の shim 化は不要。PATH shim 構成のまま sandbox 内外で一様に動く

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
  ├─ keychain provider から age 秘密鍵を取得（OS 認証セッション経由）
  ├─ age provider がその鍵で SA token (ops_xxx) を復号
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
# OS keychain で秘密鍵を保護する provider
[providers.keychain]
type = "keychain"
service = "fnox"

# Age 暗号化で secret を保管。秘密鍵自体は keychain から取得（disk に鍵ファイルを置かない）
[providers.age]
type = "age"
recipients = ["age1<PUBLIC_KEY>"]
identity = { provider = "keychain", value = "age-key" }

# Personal vault 用の 1Password service account
[providers.op_personal]
type = "1password"
token = { secret = "OP_SA_PERSONAL" }

[secrets]
# age 秘密鍵そのもの（実体は keychain 内、ここは参照のみ）
age-key = { provider = "keychain", value = "age-key" }

# SA トークン本体は age 暗号化済み（disk 上は base64 暗号文のみ）
OP_SA_PERSONAL = { provider = "age", value = "<age-encrypted-blob>" }

# 実際に欲しい secret（op から live で fetch）
FLATT_NPM_TOKEN = { provider = "op_personal", value = "op://Personal/slhx4rnaex4ectm6hxblqyiu7y/credential" }
```

**性質**:
- このファイルには平文の秘匿値が一切含まれない（age 暗号文と op:// 参照、provider 参照のみ）
- **disk 上に age 秘密鍵ファイルを置かない**（keychain 内のみ）
- git 追跡可、リポ公開しても秘匿値は復元できない
- 命名規約 `op_personal` の suffix により、将来 `op_work` 等の追加が衝突なく可能
- 既存 `~/.config/mise/age.txt` には**触れない**（sops の参照先として継続存在）

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

> 注: 手順中に `~/.config/mise/age.txt` を **読み取り専用** で参照する箇所があるが、
> ファイル自体の削除・移動・改変は一切行わない。
> age.txt は sops のために継続存在させる。
> age.txt の整理は sops から fnox への secret 移行タスク（別タスク）で行う。

1. 1Password 管理画面で service account `fnox-personal-npm`（仮名）を作成し、
   Personal vault への read-only access に絞る
2. 発行された `ops_xxx` トークンを安全に控える
3. 既存 age 公開鍵を抽出（age.txt の `# public key: age1...` 行から、read-only）:
   ```fish
   awk '/public key:/{print $NF}' ~/.config/mise/age.txt
   # → age1xxx... が出力される
   ```
4. `~/dotfiles/.config/fnox/config.toml` の `recipients = ["age1<PUBLIC_KEY>"]` を実値に置換
5. age 秘密鍵を macOS Keychain に登録（age.txt は read-only で参照、変更しない）:
   ```fish
   awk '/^AGE-SECRET-KEY/' ~/.config/mise/age.txt | \
       fnox set age-key --provider keychain --global
   ```
   - `--global` で `~/.config/fnox/config.toml` の `[secrets]` に参照が追記される
   - 実際の鍵値は macOS Keychain の service=`fnox`, key=`age-key` 配下に格納
   - stdin pipe で渡すため shell history / ps に値が露出しない
   - 初回 fnox 起動時にダイアログが出るので「Always Allow」を選択
6. SA トークンを age 暗号化して fnox config に書き込む:
   ```fish
   # interactive prompt で値を入力（hidden input、shell history に残らない）
   fnox set OP_SA_PERSONAL --provider age --global
   # ops_xxx を貼り付ける
   ```
   または stdin で:
   ```fish
   echo "ops_xxx" | fnox set OP_SA_PERSONAL --provider age --global
   # ただし echo 経由は shell history に残るので注意。可能なら interactive prompt 推奨
   ```
   - age 暗号文が `~/.config/fnox/config.toml` の `[secrets]` に追記される
   - 暗号化に必要な情報（recipients）は config から自動で読まれる
7. `~/dotfiles/.npmrc` を placeholder 形式に書き換え（plain token を削除）
8. `~/dotfiles/.config/mise/config.toml` に `_.path = ["~/dotfiles/bin/fnox-shims"]` を追記
9. `~/dotfiles/.gitignore` を更新
10. `~/dotfiles/install.sh` の deploy ステップを追加
11. `bash ~/dotfiles/install.sh` を実行
12. 新しいシェルを開いて検証ステップへ

# セキュリティ特性

## 守れる

- disk 上に平文 token も age 秘密鍵も存在しない（`.npmrc` は placeholder、`fnox.toml` は
  age 暗号文 + op:// 参照 + keychain 参照のみ）
- age 秘密鍵は macOS Keychain 内に格納（Apple Silicon では Secure Enclave で保護）
- 親シェル env に token が乗らない（fnox exec で wrap した子プロセスにのみ注入）
- `env` / `printenv` / `set` / `/proc/self/environ` 等で読まれない
- AI ツールが `bash -c 'env | grep TOKEN'` を実行しても、親シェル env を継承するだけで token は無い
- service account なので op CLI が個人セッションに依存せず、TouchID プロンプトが運用中に出ない
- リポ公開しても秘匿値は復元できない（keychain access が無い限り）
- 他アプリケーション（postinstall script、悪意あるソフト等）が同じ keychain item に
  アクセスしようとすると OS が個別にプロンプトを出す or 拒否する
- 常時 sandbox 運用の Claude Code 内でも、keychain アクセスが通ることを検証済み（前提検証参照）

## 守れない（明示的に受容するリスク）

- npm 子プロセスとその子孫プロセス（`package.json` scripts, postinstall hook 等）の env には
  FLATT_NPM_TOKEN が乗る。npm が `.npmrc` の `${VAR}` を展開するため原理的に避けられない
- 対策（`.npmrc` に `ignore-scripts=true` を入れる等）は本タスク範囲外、別タスクで検討
- 既存の mise activate + sops+age 由来の env 漏出は別タスクで対応予定。
  本タスクは新規 secret 経路の構築に集中する
- 既存 `~/.config/mise/age.txt` は本タスクでは存続。disk 上の age 鍵ファイル除去は sops 移行と
  セットで別タスクで対応

# 検証手順

実装後に新しいシェルを開いて以下を確認:

1. **keychain アクセス確認**:
   ```
   fnox get age-key
   ```
   → 初回ダイアログで「Always Allow」を選び、`AGE-SECRET-KEY-...` が返ること
2. **age 復号確認**:
   ```
   fnox get OP_SA_PERSONAL
   ```
   → `ops_xxx` で始まる文字列が返ること（keychain → age 経路の連鎖が機能）
3. **op 連携確認**:
   ```
   fnox get FLATT_NPM_TOKEN
   ```
   → `tg_anon_xxx` で始まる npm token が返ること（keychain → age → op の連鎖が機能）
4. **PATH 順序確認**:
   ```
   which npm
   ```
   → `~/dotfiles/bin/fnox-shims/npm` を指すこと
5. **env 隔離確認**:
   ```
   env | grep FLATT_NPM_TOKEN     # 何も出ない
   set | grep FLATT_NPM_TOKEN     # 何も出ない
   env | grep AGE_SECRET          # 何も出ない
   ```
6. **npm 子プロセス内で展開されるか**:
   ```
   npm config get //npm.flatt.tech/:_authToken
   ```
   → token 値が返る（npm 子プロセス内で env から `${VAR}` が展開される）
7. **registry 認証成功**:
   ```
   npm whoami --registry https://npm.flatt.tech/
   ```
   → 認証成功
8. **AI ツール経路（非対話 bash サブシェル）確認**:
   ```
   bash -c 'env | grep FLATT_NPM_TOKEN'    # 何も出ない
   bash -c 'npm whoami --registry https://npm.flatt.tech/'   # 認証成功
   ```
9. **age.txt 不変確認**:
   ```
   ls -la ~/.config/mise/age.txt
   shasum ~/.config/mise/age.txt
   ```
   → bootstrap 前後で mtime / sha が一致（read-only 参照のみだったこと）

# トレードオフと棄却した代替

## 棄却: `fnox activate` の shell integration

- 親シェル env に `set -gx` で export される（`fnox activate fish` の hook-env 出力で実測確認済み）
- AI ツールが `env` で容易に読める、サブプロセス継承で漏れる → 脅威モデル違反

## 棄却: `fnox exec -- claude` で AI ツールごと wrap（境界 env 注入）

- sandbox 内 keychain アクセスが不可だった場合の回避策候補だったが、前提検証で sandbox 内
  keychain アクセスが可能と判明したため不要
- この方式は claude プロセス自身の env に secret が乗り、claude の introspection / 子プロセス継承
  経由で漏れ面が広がるため、可能なら避けるべき構成

## 棄却: desktop+biometric via fnox onepassword provider (token なしモード)

- 実装は対応する（op CLI への shell-out 時に `OP_SERVICE_ACCOUNT_TOKEN` が optional）
- ただし fnox docs が明示的に推奨していない経路。将来仕様が固まる可能性あり
- 個人プランでも SA が作成可能と判明したため、docs 推奨どおりの SA 経路を採用

## 棄却: age 秘密鍵を disk ファイル（`key_file` 指定）で参照

- `~/.config/mise/age.txt` のような disk 上ファイルを fnox から直接読む構成
- 平文の秘密鍵ファイルが disk 上に存在することになり、AI ツール経由のファイル読み取りに
  耐性が無い（既存 sops の構成と同じ問題）
- keychain 経由なら鍵自体が OS 暗号化ストレージ内に隔離され、第三者プロセスからの
  アクセスに OS 認証が要求される

## 棄却: 各 secret を直接 keychain に格納する Option A 案

- `[providers.keychain]` を直接参照し、`OP_SA_PERSONAL = { provider = "keychain", value = "..." }`
  とする最小構成
- 構造はシンプルだが、secret 数が増えると **keychain への個別登録作業が secret 数だけ発生**する
- 新マシン setup でも同様に N 回繰り返し必要
- 一方 age 層を挟むと、追加 secret は `fnox set X "v" --provider age` だけで完結
  （keychain アクセスは age 鍵の 1 回のみで、以後 disk 上 fnox.toml に暗号文を追記する流れ）
- 「複数 secret を扱う基盤」という設計目的に対して Option A はスケールしないため棄却

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
- **既存 `~/.config/mise/age.txt` の整理（削除 / 移動 / バックアップ化）**。
  本タスクでは age.txt を一切変更しない（read-only 参照のみ）。
  age.txt の処分は sops 移行タスクと同時に検討する
- `~/.mcp.json` の MCP server 起動を `fnox exec` 経由にする
- 他の既存 secret (`.env.enc.json` の中身など) の fnox 移行
- 複数 service account の追加（現設計は naming convention で multi-SA-ready）
- SA token のローテーション運用手順の自動化

# 拡張余地のメモ

- `op_personal` の命名規約により、後から `op_work` / `op_readonly` 等を衝突なく追加可能
- project-level の `fnox.toml` で provider override も可能（fnox の hierarchical config）
- 新たに age 暗号化したい secret は `fnox set X "v" --provider age --global` だけで追加可能
  （keychain アクセスは age 鍵 1 回限り、以後は fnox.toml 内の暗号文として追記される）
- 「数ヶ月後に見て分かる状態」担保: 真実は `_fnox_npm_shim` 内の `FNOX_WRAPPED_TOOLS` 配列と
  `~/.config/fnox/config.toml` の `[providers]` / `[secrets]`。
  追加は配列に 1 行 + install.sh 再実行 / `fnox set` 1 回で完結する

# 参考リンク

- fnox: https://fnox.jdx.dev/
- fnox 1Password provider: https://fnox.jdx.dev/providers/1password.html
- fnox age provider: https://fnox.jdx.dev/providers/age.html
- fnox keychain provider: https://fnox.jdx.dev/providers/keychain.html
- fnox hierarchical config: https://fnox.jdx.dev/guide/hierarchical-config.html
- mise env._.path: https://mise.jdx.dev/environments/#path
- mise shell-aliases limitations: https://mise.jdx.dev/shell-aliases.html#limitations
- 1Password service accounts: https://developer.1password.com/docs/service-accounts/
