# fnox による秘匿情報管理

[fnox](https://fnox.jdx.dev/) を統一インターフェースに、ローカル disk から平文の秘匿情報を排除する。
**op vault を一次保管庫**にして実行時に live fetch し、消費プロセスの env にのみ注入する方式。
（初出の適用先は npm registry の認証トークンだが、本書は特定の値ではなく**仕組み**を述べる。
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

## 注入機構（シェル関数ラッパー・全シェル＋Claude 一様）

token は **親シェル env に出さず、パッケージマネージャの子プロセスにのみ**注入する（`fnox exec` で wrap）。
配送は **各シェルが読むファイルに置くシェル関数**で行う（PATH shim ではない）。`bin/install-fnox-shell-wrappers`
が単一の TOOLS 列（npm npx yarn bun bunx pnpm pnpx）から、各シェル構文の**ラッパーファイルを丸ごと生成**する
（冪等・所有ファイルのみ書く＝hand-maintained な rc は触らない）。

### シェル関数ラッパー

各ツールにつき `fnox exec -- <tool> "$@"` を呼ぶ関数を定義する。生成物と読み込み:

- **zsh / bash**: `bin/fnox-wrappers.sh`（POSIX 関数）を生成。`~/.zshrc` / `~/.bashrc` から**一度だけ手で `source` 行**を足す
  （`[ -r "$HOME/dotfiles/bin/fnox-wrappers.sh" ] && . "$HOME/dotfiles/bin/fnox-wrappers.sh"`。repo の `.bashrc` が
  既に `.cargo/env`・`.fzf.bash` を source しているのと同じ流儀）。以後ツールを増減してもスクリプトが
  `fnox-wrappers.sh` を書き換えるだけで済み、rc の source 行は不変。
- **fish**: `~/.config/fish/conf.d/fnox-wrappers.fish`（fish が conf.d を自動 source。`function <tool>; fnox exec -- <tool> $argv; end`）。

zsh/bash が conf.d 相当を持たないので **fish=自動 conf.d / zsh・bash=明示 source** の差はあるが、どちらも
「スクリプトは所有ファイルを生成、シェルがそれを読む」で対称。`fnox-wrappers.sh` の source 行を rc に手で足すのは、
**AI（Claude）はサンドボックスで `.zshrc`/`.bashrc` を書けない**（rc インジェクション保護）ため＝rc 編集は人手の一度きり。

これで**対話シェル（zsh/bash/fish）と Claude Code の Bash tool の両方**で npm/yarn/pnpm/bun が fnox を通る:

- **Claude Code の Bash tool は起動時に `~/.zshrc` を source して alias/関数/option を snapshot し、各コマンドに
  再適用する**（`code.claude.com/docs/en/tools-reference#bash-tool-behavior` 明記。fish はデフォルトでも
  非 POSIX なので Bash tool は zsh にフォールバックし `~/.zshrc` を読む）。なので非対話 `bash -c 'npm ...'`
  （AI エージェント経由）でも関数が効く。← PATH shim の元々の存在理由「非対話 AI bash に注入」は、実は
  rc の alias/関数でカバーできると判明したので shim を廃止した。
- **bypass**: `command <tool>`（または `\<tool>`）で関数を飛ばして実体を直接起動する（旧 `FNOX_SHIM_BYPASS`
  env の代替）。

### なぜ PATH shim をやめたか（npm:npm 再帰）

旧構成は `bin/_fnox_shim` を `[env]._.path` で PATH 先頭に prepend していた。これは npm の mise backend
`npm:npm`（mise が `npm view`/install を **PATH の `npm` 名で実行**する。実機 probe 済み＝node を絶対パスで
使うのではない）と両立しない: PATH 先頭が shim だと mise の bootstrap npm が shim に再入し、
`mise install npm`→`npm`→shim→… で **無限再帰してハング**する（手動 `mise i` でも同じ。shim が PATH に
居る限り npm の bootstrap が壊れるのが真因）。mise は install サブプロセスにも `[env]._.path` を再注入する
ため、shim 側で外側の PATH をいじっても打ち消されて回避できなかった。

シェル関数は **PATH に載らず、mise が spawn する subprocess に継承されない**ので、mise の bootstrap npm は
素の実体 npm に解決される → 再帰せず **per-project の npm 版 pin が普通に動く**。これが関数方式の決め手。

> 注: その後 npm は mise 既定で `aqua:npm/cli` に移行し（jdx/mise#9762・2026-05〜）、`npm view`/install を
> PATH の `npm` 名で走らせなくなったため、npm:npm 再帰は現在は発生しない（本節は歴史的経緯）。ただし
> 「関数を PATH に載せない」という選択自体は他の language backend にも効くので維持している。

### 版解決（corepack → mise packageManager）

版解決は **mise が肩代わり**する（corepack 廃止）:

- mise 2026.2.8+（PR #8059）は package.json の `packageManager`（優先される
  `devEngines.packageManager` があればそちら）を **idiomatic version file** として読み、
  pnpm/yarn/npm の版を per-project 解決する。node も `.nvmrc`/`.node-version` を idiomatic に
  読ませ、node 版も per-project に自動解決させる。有効化は gate 設定
  `[settings] idiomatic_version_file_enable_tools = ["node", "pnpm", "yarn", "npm"]`（mise config.toml）。
- `fnox exec -- <tool>` の `<tool>` は素の PATH 探索で解決される。`mise activate`（zsh/bash/fish）が
  cd 時に PATH を pin 版へ更新するので、ラッパーは現在のプロジェクトの版に注入する。`packageManager`
  記載の無いプロジェクトでは `[tools]` の `yarn = "1"` 等が global default。
- **版解決とエラーは mise に委ねる**（ラッパーは無ロジック）。pin 済みだが未インストールのツールは
  **自動インストールしない**（旧 dispatcher の auto-install は廃止）→ 手で `mise install` する。
  `fnox exec` は内部 execvp なので mise の command-not-found ハンドラ（`not_found_auto_install`）は
  経由しない。npm は node 同梱で常に PATH 上に在るため、**未インストール pin の npm はサイレントに
  node 同梱版**で走る点に注意（mise の missing 警告で気付く運用前提）。
- **pin npm の install は素の `mise install`（`mise i`）でよい**。npm は mise 既定で `aqua:npm/cli` に解決され
  （jdx/mise#9762・2026-05〜）、版は npm/cli の GitHub tags、実体は npmjs.org の tarball から入る＝**FLATT を
  経由せず token 不要**（pnpm/yarn が aqua/github で入るのと同じ）。
  - 旧 `npm:npm` backend は版解決に `npm view npm versions …` を FLATT 向けに走らせ token を要し、素の `mise i`
    は空 token で **401** だった（`fnox exec -- mise i` で回避）。aqua 移行でこの token 依存は解消した。なお
    aqua は npm CLI 本体を npmjs.org から直に取る＝**FLATT/Takumi Guard プロキシをバイパス**するが、対象は公式
    npm CLI かつ版固定なのでリスクは限定的（プロジェクト依存の `npm install` は従来どおり FLATT 経由）。
  - install 後、プロジェクト内のランタイム `npm install`（依存取得）は従来どおりラッパー `npm`
    （→`fnox exec -- npm`）が FLATT に token 付きで実行する。

### トレードオフ（生 subprocess の穴）

シェル関数は **非シェル・非 npm 子孫の生プロセスが直接叩く npm には継承されない**（`make`→`sh -c npm`、
Node の `child_process`、git hook 等）→ その経路は token 非注入になる。ただし npm の **postinstall/lifecycle
は親の fnox-wrapped npm の env（`FLATT_NPM_TOKEN`）を継承**するのでカバーされる。穴は「npm 以外の foreign
ツールが token 付き registry 向けに新規 npm install する」狭いケースのみ。PATH shim は全 subprocess を拾えた
代わりに npm:npm 再帰を抱えていた（前節）ので、この穴を受け入れて再帰を消す判断（個人運用では実害が小さい）。

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
   その値を使うツールがラッパー関数経由（npm/yarn/pnpm/bun 等）なら、追加設定なしで env に入る（**read 解放したファイルに平文を書かない**）。
4. 別 vault / 別 SA が要るなら provider を追加（命名規約に従う）。SA token の Keychain 登録は
   `echo "<ops token>" | fnox set <参照名> --provider keychain --global`（stdin で history 非露出、初回ダイアログで「Always Allow」）。
5. op を介さず **commit する暗号文**で持ちたい secret は age provider を使う：
   `fnox set <SECRET_NAME> "<値>" --provider age`（→ `{ provider="age", value="..." }` が config に書かれ commit 可。詳細は上述「age provider」）。

## sandbox / permission との関係

Claude Code の sandbox 内では op（Go 製）が TLS 検証に失敗するため、`fnox` は
`excludedCommands` で sandbox 外実行させる。あわせて `fnox get`/`fnox export`（値出力経路）は
deny する。詳細・根拠は [docs/claude-code-security.md](./claude-code-security.md) の「fnox」節。

- token を要する PM 操作（FLATT への install/publish 等）は、AI も含め **`fnox exec -- <pm> …` の形で明示的に打つ**。
  ラッパー経由の素の `npm install` は submit 文字列が `npm …` で `fnox *` に当たらず sandbox 内に残り、op の TLS
  失敗で 401 になる（`fnox exec -- <pm> …` はその install だけ sandbox 外に出る点を許容）。AI 向け呼び出し規則は
  `.claude/rules/fnox-sandbox-invocation.md`、egress/`SSL_CERT_FILE` を巡る切り分けの実機ログは
  [docs/claude-code-security.md](./claude-code-security.md) の「fnox」節。

## 無効化 / 緊急回避

ラッパー関数・fnox・op・mise の想定外バグや upstream の破壊的変更で npm/bun 等が打てなくなった時の
逃げ道。**失敗クラスごとに効くレイヤが違う**ので 2 系統を用意する。

| 失敗クラス | 症状 | 回避策 |
|---|---|---|
| (a) fnox / op の障害・upstream 破壊 | `fnox exec` が動かず token 注入が落ちる | `command <tool>` で実体を直接起動 |
| (b) ラッパー関数自体のバグ | 関数経路が壊れる | `fnox-wrappers.sh` の source 行 / conf.d ファイルを外す |

### (a) `command <tool>`（per-command）

ラッパーは関数なので `command npm`（または `\npm`）で関数を飛ばし、PATH 上の実体 npm を直接起動できる。
**token は注入されない**ので、認証が要る操作（private registry への publish 等）はその間失敗する点に注意。

```sh
command npm ci        # その 1 コマンドだけ素通し（fnox 非経由）
```

実体の版解決は `mise activate` が更新する PATH に依存する（「版解決」節参照）。

### (b) ラッパー撤去

関数定義そのものが壊れている場合は、`~/.zshrc`/`~/.bashrc` の `fnox-wrappers.sh` を source する 1 行を
コメントアウトし、fish は `~/.config/fish/conf.d/fnox-wrappers.fish` を退避して、シェルを再読込する。以後
npm/bun は素の実体が動く（fnox 非経由）。生成物の復旧は `bin/install-fnox-shell-wrappers`（冪等に再生成）。

## 平常時の意図的 bypass（秘匿不要・レイテンシ敏感）

ラッパーは呼び出しごとに `fnox exec`（op live fetch）で **≈1.5s** のオーバーヘッドを足す。**token を
必要としない**呼び出しがラッパー経由になると、この 1.5s は純粋な無駄になり、**タイムアウト制約のある
呼び出し元では失敗の原因**になる。

ただし関数は **PATH に載らないシェル機構**なので、**PM を直接 exec する subprocess（多くの statusline
custom-command・hook 等）は関数を継承せず、もともと実体が動く＝既に高速**。fnox レイテンシが乗るのは
「ラッパー関数を持つシェル（対話 zsh/bash/fish・Claude の Bash tool）から叩いた」ときだけ。その経路で
token 不要かつレイテンシ敏感なら、呼び出しを `command <tool>` に書き換えて fnox を迂回する。

> 〈具体例: ccstatusline の duration 表示〉ステータスラインの custom-command が
> `bun run …/claude-code-duration.ts` を呼ぶ。このスクリプトは tmp の JSON を読むだけで秘匿不要。
> 旧 PATH shim 構成では全 bun 呼び出しが shim 経由（≈1.5s）になり既定 timeout **1000ms** を超過し
> `[Timeout]` 表示だった。関数構成では custom-command の bun が関数を継承しなければ実体直起動で解消する。
> 念のため確実に避けるなら `commandPath` を `command bun run …`（または実体パス直書き）にする。

## 既知の制約・別タスク

- **FLATT registry token は npm 子・孫プロセス（postinstall 等）の env に乗る**。npm が `.npmrc` の
  `${VAR}` を展開して使う以上、注入が必要な registry token なので原理的に避けられない。**追加の
  `ignore-scripts` 防御はグローバル導入しない判断（YAGNI）**: 既存の `min-release-age`(7日) が「汚染版を
  掴む確率」を主に潰しており、注入される秘匿情報は `FLATT_NPM_TOKEN` 1件（rotatable な registry token・
  OP_SA は `env=false`）で blast radius が小さい。一方 npm の `ignore-scripts` は allowlist 無しの全停止
  （依存だけでなく自プロジェクトの prepare/postinstall や native module ビルドも止まる）で摩擦が大きく
  サイレント失敗を招く。bun・pnpm 10+ は依存スクリプトを既定でブロックする safe-by-default なので穴は
  npm/yarn-classic に限る。**運用**: 高リスクな単発 install は手動で `npm install --ignore-scripts`
  →必要分だけ `npm rebuild`、未知パッケージは bun/pnpm を優先する。
- **provider 認証の SA token（OP_SA）は `env = false` で注入しない**。以前は default `[secrets]` の通常
  エントリで、`fnox exec` が npm 子 env まで SA token を載せていた（postinstall から vault 全体を引ける
  露出）。`env = false` 化で解決済み（上述「env 注入の制御」）。
- **corepack は廃止済み**（mise の `packageManager` 対応へ移行・PR #8059 / mise 2026.2.8+）。
  per-project 版解決は mise（node/pnpm/yarn/npm）が肩代わりする（上述「版解決」）。**注入は PATH shim を
  廃して各シェル rc のラッパー関数（`fnox exec`）へ移行**した（上述「注入機構」）。npm はその後 mise 既定で
  `aqua:npm/cli` に移行（npmjs.org tarball・FLATT 非経由・token 不要）したため npm:npm の bootstrap 再帰自体が
  無くなり、関数が PATH 非搭載で mise subprocess に継承されない利点は他の language backend 向けに残る。
- **age provider は再導入済み**（基礎基盤のみ・使用 secret は無し。上述「age provider」）。OP_SA を age 化
  する 3 段移行（`keychain → age → op`）は任意で未実施（現状 keychain 直結で必要十分）。

## 関連

- sandbox/permission の保護方針・delta: [docs/claude-code-security.md](./claude-code-security.md)
- fnox 公式: <https://fnox.jdx.dev/>
