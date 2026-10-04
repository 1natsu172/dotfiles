# fnox による秘匿情報管理

[fnox](https://fnox.jdx.dev/) を使い、秘匿情報を平文で disk に置かない。1Password の vault を保管場所とし、実行時に取得して、使うプロセスの env にだけ注入する。

## 解決の流れ

`~/.config/fnox/config.toml`（追跡対象。平文の秘匿値は無い）に、秘匿情報ごとの名前と取得元の provider を書く。

1. keychain provider が macOS Keychain（service `fnox`）から 1Password の service account token を取り出す
2. 1password provider がその token で `op://VAULT/ITEM/FIELD` を取得する
3. `[secrets]` のキー名がそのまま環境変数名になり、消費プロセスの env に入る
4. 消費側の設定が `${NAME}` で参照する（例: `.npmrc` の `_authToken=${FLATT_NPM_TOKEN}`）

- 名前は config と消費側の 2 箇所で一致させる。片方を改名したら両方直す
- provider は `op_<vault の範囲>_<環境>` と名付ける（例: `op_personal_develop`）

### `env = false`

`[secrets]` の各エントリは既定で `fnox exec` の子プロセスに注入される。`env = false` を付けると注入されず、`fnox get` と provider の認証からだけ参照できる。

- op provider の service account token（`OP_SA_...`）は `env = false` で default の `[secrets]` に 1 度だけ置く。注入すると npm の postinstall などが vault 全体を引ける token を読める。op provider の `token` は `[secrets]` の参照しか受け付けないので、keychain を直接引く書き方はできない
- `env = false` は注入を止めるだけで、取得は止めない。`fnox exec` は profile の全 secret を取得してから除外するので、`fnox get` でしか使わない secret を default に置くと、npm を打つたびに op への問い合わせが走る。そういう secret は専用の profile に置く

### age provider

op を通さず、暗号文を config に commit して持つ secret 用の provider。現在これを使う secret は無い。

- `recipients` は公開鍵（commit してよい）、`identity = { provider = "keychain", value = "AGE_IDENTITY" }` が復号鍵を Keychain から取る。復号鍵を平文でファイルに置かない
- 復号鍵の登録: `awk '/^AGE-SECRET-KEY/' <keyfile> | fnox set AGE_IDENTITY --provider keychain --global`
- 使い方: `fnox set <NAME> "<値>" --provider age` で暗号文が `[secrets]` に書かれる
- age は保管時の保護で、env に載るかどうかは `env` フラグで別に決まる。`OP_SA` は Keychain 直結のままで足りているので age にしていない

## 注入機構

token を親シェルの env に出さず、パッケージマネージャの子プロセスにだけ注入する。各シェルが読むファイルにシェル関数を置き、`npm` などを `fnox exec -- npm "$@"` に置き換える。

`bin/install-fnox-shell-wrappers` が `TOOLS`（npm npx yarn bun bunx pnpm pnpx）から生成物を書く。手で管理している rc は触らない。

| シェル | 生成物 | 読み込み |
|---|---|---|
| zsh / bash | `bin/fnox-wrappers.sh` | `~/.zshrc` / `~/.bashrc` に手で足した `source` 行。sandbox は rc への書き込みを禁じているので、ここは人が 1 度だけ書く |
| fish | `~/.config/fish/conf.d/fnox-wrappers.fish` | conf.d として自動で読まれる |

- Claude Code の Bash tool は、ログインシェルが fish でも zsh で動き、起動時に `~/.zshrc` の関数を snapshot する。AI が打つ `npm` に token を通すのは zsh の `source` 行なので、fish しか使わなくても消さない
- `command npm` で関数を飛ばして実体を直接起動できる
- PATH の shim にしないのは、関数なら PATH に載らず mise などが起動する subprocess に継承されないため。shim だと mise の bootstrap が shim に再入して無限再帰したことがある
- 関数を通るのは関数を持つシェルから打った場合だけ。`make` や Node の `child_process` などが直接起動する npm には注入されない。npm の postinstall は親の env を継承するので注入される

### 版の解決

ラッパーは版を解決しない。`fnox exec -- <tool>` は PATH で `<tool>` を探し、PATH は `mise activate` が cd のたびに project の版へ切り替える。

- mise の `idiomatic_version_file_enable_tools = ["node", "pnpm", "yarn", "npm"]` で、`package.json` の `packageManager` と `.nvmrc` / `.node-version` を読ませている。corepack は使わない
- pin されていて未インストールのツールは自動で入らない。`fnox exec` は mise の command-not-found を通らないので、手で `mise install` する。npm だけは node 同梱版が黙って使われる
- npm の版は mise 既定の `aqua:npm/cli` で入るので、`mise install` に token は要らない。npm 本体は npmjs から取るので Takumi Guard を通らないが、公式の CLI を版固定で取るだけなので許容している

## remote(HTTP) MCP への token 注入（headersHelper）

remote の MCP サーバは、Claude Code が `Authorization` ヘッダで token を送る。起動するコマンドが無いので `fnox exec` では包めず、env で渡すと claude 自体の env に token が載る。そこで Claude Code の `headersHelper` を使う。claude が接続時にスクリプトを実行し、stdout の JSON をヘッダに使う。起動経路（CLI / IDE / Dock）によらず動き、token は env に載らない。他の client には持ち込めないが、それは承知で選んだ。

- スクリプトは `bin/claude-utils/mcp-auth-header.sh <SECRET_NAME> [header] [scheme]`。どのサーバがどの secret を使うかは `.mcp.json` の引数に書く。MCP が増えても設定を足すだけで済む
- `fnox get <secret> --profile mcp` で 1 つだけ取得し、失敗したら非 0 で終わる。空の `Bearer ` を送って 401 になるのを避けるため
- MCP の token は `mcp` profile に `env = false` で置く。default に置くと npm を打つたびに取得が走る
- helper は `--no-defaults` を付けず、default の `OP_SA` を認証に使う。profile ごとに `OP_SA` を書き直さずに済む
- helper は接続のたびに実行され、キャッシュされない。Dock から起動した claude の最小の PATH でも動くよう、スクリプト内で mise の shims と Homebrew を PATH に足している

## 新しい秘匿情報を足す

1. 1Password の vault に値を置き、`op://<vault>/<item>/<field>` を控える
2. config の `[secrets]` に `<NAME> = { provider = "op_personal_develop", value = "op://..." }` を足す
3. 消費側で `${<NAME>}` を参照する。ラッパー経由のツールなら追加の設定は要らない。read を開けているファイルに平文を書かない
4. 別の vault や service account が要るなら provider を足す。token の Keychain 登録は `echo "<token>" | fnox set <NAME> --provider keychain --global`

`fnox set <NAME> --provider <p>` は Keychain への格納と同時に default の `[secrets]` にも `env = true` のエントリを書く。provider の認証鍵を入れるつもりで実行すると、その鍵が以後すべての `fnox exec` で注入される。不要ならその行を消すか `env = false` を付ける。

## sandbox との関係

Claude Code の sandbox の中では op が TLS 検証に失敗するので、`fnox *` を `excludedCommands` で sandbox 外に出し、値を出力する `fnox get` / `fnox export` は deny している。token の要る操作は AI も `fnox exec -- <pm> ...` の形で打つ。詳細は [claude-code-security.md](./claude-code-security.md) の「fnox」節。

## 障害時の回避

| 壊れたもの | 回避策 |
|---|---|
| fnox や op | `command npm` で関数を飛ばす。token は注入されないので認証が要る操作は失敗する |
| ラッパー関数 | rc の `source` 行をコメントアウトし、fish は `conf.d/fnox-wrappers.fish` を退避する。戻すときは `bin/install-fnox-shell-wrappers` を実行する |
| 注入方式そのもの | `fnox activate` で親シェルの env に展開する |

`fnox activate` は平常時には使わない。シェル配下のどのプロセスからも token が読めるようになり、postinstall やプロンプトインジェクションで漏れる範囲が広がる。それでも平文を disk に置かないという利点は残るので、最後の手段としては妥当。緩めるときも平文を disk に置かない線は守る。

## token が要らない呼び出しの遅延

ラッパーは `fnox exec` の取得で 1 回あたり約 1.5 秒かかる。token の要らない呼び出しでは無駄で、timeout のある呼び出し元では失敗の原因になる。関数は PATH に載らないので、statusline や hook が直接起動する `bun` は関数を通らず遅延しない。関数を持つシェルから token の要らないコマンドを打ち、遅延が問題になるときは `command bun` と書く。

## 既知の制約

- registry token は npm の子孫（postinstall を含む）の env に載る。npm が `${VAR}` を展開する以上避けられないので、注入するのは rotate できる `FLATT_NPM_TOKEN` 1 件に絞っている。postinstall への対策は [supply-chain-defenses.md](./supply-chain-defenses.md) の層 2
