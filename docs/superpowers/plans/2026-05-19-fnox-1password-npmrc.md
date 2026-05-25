# fnox + 1Password + Keychain による .npmrc token 管理 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `.npmrc` の Flatt registry token を平文から取り除き、fnox（keychain → age → 1Password SA chain）経由で npm/yarn/bun 系の子プロセスにのみ注入する。

**Architecture:** age 秘密鍵を macOS Keychain に格納し、それで 1Password SA token を復号、SA token で op CLI を叩いて Flatt token を取得。`~/dotfiles/bin/fnox-shims/` 配下の PATH shim が npm 系コマンドを `fnox exec -- mise x -- <tool>` でラップし、token を親シェル env に出さず子プロセスにのみ渡す。

**Tech Stack:** fnox 1.25.0, 1Password CLI (op) 2.34.0, age 1.3.1, mise, fish/bash/zsh, macOS Keychain

---

## 前提と進め方（必読）

このタスクは **秘匿情報の実値を扱う工程（USER 専任）** と **ファイル/設定の編集工程（AGENT 可）** が混在する。各タスクに `[AGENT]` / `[USER]` / `[VERIFY]` のラベルを付ける。

- `[AGENT]`: Claude が実施可能（ファイル作成・編集、symlink 配置等）
- `[USER]`: ユーザーが手で行う。SA token / age 秘密鍵などの実値を扱うため Claude にやらせない
- `[VERIFY]`: 検証コマンド。秘匿値を端末に出さない形（prefix 判定 / 終了コード）で確認する

**秘匿値の扱い原則:**
- Claude は `~/.config/mise/age.txt` を**読まない**（私有鍵が同居するため）。公開鍵が必要なときは USER が `awk` で抽出して値を渡す
- `fnox get` の検証は値を素で print せず `| grep -q '^prefix'` 等で判定する

**実装順序の鉄則（npm を壊さないため）:**
`.npmrc` の placeholder 化（Task 7）は、**fnox が FLATT_NPM_TOKEN を解決できると確認できた後（Task 4 VERIFY 通過後）かつ shim が PATH に乗った後（Task 5-6 完了後）**に行う。順序を守らないと npm install が 401 で壊れる。

**コミット方針:**
ユーザーの運用ルール上、コミットは明示許可があるまで行わない。各タスク末尾の「コミット候補」は、実行時にユーザーへ確認してから実施する。

---

## ファイル構成マップ

| パス | 区分 | 責務 |
|---|---|---|
| `~/dotfiles/bin/_fnox_npm_shim` | 新規 (AGENT) | tool 名判定 + `fnox exec -- mise x` ディスパッチ + `--deploy` で symlink 生成 |
| `~/dotfiles/bin/fnox-shims/<tool>` | 生成物 (deploy) | `../_fnox_npm_shim` への相対 symlink。gitignore 対象 |
| `~/dotfiles/.config/fnox/config.toml` | 新規 (AGENT 雛形 + USER 値投入) | provider chain 定義 + secret 参照。平文値は持たない |
| `~/dotfiles/.config/mise/config.toml` | 修正 (AGENT) | `[env]` に `_.path` を 1 行追加 |
| `~/dotfiles/.npmrc` | 修正 (AGENT) | token を `${FLATT_NPM_TOKEN}` placeholder 化 |
| `~/dotfiles/.gitignore` | 修正 (AGENT) | `!.config/fnox` と `bin/fnox-shims/` を追加 |
| `~/dotfiles/install.sh` | 修正 (AGENT) | deploy ステップ追加 |
| macOS Keychain (service=`fnox`) | USER | age 秘密鍵を格納 |
| 1Password Personal vault SA | USER | fnox が op を叩くための service account |

---

## Task 1: dispatcher スクリプト作成と deploy 機構の検証 `[AGENT]`

**Files:**
- Create: `~/dotfiles/bin/_fnox_npm_shim`

- [ ] **Step 1: dispatcher スクリプトを作成**

`~/dotfiles/bin/_fnox_npm_shim` を以下の内容で作成:

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

- [ ] **Step 2: 実行権限を付与**

Run: `chmod +x ~/dotfiles/bin/_fnox_npm_shim`

- [ ] **Step 3: deploy が symlink を正しく生成するか検証**

Run: `~/dotfiles/bin/_fnox_npm_shim --deploy`
Expected: `npm`, `npx`, `yarn`, `bun`, `bunx`, `pnpm`, `pnpx` の symlink 作成ログが出る

- [ ] **Step 4: symlink の中身を確認**

Run: `ls -la ~/dotfiles/bin/fnox-shims/`
Expected: 各 tool が `../_fnox_npm_shim` を指す symlink になっている

- [ ] **Step 5: deploy の冪等性を確認**

Run: `~/dotfiles/bin/_fnox_npm_shim --deploy && ls -la ~/dotfiles/bin/fnox-shims/`
Expected: エラーなく再実行でき、symlink 構成は変わらない

**コミット候補（要ユーザー承認）:**
```bash
git add bin/_fnox_npm_shim
git commit -m "feat(bin): add fnox exec shim dispatcher for npm-family tools"
```
（`bin/fnox-shims/` は Task 5 で gitignore するまでステージしない）

---

## Task 2: fnox config 雛形の作成 `[AGENT]`

**Files:**
- Create: `~/dotfiles/.config/fnox/config.toml`

- [ ] **Step 1: config ディレクトリと雛形を作成**

`~/dotfiles/.config/fnox/config.toml` を以下で作成（`recipients` と `OP_SA_PERSONAL` の値は Task 3-4 で投入されるため placeholder）:

```toml
# OS keychain で秘密鍵を保護する provider
[providers.keychain]
type = "keychain"
service = "fnox"

# Age 暗号化で secret を保管。秘密鍵は keychain から取得（disk に鍵ファイルを置かない）
[providers.age]
type = "age"
recipients = ["age1REPLACE_WITH_PUBLIC_KEY"]
identity = { provider = "keychain", value = "age-key" }

# Personal vault 用の 1Password service account
[providers.op_personal]
type = "1password"
token = { secret = "OP_SA_PERSONAL" }

[secrets]
# age 秘密鍵そのもの（実体は keychain 内、ここは参照のみ）
age-key = { provider = "keychain", value = "age-key" }

# 実際に欲しい secret（op から live で fetch）
FLATT_NPM_TOKEN = { provider = "op_personal", value = "op://Personal/slhx4rnaex4ectm6hxblqyiu7y/credential" }
```

注: `OP_SA_PERSONAL` の `[secrets]` 行はここに書かない。Task 3 の `fnox set ... --global` が自動追記する。

- [ ] **Step 2: ファイルが正しい TOML か確認**

Run: `fnox -c ~/dotfiles/.config/fnox/config.toml provider list 2>&1 || true`
Expected: provider 一覧（keychain / age / op_personal）が出る。secret 解決エラーが出ても TOML パース自体が通っていれば OK

**コミット候補:** Task 4 完了後にまとめて（recipient 投入後）。

---

## Task 3: 秘匿値の bootstrap `[USER]`

> このタスクは実値（SA token / age 秘密鍵）を扱うため **ユーザーが手で実施**する。
> `~/.config/mise/age.txt` は **read-only 参照のみ**。削除・移動・改変しない。

- [ ] **Step 1: 1Password service account を作成**

1Password 管理画面で service account（例: `fnox-personal-npm`）を作成し、**Personal vault への read-only access** に絞る。発行された `ops_xxx` トークンを控える。

- [ ] **Step 2: age 公開鍵を抽出して Claude に渡す**

Run（fish, read-only）: `awk '/public key:/{print $NF}' ~/.config/mise/age.txt`
出力された `age1xxx...` を Task 4 で config に投入するため控える / Claude に伝える。
（公開鍵は秘匿情報ではないため共有可）

- [ ] **Step 3: age 秘密鍵を Keychain に登録**

Run（fish）:
```fish
awk '/^AGE-SECRET-KEY/' ~/.config/mise/age.txt | \
    fnox set age-key --provider keychain --global
```
- 初回 fnox 起動時の Keychain ダイアログで「Always Allow」を選ぶ
- `~/.config/fnox/config.toml` の `[secrets]` に `age-key` 参照が追記される（実体は Keychain）
- stdin pipe なので値は shell history / ps に残らない

- [ ] **Step 4: SA token を age 暗号化して config に格納**

Run（fish, interactive prompt で hidden input）:
```fish
fnox set OP_SA_PERSONAL --provider age --global
# プロンプトに ops_xxx を貼り付け（画面に出ない）
```
- `~/.config/fnox/config.toml` の `[secrets]` に age 暗号文が追記される

---

## Task 4: recipient 投入と fnox 解決チェーンの検証 `[AGENT]` + `[VERIFY]`

**Files:**
- Modify: `~/dotfiles/.config/fnox/config.toml`（`recipients` の placeholder を実値に）

- [ ] **Step 1: recipient を実際の公開鍵に置換 `[AGENT]`**

`~/dotfiles/.config/fnox/config.toml` の
`recipients = ["age1REPLACE_WITH_PUBLIC_KEY"]`
を Task 3-Step2 で得た実値 `recipients = ["age1xxx..."]` に置換。

- [ ] **Step 2: keychain → age 鍵取得の確認 `[VERIFY]`**

Run: `fnox -c ~/.config/fnox/config.toml get age-key | grep -q '^AGE-SECRET-KEY' && echo OK || echo NG`
Expected: `OK`（値は print しない）

- [ ] **Step 3: age 復号で SA token が取れる確認 `[VERIFY]`**

Run: `fnox -c ~/.config/fnox/config.toml get OP_SA_PERSONAL | grep -q '^ops_' && echo OK || echo NG`
Expected: `OK`

- [ ] **Step 4: op 連携で Flatt token が取れる確認 `[VERIFY]`**

Run: `fnox -c ~/.config/fnox/config.toml get FLATT_NPM_TOKEN | grep -q '^tg_' && echo OK || echo NG`
Expected: `OK`（keychain → age → op の chain 全体が機能）

> ここが通らなければ Task 7（.npmrc 書き換え）に進まない。npm が壊れる。

**コミット候補（要ユーザー承認）:**
```bash
git add .config/fnox/config.toml .gitignore   # .gitignore は Task 5 で更新後にまとめる手もある
git commit -m "feat(fnox): add keychain->age->1password secret chain config"
```
（暗号文と op:// 参照のみで平文秘匿値は含まれないことを確認してからコミット）

---

## Task 5: mise PATH 投入と .gitignore 更新 `[AGENT]`

**Files:**
- Modify: `~/dotfiles/.config/mise/config.toml`
- Modify: `~/dotfiles/.gitignore`

- [ ] **Step 1: mise config に `_.path` を追加**

`~/dotfiles/.config/mise/config.toml` の `[env]` セクションに 1 行追加（既存行は残す）:

```toml
[env]
SOPS_AGE_KEY_FILE = "{{config_root}}/.config/mise/age.txt"
_.file = { path = "~/dotfiles/.env.enc.json", redact = true }
_.path = ["~/dotfiles/bin/fnox-shims"]
```

- [ ] **Step 2: .gitignore に 2 行追加**

`~/dotfiles/.gitignore` に追記:

```gitignore
# fnox global config はトラッキング対象
!.config/fnox

# 自動生成 shim symlink は管理外
bin/fnox-shims/
```

- [ ] **Step 3: fnox config が追跡対象、shims が無視対象であることを確認 `[VERIFY]`**

Run:
```bash
cd ~/dotfiles
git check-ignore -v .config/fnox/config.toml; echo "exit=$?"   # 追跡対象なら exit=1（無視されない）
git check-ignore -v bin/fnox-shims/npm; echo "exit=$?"          # 無視対象なら exit=0
```
Expected: `config.toml` は無視されない（exit=1）、`fnox-shims/npm` は無視される（exit=0）

**コミット候補（要ユーザー承認）:**
```bash
git add .config/mise/config.toml .gitignore
git commit -m "feat(mise): prepend fnox-shims to PATH via env._.path"
```

---

## Task 6: install.sh に deploy ステップ追加 `[AGENT]`

**Files:**
- Modify: `~/dotfiles/install.sh`

- [ ] **Step 1: install.sh の deploy ステップを追記**

`~/dotfiles/install.sh` の `echo "...Deploy dotfiles complete..."` 行の**前**に以下を挿入:

```bash
# fnox shim symlinks の deploy（idempotent）
if [[ -x "${DOT_DIRECTORY}/bin/_fnox_npm_shim" ]]; then
  "${DOT_DIRECTORY}/bin/_fnox_npm_shim" --deploy
fi
```

- [ ] **Step 2: install.sh を実行して全体が通るか確認 `[VERIFY]`**

Run: `bash ~/dotfiles/install.sh`
Expected: 既存の symlink 配置 + fnox-shims deploy が完走、エラーなし

- [ ] **Step 3: PATH 投入の確認（新しい fish を開いて） `[VERIFY]`**

新しい fish セッションで Run: `which npm`
Expected: `~/dotfiles/bin/fnox-shims/npm` を指す
（もし mise shims が先に来ていたら spec の検証ポイント参照。`_.path` の prepend 順を確認）

**コミット候補（要ユーザー承認）:**
```bash
git add install.sh
git commit -m "feat(install): deploy fnox shim symlinks on setup"
```

---

## Task 7: .npmrc の placeholder 化 `[AGENT]`（必ず Task 4 VERIFY 通過後）

**Files:**
- Modify: `~/dotfiles/.npmrc`

- [ ] **Step 1: .npmrc の token 行を placeholder に置換**

`~/dotfiles/.npmrc` を以下の内容にする（平文 `tg_anon_xxx` を削除）:

```
registry=https://npm.flatt.tech/
//npm.flatt.tech/:_authToken=${FLATT_NPM_TOKEN}
```

- [ ] **Step 2: 平文 token が消えたことを確認 `[VERIFY]`**

Run: `grep -c 'tg_anon' ~/dotfiles/.npmrc; echo "exit=$?"`
Expected: `0`（マッチ無し）

- [ ] **Step 3: placeholder 形式になったことを確認 `[VERIFY]`**

Run: `grep -q 'authToken=${FLATT_NPM_TOKEN}' ~/dotfiles/.npmrc && echo OK || echo NG`
Expected: `OK`

**コミット候補（要ユーザー承認）:**
```bash
git add .npmrc
git commit -m "feat(npmrc): replace plaintext registry token with fnox env placeholder"
```

---

## Task 8: エンドツーエンド検証 `[VERIFY]`（新しいシェルで）

新しい fish セッションを開いて以下を順に確認:

- [ ] **Step 1: PATH 順序**

Run: `which npm`
Expected: `~/dotfiles/bin/fnox-shims/npm`

- [ ] **Step 2: 親シェル env に token が漏れていない**

Run: `env | grep -E 'FLATT_NPM_TOKEN|AGE-SECRET' ; echo "exit=$?"`
Expected: 何も出ない（exit=1）

- [ ] **Step 3: npm 子プロセス内で展開される**

Run: `npm config get //npm.flatt.tech/:_authToken | grep -q '^tg_' && echo OK || echo NG`
Expected: `OK`（shim → fnox exec で env 注入され npm が `${VAR}` 展開）

- [ ] **Step 4: registry 認証成功**

Run: `npm whoami --registry https://npm.flatt.tech/`
Expected: 認証ユーザー名が返る（401 でない）

- [ ] **Step 5: AI ツール経路（非対話 bash）**

Run:
```bash
bash -c 'env | grep FLATT_NPM_TOKEN; echo "leak_exit=$?"'
bash -c 'npm whoami --registry https://npm.flatt.tech/'
```
Expected: 1 行目 leak なし（leak_exit=1）、2 行目 認証成功

- [ ] **Step 6: Claude Code（sandbox）経路**

Claude Code の Bash tool で Run: `npm whoami --registry https://npm.flatt.tech/`
Expected: 認証成功（sandbox 内 keychain → age → op chain が機能）

- [ ] **Step 7: age.txt 不変確認**

Run: `ls -la ~/.config/mise/age.txt; shasum ~/.config/mise/age.txt`
Expected: 本タスク開始前と mtime / sha が一致（read-only 参照のみだった）

---

## Task 9: 旧トークンのローテーション `[USER]`（セキュリティ必須）

> 現行 `tg_anon_xxx` は git 履歴（9e8f86d 他）経由で GitHub
> （`github.com/1natsu172/dotfiles`）に push 済み ＝ **既に露出している**。
> 移行で .npmrc から消しても履歴には残るため、**トークン自体をローテーションする**。

- [ ] **Step 1: Flatt 側で新しい registry token を発行**

Flatt Security の管理画面で npm registry token を再発行（旧トークンは revoke）。

- [ ] **Step 2: 1Password の item を新トークンで更新**

`op://Personal/slhx4rnaex4ectm6hxblqyiu7y/credential` の値を新トークンに更新。
fnox は live fetch なので config 変更不要、次回 `npm` 実行から自動で新トークンが使われる。

- [ ] **Step 3: 反映確認 `[VERIFY]`**

Run: `npm whoami --registry https://npm.flatt.tech/`
Expected: 新トークンで認証成功

> 補足: git 履歴からの完全除去（filter-repo / BFG）は破壊的かつ別タスク。
> ローテーションで旧トークンを無効化すれば、履歴に残っても実害は消える。

---

## Self-Review（spec カバレッジ）

- spec A（fnox config）→ Task 2, 4 ✅
- spec B（dispatcher）→ Task 1 ✅
- spec C（shim 配置）→ Task 1, 6 ✅
- spec D（mise PATH）→ Task 5 ✅
- spec E（.npmrc）→ Task 7 ✅
- spec F（.gitignore）→ Task 5 ✅
- spec G（install.sh）→ Task 6 ✅
- spec H（bootstrap）→ Task 3 ✅
- spec 検証手順 → Task 8 ✅
- spec 受容リスク（postinstall, sops, age.txt 存続）→ Out of scope として spec に記載済み、本計画では age.txt を Task 3/8 で read-only 厳守 ✅
- 追加: git 履歴の token 露出 → Task 9（ローテーション）で対応 ✅
