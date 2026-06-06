# fnox + 1Password + Keychain による .npmrc token 管理 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `.npmrc` の Flatt registry token を平文から取り除き、fnox（keychain → 1Password SA chain）経由で npm/yarn/bun 系の子プロセスにのみ注入する。

**Architecture:** SA token を macOS Keychain に格納し、fnox keychain provider で取得して 1Password provider の認証に渡す。op_personal_develop が op CLI 経由で Flatt token を live fetch。`~/dotfiles/bin/fnox-shims/` 配下の PATH shim が npm 系コマンドを `fnox exec -- $(mise which <tool>)` でラップし、token を親シェル env に出さず子プロセスにのみ渡す。

> 補足: 本来は keychain → age → op の 3 段 chain が理想（fnox docs 推奨パターン）だが、
> 実機 1.25.1 で age provider の `identity` 未実装のため、暫定で age 層を省く。
> fnox 側の実装追従後に再導入する（spec 冒頭の「暫定構成について」参照）。

**Tech Stack:** fnox 1.25.1, 1Password CLI (op) 2.34.0, mise, fish/bash/zsh, macOS Keychain

---

## 前提と進め方（必読）

このタスクは **秘匿情報の実値を扱う工程（USER 専任）** と **ファイル/設定の編集工程（AGENT 可）** が混在する。各タスクに `[AGENT]` / `[USER]` / `[VERIFY]` のラベルを付ける。

- `[AGENT]`: Claude が実施可能（ファイル作成・編集、symlink 配置等）
- `[USER]`: ユーザーが手で行う。SA token などの実値を扱うため Claude にやらせない
- `[VERIFY]`: 検証コマンド。秘匿値を端末に出さない形（prefix 判定 / 終了コード）で確認する

**秘匿値の扱い原則:**
- Claude は `~/.config/mise/age.txt` を**読まない、触らない**（本タスクでは age を使わないため、参照すらしない）
- `fnox get` の検証は値を素で print せず `| grep -q '^prefix'` 等で判定する

**実装順序の鉄則（npm を壊さないため）:**
`.npmrc` の placeholder 化（Task 6）は、**fnox が FLATT_NPM_TOKEN を解決できると確認できた後（Task 4 VERIFY 通過後）かつ shim が PATH に乗った後（Task 5 完了後）**に行う。順序を守らないと npm install が 401 で壊れる。

**コミット方針:**
ユーザーの運用ルール上、コミットは明示許可があるまで行わない。各タスク末尾の「コミット候補」は、実行時にユーザーへ確認してから実施する。

---

## ファイル構成マップ

| パス | 区分 | 責務 |
|---|---|---|
| `~/dotfiles/bin/_fnox_npm_shim` | 新規 (AGENT) | tool 名判定 + `fnox exec -- $(mise which <tool>)` ディスパッチ + `--deploy` で symlink 生成 |
| `~/dotfiles/bin/fnox-shims/<tool>` | 生成物 (deploy) | `../_fnox_npm_shim` への相対 symlink。gitignore 対象 |
| `~/dotfiles/.config/fnox/config.toml` | 新規 (AGENT 雛形 + USER 値投入) | keychain + op_personal_develop provider と FLATT_NPM_TOKEN の op:// 参照。平文値は持たない |
| `~/dotfiles/.config/mise/config.toml` | 修正 (AGENT) | `[env]` に `_.path` を 1 行追加 |
| `~/dotfiles/.npmrc` | 修正 (AGENT) | token を `${FLATT_NPM_TOKEN}` placeholder 化 |
| `~/dotfiles/.gitignore` | 修正 (AGENT) | `!.config/fnox` と `bin/fnox-shims/` を追加 |
| `~/dotfiles/install.sh` | 修正 (AGENT) | deploy ステップ追加 |
| macOS Keychain (service=`fnox`, key=`OP_SA_PERSONAL_DEVELOP`) | USER | SA token を格納 |
| 1Password Personal vault SA | USER | fnox が op を叩くための service account |

---

## Task 1: dispatcher スクリプト作成と deploy 機構の検証 `[AGENT]`

**Files:**
- Create: `~/dotfiles/bin/_fnox_npm_shim`

- [x] **Step 1: dispatcher スクリプトを作成**

`~/dotfiles/bin/_fnox_npm_shim` を以下の内容で作成:

```bash
#!/usr/bin/env bash
# fnox exec で wrap して呼ぶ tool 群の dispatcher。
# 起動時の $0 ファイル名から tool 名を判定し、mise which で実体パスを解決して呼ぶ。
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
# `mise which` で実体バイナリの絶対パスを解決してから fnox exec で起動する。
# - `mise x -- <tool>` は PATH 検索が走り、PATH 先頭の本ディレクトリ
#   (fnox-shims/<tool>) を再帰的に拾って無限ループするため使わない。
# - パスをハードコードもしない。`mise which` が現在の mise 設定(プロジェクト別
#   バージョン含む)に基づき実体パスを返すので、インストール構造の変化に追従する。
tool="${0##*/}"
real="$(mise which "${tool}")"
exec fnox exec -- "${real}" "$@"
```

- [x] **Step 2: 実行権限を付与**

Run: `chmod +x ~/dotfiles/bin/_fnox_npm_shim`

- [x] **Step 3: deploy が symlink を正しく生成するか検証**

Run: `~/dotfiles/bin/_fnox_npm_shim --deploy`
Expected: `npm`, `npx`, `yarn`, `bun`, `bunx`, `pnpm`, `pnpx` の symlink 作成ログが出る

- [x] **Step 4: symlink の中身を確認**

Run: `ls -la ~/dotfiles/bin/fnox-shims/`
Expected: 各 tool が `../_fnox_npm_shim` を指す symlink になっている

- [x] **Step 5: deploy の冪等性を確認**

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

- [ ] **Step 1: config を作成**

`~/dotfiles/.config/fnox/config.toml` を以下の内容で作成:

```toml
# OS keychain で秘匿値を保護する provider
[providers.keychain]
type = "keychain"
service = "fnox"

# Personal vault 用の 1Password service account
[providers.op_personal_develop]
type = "1password"
token = { secret = "OP_SA_PERSONAL_DEVELOP" }

[secrets]
# SA トークン本体（実体は macOS Keychain 内、ここは参照のみ）
OP_SA_PERSONAL_DEVELOP = { provider = "keychain", value = "OP_SA_PERSONAL_DEVELOP" }

# 実際に欲しい secret（op から live で fetch）
FLATT_NPM_TOKEN = { provider = "op_personal_develop", value = "op://personal-develop/ut45f4nuxkaoquisyrolp2vqqe/credential" }
```

> 注: Task 3 で `fnox set OP_SA_PERSONAL_DEVELOP --provider keychain --global` を実行すると、
> 既にここで宣言した `OP_SA_PERSONAL_DEVELOP = { ... }` の参照と整合した状態で keychain item が作成される。
> fnox は同名の secret が `[secrets]` に既存の場合、provider 設定を尊重して値だけ keychain に書き込む。

- [ ] **Step 2: TOML パースが通ることを確認 `[VERIFY]`**

Run: `fnox -c ~/dotfiles/.config/fnox/config.toml provider list 2>&1 | head`
Expected: provider 一覧（keychain / op_personal_develop）が出る。
（secret 解決はまだだが、TOML パース自体が通っていればこの段階では OK）

**コミット候補:** Task 4 完了後にまとめて（chain 動作確認後）。

---

## Task 3: 秘匿値 bootstrap `[USER]`

> このタスクは実値（SA token）を扱うため **ユーザーが手で実施**する。
> 本タスクでは age を使わないため、`~/.config/mise/age.txt` には**触れない**。

- [ ] **Step 1: 1Password service account を作成**

1Password 管理画面で service account（例: `fnox-personal-npm`）を作成し、**Personal vault への read-only access** に絞る。発行された `ops_xxx` トークンを控える。

- [ ] **Step 2: SA token を Keychain に登録**

Run（fish）:
```fish
echo "ops_xxx" | fnox set OP_SA_PERSONAL_DEVELOP --provider keychain --global
```
- `ops_xxx` は実値に置き換える
- `--global` で `~/.config/fnox/config.toml` の `[secrets]` の参照と整合
- 実体は macOS Keychain の service=`fnox`, key=`OP_SA_PERSONAL_DEVELOP` 配下に格納
- stdin pipe で渡すため shell history / ps に値が露出しない
- 初回 fnox 起動時の Keychain ダイアログで「Always Allow」を選ぶ

別法（interactive prompt、hidden input、より安全）:
```fish
fnox set OP_SA_PERSONAL_DEVELOP --provider keychain --global
# プロンプトに ops_xxx を貼り付け（画面に出ない）
```

---

## Task 4: fnox chain 解決の検証 `[VERIFY]`

- [ ] **Step 1: keychain → SA token 取得の確認**

Run: `fnox get OP_SA_PERSONAL_DEVELOP | grep -q '^ops_' && echo OK || echo NG`
Expected: `OK`（値は print しない）

- [ ] **Step 2: keychain → op_personal_develop 連携で Flatt token が取れる確認**

Run: `fnox get FLATT_NPM_TOKEN | grep -q '^tg_' && echo OK || echo NG`
Expected: `OK`（chain 全体が機能）

> ここが通らなければ Task 6（.npmrc 書き換え）に進まない。npm が壊れる。

**コミット候補（要ユーザー承認）:**
```bash
git add .config/fnox/config.toml
git commit -m "feat(fnox): add keychain->1password secret chain config"
```
（fnox.toml には provider 参照と op:// URI のみで平文秘匿値が無いことを確認してからコミット）

---

## Task 5: mise PATH 投入と .gitignore + install.sh `[AGENT]`

**Files:**
- Modify: `~/dotfiles/.config/mise/config.toml`
- Modify: `~/dotfiles/.gitignore`
- Modify: `~/dotfiles/install.sh`

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

- [ ] **Step 3: install.sh に deploy ステップを追加**

`~/dotfiles/install.sh` の `echo "...Deploy dotfiles complete..."` 行の**前**に以下を挿入:

```bash
# fnox shim symlinks の deploy（idempotent）
if [[ -x "${DOT_DIRECTORY}/bin/_fnox_npm_shim" ]]; then
  "${DOT_DIRECTORY}/bin/_fnox_npm_shim" --deploy
fi
```

- [ ] **Step 4: gitignore の効きを確認 `[VERIFY]`**

Run:
```bash
cd ~/dotfiles
git check-ignore -v .config/fnox/config.toml; echo "exit=$?"   # 追跡対象なら exit=1
git check-ignore -v bin/fnox-shims/npm; echo "exit=$?"          # 無視対象なら exit=0
```
Expected: `config.toml` は無視されない（exit=1）、`fnox-shims/npm` は無視される（exit=0）

- [ ] **Step 5: install.sh を実行 `[VERIFY]`**

Run: `bash ~/dotfiles/install.sh`
Expected: 既存の symlink 配置 + fnox-shims deploy が完走、エラーなし

- [ ] **Step 6: PATH に shim が乗っているか確認（新しい fish セッションで） `[VERIFY]`**

新しい fish を開いて Run: `which npm`
Expected: `~/dotfiles/bin/fnox-shims/npm` を指す
（もし mise shims が先に来ていたら spec の検証ポイント参照）

**コミット候補（要ユーザー承認）:**
```bash
git add .config/mise/config.toml .gitignore install.sh
git commit -m "feat(mise,install): wire fnox shims into PATH and install flow"
```

---

## Task 6: .npmrc の placeholder 化 `[AGENT]`（必ず Task 4 VERIFY 通過後）

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

## Task 7: エンドツーエンド検証 `[VERIFY]`（新しいシェルで）

新しい fish セッションを開いて以下を順に確認:

- [ ] **Step 1: PATH 順序**

Run: `which npm`
Expected: `~/dotfiles/bin/fnox-shims/npm`

- [ ] **Step 2: 親シェル env に secret が漏れていない**

Run: `env | grep -E 'FLATT_NPM_TOKEN|OP_SA_PERSONAL_DEVELOP' ; echo "exit=$?"`
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
bash -c 'env | grep -E "FLATT_NPM_TOKEN|OP_SA_PERSONAL_DEVELOP"; echo "leak_exit=$?"'
bash -c 'npm whoami --registry https://npm.flatt.tech/'
```
Expected: 1 行目 leak なし（leak_exit=1）、2 行目 認証成功

- [ ] **Step 6: Claude Code（sandbox）経路**

Claude Code の Bash tool で Run: `npm whoami --registry https://npm.flatt.tech/`
Expected: 認証成功（sandbox 内 keychain → op chain が機能）

- [ ] **Step 7: age.txt 不変確認**

Run: `ls -la ~/.config/mise/age.txt; shasum ~/.config/mise/age.txt`
Expected: 本タスク開始前と mtime / sha が一致（一切触らなかったこと）

---

## Task 7.5: fish の corepack エイリアスに token 注入 `[USER]`（E2E で判明したバグ修正）

> **背景**: Task 7 の E2E で「bash/zsh は PONG だが fish は 401」を観測。根本原因は
> `config.fish` の `alias npm="corepack npm"` 群が fish で PATH 上の fnox-shim を
> shadow し、fnox exec を bypass していたこと（fish では function/alias が PATH より優先）。
> `which npm` は外部コマンドで fish function を無視するため「which は fnox-shims を指すのに
> npm は 401」という紛らわしい症状になっていた。spec の D-2 セクション参照。
>
> `config.fish` は `Edit(~/.config/fish/**)` deny 保護のため、編集は USER が行う。

- [ ] **Step 1: config.fish の corepack エイリアスを fnox exec で包む**

`~/dotfiles/.config/fish/config.fish` の corepack エイリアス群（127 行付近）を変更:

```fish
alias yarn="fnox exec -- corepack yarn"
alias yarnpkg="fnox exec -- corepack yarnpkg"
alias pnpm="fnox exec -- corepack pnpm"
alias pnpx="fnox exec -- corepack pnpx"
alias npm="fnox exec -- corepack npm"
alias npx="fnox exec -- corepack npx"
```

各行頭に `fnox exec -- ` を足すだけ。`bun`/`bunx` は corepack 対象外なので変更不要
（fish でも PATH の fnox-shim 経由で token 注入される）。

- [ ] **Step 2: 新しい fish セッションで検証 `[VERIFY]`**

Run（新しい対話 fish）: `npm ping --registry https://npm.flatt.tech/`
Expected: `PONG { "ok": true }`（401 でない）

> 検証済み（実機）: `fnox exec -- corepack npm ping` → PONG ok。

---

## Task 8: ローカル平文トークンの purge + ローテーション `[USER]`

> **訂正（検証で判明した正確な事実）**: 当初「git 履歴経由で GitHub に push 済み＝露出」と
> 記載したが**誤り**。全コミット diff + 全 object（到達不能含む）を pickaxe / cat-file で
> 走査した結果、実トークンは **ローカル stash@{0}（"npmrc auth ベタ一時的に"= 平文実験）の
> blob 9fbca17 1 個のみ**に存在し、**origin には未 push**（feature ブランチ自体も未 push）。
> 露出は**ローカルのみ**だった（`git stash show -p` 等で読める程度）。
> スナップショット grep だけだと取りこぼす + placeholder `tg_anon_xxx` の誤検出に注意。

- [ ] **Step 1: 実トークンを含むローカル stash を破棄して purge `[VERIFY]`**

```fish
git stash drop 'stash@{0}'           # 平文実験の stash（実トークン入り）
git reflog expire --expire=now --all # ※ refs/stash の reflog も消えるので他 stash の要否に注意
git gc --prune=now                   # dangling blob を即時 purge
# 検証: 実トークン blob が消えたか（固有 substring で全 object 走査、空なら成功）
git cat-file --batch-all-objects --batch-check | awk '$2=="blob"{print $1}' | \
  while read oid; git cat-file blob $oid 2>/dev/null | grep -q '<実トークン固有部>'; and echo "残存:$oid"; end
```

- [ ] **Step 2: Flatt で新トークン発行 + 旧トークン revoke**

Flatt Security 管理画面で registry token を再発行し、旧トークンを revoke。
（ローカルからは purge 済みだが、念のため＋ローカル disk に一時存在した事実への保守的対応）

- [ ] **Step 3: 1Password の item を新トークンで更新**

`op://personal-develop/ut45f4nuxkaoquisyrolp2vqqe/credential` の値を新トークンに更新。
fnox は live fetch なので config 変更不要、次回 `npm` 実行から新トークンが使われる。

- [ ] **Step 4: 反映確認 `[VERIFY]`**

Run（新トークンで認証通るか。whoami は automation token 非対応なので ping）:
`fnox exec -- corepack npm ping --registry https://npm.flatt.tech/`
Expected: `PONG { "ok": true }`

---

## Self-Review（spec カバレッジ）

- spec A（fnox config）→ Task 2 ✅
- spec B（dispatcher）→ Task 1 ✅
- spec C（shim 配置）→ Task 1, 5 ✅
- spec D（mise PATH）→ Task 5 ✅
- spec E（.npmrc）→ Task 6 ✅
- spec F（.gitignore）→ Task 5 ✅
- spec G（install.sh）→ Task 5 ✅
- spec H（bootstrap）→ Task 3 ✅
- spec 検証手順 → Task 4, 7 ✅
- spec 受容リスク（postinstall, sops, age.txt 存続）→ Out of scope として spec に記載済み、本計画では age.txt を Task 3/7 で一切触らない ✅
- 訂正: 当初「git 履歴で push 済み露出」と誤記 → 実際はローカル stash のみ・未 push。
  全 object 走査で実トークン blob を特定し purge + ローテーション → Task 8 で対応 ✅
- 追加: 暫定構成（age 抜き）→ spec 冒頭 + 計画冒頭で明示、将来 age を再導入する余地を Out of scope に明記 ✅
- 追加: fish corepack エイリアスによる shim bypass（E2E で判明）→ Task 7.5 で対応、spec D-2 に記載 ✅
- 追加: mise x の PATH 再帰ループ（E2E で判明）→ `mise which` 方式に修正済み（Task 1 / spec B）✅

## 別タスクに分離（本計画スコープ外）

- **corepack → mise packageManager 対応への移行**: PR #8059（mise 2026.2.8+）で `packageManager`
  フィールド対応が入ったが、per-project 版解決の実挙動は mise バージョン依存で要実証。
  corepack 廃止は影響範囲が広いため独立タスクとする。本計画では corepack 維持のまま
  fish エイリアスに token 注入する（Task 7.5）。
