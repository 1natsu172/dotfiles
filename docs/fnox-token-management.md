# fnox による秘匿情報管理

[fnox](https://fnox.jdx.dev/) を統一インターフェースに、ローカル disk から平文の秘匿情報を排除する。
sops+age（`## SOPS`）が `.env.enc.json` を暗号文でコミットする方式なのに対し、fnox は
**op vault を一次保管庫**にして実行時に live fetch する方式。両者は併存する。
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

### なぜ keychain 直結の暫定構成か

理想は `keychain → age → op` の 3 段（age 鍵を keychain に置き、fnox.toml に age 暗号文を
commit する。fnox docs も推奨）。しかし**実機 fnox 1.25.1 では age provider に
`identity = { provider = "keychain", ... }` が未実装**（TOML 段階で `unknown field 'identity'`。
docs だけ先行）。実装が追いつくまで age 層を省き、SA token を Keychain に直接置く 2 段で運用する。
fnox 側で実装され次第 age 層を再導入する（それまで op vault が source of truth）。

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

## 新しい秘匿情報を足す

1. op vault に値を置き、`op://<vault>/<item>/<field>` URI を控える。
2. `~/.config/fnox/config.toml` の `[secrets]` に `<SECRET_NAME> = { provider = "<op provider>", value = "op://..." }` を追記（op 経由で取る場合。`<op provider>` は既存の `op_…` provider、例 `op_personal_develop`）。
3. 消費側で `<SECRET_NAME>` を env 参照する形にする（設定ファイル内の `${<SECRET_NAME>}` 等）。
   その値を使うツールが PATH shim 経由 or fish 対象なら、追加設定なしで env に入る（**read 解放したファイルに平文を書かない**）。
4. 別 vault / 別 SA が要るなら provider を追加（命名規約に従う）。SA token の Keychain 登録は
   `echo "<ops token>" | fnox set <参照名> --provider keychain --global`（stdin で history 非露出、初回ダイアログで「Always Allow」）。

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

実体バイナリの解決は `mise which` に依存する（前方互換のため。[注入機構](#注入機構path-shim-fish-corepack-共存)参照）。
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

## 既知の制約・別タスク

- **npm 子・孫プロセス（postinstall 等）の env には token が乗る**。npm が `.npmrc` の `${VAR}` を
  展開する以上原理的に避けられない。`ignore-scripts` 等の対策は別タスク。
- 既存 mise activate + sops+age 由来の env 露出解消、`age.txt` の整理は別タスク（本構成は age.txt を参照しない）。
- corepack を mise の `packageManager` 対応（PR #8059 / mise 2026.2.8+）へ移して corepack 廃止する案は、
  per-project 版解決の実挙動検証が要るため別タスク。本構成は corepack 維持。

## 関連

- sandbox/permission の保護方針・delta: [docs/claude-code-security.md](./claude-code-security.md)
- `## SOPS`（README.md）: 併存する age 方式の秘匿情報管理
- fnox 公式: <https://fnox.jdx.dev/>
