# fnox による秘匿情報管理

[fnox](https://fnox.jdx.dev/) を統一インターフェースに、ローカル disk から平文の秘匿情報を排除する。
**op vault を一次保管庫**にして実行時に live fetch し、消費プロセスの env にのみ注入する方式。
（初出の適用先は npm private registry の認証トークンだが、本書は特定の値ではなく**仕組み**を述べる。
具体名は例として `〈例: ...〉` で示す。）

## 解決チェーン

`~/.config/fnox/config.toml`（global config、追跡対象、平文の秘匿値なし）に、秘匿情報1件ごとに
名前（＝注入される環境変数名）と取得元 provider を定義する。解決は次の段で流れる:

```
[keychain provider] 1Password service account token(ops_…) を macOS Keychain から取得
        │
        ▼
[1password provider] その SA token で op CLI を叩き op://VAULT/ITEM/FIELD を live fetch
        │
        ▼
<SECRET_NAME>      解決値を「その名前の環境変数」として消費プロセスの env に export
        │
        ▼
消費側の設定が env 参照（例: 設定ファイル内の ${<SECRET_NAME>}）で値に展開する
```

- `<SECRET_NAME>` は config の `[secrets]` に書いたキー名がそのまま環境変数名になる。
  消費側（設定ファイル等）は同名を env 参照すれば値を受け取る。**名前は config と消費側の 2 箇所で一致させる**
  （片方を改名したら両方直す。これが唯一の結合点）。
- SA token 実体は **Keychain（service=`fnox`）内のみ**。config には provider 参照と `op://` URI だけ。
- provider 命名は `op_<vault スコープ>_<環境>`。将来 `op_work` 等を衝突なく追加できる。

> 〈現状の具体例〉 `[secrets]` に `FLATT_NPM_TOKEN = { provider = "op_personal_develop", value = "op://.../credential" }`
> を定義し、`~/.npmrc` に `//<registry>/:_authToken=${FLATT_NPM_TOKEN}` と書く。npm 実行時に
> `FLATT_NPM_TOKEN` が env に注入され `${FLATT_NPM_TOKEN}` が展開される。値や名前が変わっても上の仕組みは不変。

### env 注入の制御（`env = false`）

`[secrets]` / `[profiles.X.secrets]` の各エントリは既定で消費プロセスに env var として注入される
（`env = true`）。`env = false` を付けると **`fnox exec` では注入されず、`fnox get`（および provider
認証の token 解決）からのみ参照できる**。主な用途:

- **provider 認証専用の token**（例: op provider の SA token `OP_SA_…`）。注入は不要で、むしろ注入すると
  消費プロセス（npm の子・postinstall 等）に vault 全体を引ける SA token（root 資格情報）が漏れる。
  `env = false` で default `[secrets]` に 1 度だけ宣言すれば、各 provider/profile から認証に使えて env には
  載らない。
- **`fnox get` でだけ取りたい secret**（例: headersHelper が引く MCP token）。

注意: `env = false` は**注入を止めるだけで解決（provider fetch）は止めない**。`fnox exec` は対象 profile の
全 secret を解決してから env=false を除去するため、「`fnox get` でしか使わない secret」を default `[secrets]`
に置くと無関係な `fnox exec`（npm 等）の度に op fetch が走る。そういう secret は専用 profile に置いて解決
スコープから外す（後述「remote(HTTP) MCP への token 注入」）。

### keychain 直結（OP_SA）と age provider の関係

op の SA token は **keychain 直結（2 段: keychain → op）**で運用する。理想の `keychain → age → op`
3 段（SA token を age 暗号文で commit）は fnox 1.25.1 で age `identity = { provider="keychain" }` が
未実装のため見送っていたが、**1.26.0 (PR #515) で実装され age provider を再導入**（下記）。ただし
**OP_SA を age 化（3 段）する必要は今のところ無い**ので OP_SA は keychain 直結のまま（op vault が
source of truth）。age 層は **at-rest（commit する暗号文）の保護**であって、`env = false` による
**env 注入制御とは別軸**（age で保管しても解決時は平文になり、env に載るか否かは env フラグが決める）。

### age provider（commit する暗号文 secret 用・基礎基盤）

op を介さず **fnox.toml に age 暗号文として commit する secret** を扱う provider。**現状これを使う
secret は無く、土台だけ整えた状態**。

- `[providers.age]`: `recipients`=公開鍵(`age1…`・commit 可)、`identity = { provider = "keychain",
  value = "AGE_IDENTITY" }`（復号用の私有鍵を keychain service `fnox` から取得）。**平文鍵はディスクに
  置かない**（旧 sops 時代の `~/.config/fnox/age.txt` は #1 で廃止）。recipients は単一（このマシン）。
- 私有鍵(`AGE-SECRET-KEY-1…`)の keychain 登録: `awk '/^AGE-SECRET-KEY/' <keyfile> | fnox set
  AGE_IDENTITY --provider keychain --global`（stdin で history 非露出・初回「Always Allow」）。
- 使い方: `fnox set <NAME> "<値>" --provider age` → `[secrets]` に `{ provider="age",
  value="<base64暗号文>" }` が書かれ **commit 可**。`fnox get`/`fnox exec` が keychain identity で復号。
- identity 解決順: `FNOX_AGE_KEY` → `identity`(keychain) → `key_file` → 既定 `~/.config/fnox/age.txt`
  （未存在＝keychain identity が優先されるので不使用）。

## 注入機構（PATH shim ＋ fish corepack 共存）

token は **親シェル env に出さず、npm 子プロセスにのみ**注入する（`fnox exec` で wrap）。
シェル種別・対話/非対話を問わず一様に効かせるため、PATH shim を主機構とする。

### PATH shim（bash/zsh ＋ 非対話 subshell ＝ AI ツール）

- `bin/_fnox_shim` が dispatcher。`bin/fnox-shims/<tool>` の symlink 群（install.sh の
  `--deploy` で冪等生成、symlink は派生物として gitignore）から呼ばれる。
- mise の `[env]._.path` で `bin/fnox-shims` を PATH 先頭に prepend。env 継承で
  非対話 `bash -c 'npm ...'`（AI ツール経由）にも伝播する。
- dispatcher は `fnox exec -- $(mise which <tool>) "$@"` で実体を起動する。
  - **`mise x -- <tool>` は使わない**: PATH 検索が走り PATH 先頭の `fnox-shims/<tool>` を
    再帰的に拾って**無限ループ**する。`mise which` は実体バイナリの絶対パスを返すのでループしない。
  - パスをハードコードもしない: `mise which` が現在の mise 設定（プロジェクト別バージョン含む）に
    追従するため、インストール構造の変化に強い。
  - `mise which` 失敗時（untrusted な project 設定・mise 未管理ツール等）は **fail-fast**：
    生の mise エラーで即死させず実行可能なメッセージを出して止める。system PATH の実体へは
    **意図的に fall back しない**（mise 管理前提のツールが黙って別バージョンで動く事故を避け、
    設定ミスを表面化させるため）。

### fish の corepack エイリアス共存

`config.fish` には corepack でパッケージマネージャを版管理する `alias npm="corepack npm"` 等がある。
**fish では function/alias が PATH より優先**されるため、この alias が PATH 上の fnox-shim を
shadow し `fnox exec` を bypass する → fish だけ token 未注入で **401**。
（`which npm` は外部コマンドで fish function を無視し PATH を表示するので「which は fnox-shims を
指すのに 401」という紛らわしい症状になる。bash/zsh は corepack alias が無いので影響なし。）

対処として fish の corepack エイリアスを `fnox exec --` で包む:

```fish
alias npm="fnox exec -- corepack npm"   # yarn/yarnpkg/pnpm/pnpx/npx も同様
```

これで fish は「alias → fnox exec(token 注入) → corepack(版解決) → 実 npm」、bash/zsh は
「fnox-shim(PATH) → fnox exec → mise which → 実 npm」となり両系統で注入される。
`bun`/`bunx` は corepack 対象外なので fish でも PATH shim 経由。

## remote(HTTP) MCP への token 注入（headersHelper）

GitHub Copilot 等の **remote(HTTP) MCP** サーバは、token を `Authorization: Bearer` ヘッダで Claude Code の
MCP クライアントが送る。ローカル command が無いので `fnox exec` で wrap できず、env 注入したければ
client（claude / IDE）ごと包むしかない（IDE/Dock 起動で穴・token が client 全体の env に載る）。OAuth は
GitHub MCP × Claude Code で未対応（upstream issue 待ち）。

そこで Claude Code 固有の **`headersHelper`** を使う。`.mcp.json` / `~/.claude.json` のサーバ定義で `"headers"`
の代わりに `"headersHelper": "<script>"` を置くと、claude 本体が**接続時に** script を実行し、stdout の JSON
（`{"Authorization":"Bearer <token>"}`）をヘッダにマージする。claude 本体が走らせるので**起動経路に非依存**
（CLI/IDE/Dock 一様）で、**token は env に一切載らない**（接続時に script の stdout に瞬間的に現れるだけ）。
**代償は移植性**：headersHelper は Claude Code 専用で他 client に持ち込めない（汎用なら `Bearer ${VAR}` だが
remote MCP では client ごと env 注入が要り IDE で穴になる）。承知の上で移植性を捨てた判断。

- script は汎用の `bin/claude-utils/mcp-auth-header.sh <SECRET_NAME> [header] [scheme]`。**どのサーバが
  どの secret/ヘッダを使うかは `.mcp.json` 側に引数で併記**し（マッピングを設定に co-locate）、スクリプトは
  値非依存の1プリミティブに保つ。header-PAT な MCP が増えても新規スクリプト不要＝設定追記だけで足せる。
- 中身は `fnox get <secret> --profile mcp` で**単一 secret だけ**を解決し `jq` でヘッダ JSON を
  組む。**fail-fast**：解決失敗時は `set -e` で即非0終了し、空の `Bearer ` を吐いてサイレント 401 になるのを
  防ぐ（`fnox exec` で profile 全体を env 注入する方式は、失敗時に空文字注入＝サイレント化する弱点があった）。
- **profile = 解決スコープ**：MCP token を default `[secrets]` に置くと、`env = false` にしても npm 等の
  `fnox exec`(default) が**解決（op fetch）してから除去する**ため毎回無駄 fetch が走る。専用 `mcp` profile に
  置けば default exec の解決対象外になる。MCP token 自体も `env = false`（get 専用）にしておく。複数 MCP
  token も同 profile に並べられる。
- **OP_SA は default に 1 度だけ**：op provider の認証 SA token は default `[secrets]` に `env = false` で
  宣言し、helper は **`--no-defaults` を付けない**ことで default を継承して認証に使う（`fnox get` は要求
  secret ＋その認証依存のみ解決するので FLATT 等は巻き込まない）。これで **profile 毎の OP_SA 再宣言が不要**。
- helper は接続毎に実行され**キャッシュされない**（多サーバで同 token を引くなら自前の短 TTL cache 余地）。
  Dock 起動 claude の最小 PATH でも解決できるよう `PATH` に mise shims と homebrew を明示する。
- 仕様一次情報: Claude Code MCP Docs の dynamic headers（`headersHelper`）節。

## 新しい秘匿情報を足す

1. op vault に値を置き、`op://<vault>/<item>/<field>` URI を控える。
2. `~/.config/fnox/config.toml` の `[secrets]` に `<SECRET_NAME> = { provider = "<op provider>", value = "op://..." }` を追記（op 経由で取る場合。`<op provider>` は既存の `op_…` provider、例 `op_personal_develop`）。
3. 消費側で `<SECRET_NAME>` を env 参照する形にする（設定ファイル内の `${<SECRET_NAME>}` 等）。
   その値を使うツールが PATH shim 経由 or fish 対象なら、追加設定なしで env に入る（**read 解放したファイルに平文を書かない**）。
4. 別 vault / 別 SA が要るなら provider を追加（命名規約に従う）。SA token の Keychain 登録は
   `echo "<ops token>" | fnox set <参照名> --provider keychain --global`（stdin で history 非露出、初回ダイアログで「Always Allow」）。
5. op を介さず **commit する暗号文**で持ちたい secret は age provider を使う：
   `fnox set <SECRET_NAME> "<値>" --provider age`（→ `{ provider="age", value="..." }` が config に書かれ commit 可。詳細は上述「age provider」）。

## sandbox / permission との関係

Claude Code の sandbox 内では op（Go 製）が TLS 検証に失敗するため、`fnox` は
`excludedCommands` で sandbox 外実行させる。あわせて `fnox get`/`fnox export`（値出力経路）は
deny する。詳細・根拠は [docs/claude-code-security.md](./claude-code-security.md) の「fnox」節。

## 無効化 / 緊急回避

shim・fnox・op・mise の想定外バグや upstream の破壊的変更で npm/bun 等が打てなくなった時の
逃げ道。**失敗クラスごとに効くレイヤが違う**ので 2 系統を用意し、別レイヤで噛み合わせる。

| 失敗クラス | 症状 | 回避策 |
|---|---|---|
| (a) fnox / op の障害・upstream 破壊 | `fnox exec` が動かず token 注入が落ちる | `FNOX_SHIM_BYPASS` を非空にして実行 |
| (b) dispatcher / `mise which` 自体のバグ | PATH shim 経路が壊れる（(a) も `mise which` に依存するため効かない） | `bin/fnox-shims/` の symlink を撤去 |

### (a) `FNOX_SHIM_BYPASS`（per-command / per-shell / per-dir）

dispatcher は `FNOX_SHIM_BYPASS` が非空だと、`mise which` で実体だけ解決し `fnox exec` を
飛ばして直接起動する。**token は注入されない**ので、認証が要る操作（private registry への
publish 等）はその間失敗する点に注意。

```sh
FNOX_SHIM_BYPASS=1 npm ci        # その 1 コマンドだけ素通し
export FNOX_SHIM_BYPASS=1        # そのシェル全体
# direnv / mise の env に置けば per-dir
```

実体バイナリの解決は `mise which` に依存する（前方互換のため。[注入機構](#注入機構path-shim--fish-corepack-共存)参照）。
`mise which` 自体が壊れている場合はこの経路も効かない → (b) へ。

### (b) shim 撤去（PATH 層ごと無効化）

```sh
rm bin/fnox-shims/*    # or: rm -rf bin/fnox-shims
```

PATH 先頭の `fnox-shims/` が空になり、次の PATH エントリ（mise shims）に fall through する。
fnox を一切通さず素の npm/bun が動く。復旧は `./install.sh`（`--deploy` で冪等に再生成）。

### fish の過渡期 caveat

移行期間中の `config.fish` の corepack エイリアス（`alias npm="fnox exec -- corepack npm"` 等）は
symlink を参照せず `fnox exec` を直接呼ぶため、**上記 2 つの回避策をどちらも無視する**
（(a) は `fnox exec` 自体を飛ばせない、(b) は symlink 非依存）。fish で緊急回避したい時は:

- bash/zsh で叩く（そちらは `FNOX_SHIM_BYPASS` が効く）、または
- その場で `alias npm='corepack npm'` 等に退避する。

この制約は corepack → mise `packageManager` 移行（[既知の制約・別タスク](#既知の制約別タスク)）で
エイリアスを撤去すれば解消する。撤去後は fish も PATH shim 経由になり、2 つの回避策が全シェルで
一様に効く（バイパス機構を fish 用に作り込まないのはこのため）。

## 平常時の意図的 bypass（秘匿不要・レイテンシ敏感）

`FNOX_SHIM_BYPASS` は緊急回避だけでなく、**平常運用での恒久的な迂回**にも使う。shim は呼び出しごとに
`fnox exec`（op live fetch）で **≈1.5s** のオーバーヘッドを足す。**token を必要としない**呼び出しを
shim 経由にすると、この 1.5s は純粋な無駄になり、**タイムアウト制約のある呼び出し元では失敗の原因**になる。

判断基準は「その呼び出しは token を要するか」。要さず、かつレイテンシ敏感なら `FNOX_SHIM_BYPASS=1` を
**恒久付与**して fnox を迂回する（token 注入されないが、元々不要なので副作用なし。実体解決は `mise which`
のままなのでバージョン追従も維持。機構詳細は [無効化 / 緊急回避](#無効化--緊急回避) の (a)）。

> 〈具体例: ccstatusline の duration 表示〉ステータスラインの custom-command が
> `bun run …/claude-code-duration.ts` を呼ぶ。このスクリプトは tmp の JSON を読むだけで秘匿不要。
> ccstatusline の custom-command 既定 timeout は **1000ms** のため、shim 経由（≈1.5s）だと超過し
> `[Timeout]` 表示になる。`commandPath` 先頭に `FNOX_SHIM_BYPASS=1` を付けて迂回（≈0.05s）。
> timeout を伸ばす対処は無駄な秘匿注入とラグが毎レンダリング残るため非推奨。

## 既知の制約・別タスク

- **FLATT registry token は npm 子・孫プロセス（postinstall 等）の env に乗る**。npm が `.npmrc` の
  `${VAR}` を展開して使う以上、注入が必要な registry token なので原理的に避けられない。`ignore-scripts`
  等の追加防御は別タスク。
- **provider 認証の SA token（OP_SA）は `env = false` で注入しない**。以前は default `[secrets]` の通常
  エントリで、`fnox exec` が npm 子 env まで SA token を載せていた（postinstall から vault 全体を引ける
  露出）。`env = false` 化で解決済み（上述「env 注入の制御」）。
- corepack を mise の `packageManager` 対応（PR #8059 / mise 2026.2.8+）へ移して corepack 廃止する案は、
  per-project 版解決の実挙動検証が要るため別タスク。本構成は corepack 維持。
- **age provider は再導入済み**（基礎基盤のみ・使用 secret は無し。上述「age provider」）。OP_SA を age 化
  する 3 段移行（`keychain → age → op`）は任意で未実施（現状 keychain 直結で必要十分）。

## 関連

- sandbox/permission の保護方針・delta: [docs/claude-code-security.md](./claude-code-security.md)
- fnox 公式: <https://fnox.jdx.dev/>
