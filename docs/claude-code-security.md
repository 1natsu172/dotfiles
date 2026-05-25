# Claude Code のセキュリティ設定

> **仕様の一次情報は公式 Docs**（[permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing)）。仕様はバージョンで変わりドリフトするため、permissions / sandbox を変更する前に必ず公式 Docs を参照する（`.claude/rules/claude-code-settings.md` で常設指示）。本書は **dotfiles 固有の判断**と、**公式から自明でない検証済み挙動（delta、検証日つき）**だけを書く。仕様の写経はしない。

脅威モデル: プロンプトインジェクション（実行主体は Claude の Bash / Write / Edit tool）と Shai-Hulud 型サプライチェーン攻撃。設定の実体は `dotfiles/.claude/settings.json`。

## 設計の前提（公式仕様のうち、判断の土台になる点だけ）

詳細は公式 Docs に譲り、ここでは**うちの判断が依存する核**だけを明記する（出典: permissions / sandboxing）:

- **Sandbox（OS 強制）は Bash subprocess とその子だけ**に効く。**Permission rule は全 tool**（Read/Edit/Write/Bash/WebFetch…）に効く。別レイヤ。
- **built-in deny は無い**。sandbox の default は全 read 可（`~/.aws/credentials`・`~/.ssh/` すら読める）。塞ぐパスは自分で `denyRead` / Permission `Read` deny に列挙する。
- **Permission の `Read`/`Edit` deny は sandbox 境界にマージ**され subprocess にも効く。逆に **sandbox の `denyRead`/`denyWrite` は Claude の Read/Edit/Write tool には効かない**（tool は permission を直接使う）。
- **「Edit rules apply to all built-in tools that edit files」**（Docs 原文）。→ 組み込み **Write tool も Edit カテゴリ**。Claude tool の write を縛るのは **`Edit(...)`**（`Write(...)` は組み込み Write tool に無効。実機挙動は `D3`）。
- sandbox の **write は allowlist**（cwd `.`・`$TMPDIR`・`~/.gnupg`・`~/.npm`（cache/logs）等のみ可）、**read は denylist**（全許可からの除外）。
- Permission パス書式の要注意点: **`/path` は絶対でなくプロジェクトルート相対**（絶対は `//path`、home は `~/path`）。取り違えると home 配下を全く守れない。書式詳細は公式 Docs。

### 帰結（うちの運用判断）

- パスを subprocess と Claude tool の両方から守るには **Permission `Read`/`Edit` deny** を書けば足りる（sandbox にマージされる）。**write 防御は必ず `Edit(...)`**（`Write(...)` は組み込み Write tool に無効＝`D3`）。
- **2 つの deny リストを丸ごと同期する必要はない**。read は Permission deny が自動マージ（`sandbox.denyRead` への複製は冗長）、write は sandbox allowlist が home を元から塞ぐ（home 系 `sandbox.denyWrite` は冗長で、実効を持つのは allow 内の例外＝`~/.gnupg/*`・cwd 内のみ）。
- **冗長な sandbox 列挙は意図的に残す**: 「sandbox config 単体で何が遮断されるか」が明示され、Permission 層を取り違えても安全側に倒れるため。

## 検証済み delta（インデックス）

公式 Docs に明記が無い／読み落としやすい実機挙動。**仕様変更でドリフトしうる**ため、各行に**最終確認日と Claude Code バージョン**を記録する（その行を最後に真と確認した時点＝鮮度。「いつまで真だったか」の履歴ではない）。本文からは ID（`D1` 等）で参照する。permission を触るときは公式 Docs と実機で**再確認し、挙動が変わっていたらその行を上書き更新（日付・バージョン・内容）、不要になったら削除**する。**表は常に現状のみを映す**（経緯は git 履歴が持つので、古い記述を残して肥大化させない）。

| ID | 検証日 | CC ver | 挙動（要約） |
|----|--------|--------|-------------|
| `D1` | 2026-05-23 | 未記録 | Read/Edit deny が Permission 層でカバーする Bash コマンドは `cat`/`head`/`tail`/`sed` 等の**認識コマンドのみ**で、`xxd`/`od`/`wc`/`less`/`bat`/`more`/`strings` は漏れる。ただし **sandbox 内では Read deny が sandbox にマージされ全 read が OS 遮断されるので顕在化しない**。漏れるのは **unsandbox / `excludedCommands` 経路**で、対策は明示 Bash viewer deny（age.txt 参照）。`sed` は read-only 用途でも Edit 扱い。`allowRead` 内のパスは Read deny の Bash カバーが外れる |
| `D2` | 2026-05-25 | 2.1.150 | Bash matcher はシェルオペレータ（`&&` `;` `\|` 等）と `$(...)` を分解して各部に適用するが、**別パス名（`/bin/echo` 等）・インタプリタ包み（`sh -c` / `bash -c` / `python -c`）は取りこぼす**。`sh -c '<denied>'` 一発で deny を回避できる → Bash deny は「うっかり承認を防ぐ床」であって境界ではない（境界は sandbox） |
| `D3` | 2026-05-25 | 2.1.150 | **`Write(...)` deny は組み込み Write tool をブロックしない**。Write tool（作成/上書き）は Edit カテゴリで `Edit(...)` のみが縛る。`Write(...)` の実効は Bash redirect 遮断のみ。パス形式（`~/dir/**`/exact/`**/X`）で差は無く `Edit` の有無が全て。live-reload は file tool でも正常。実証: `Write(~/.kube/**)` のみ→作成が通り `Edit(~/.kube/**)` 追加→ブロック |

## ファイル別の保護方針

新しい機密パスを足すときは、まず**保護クラス**を決め、レシピを**丸ごと**適用する。層ごとに場当たりで一部だけ書くとドリフトして片方の層に穴が残る（過去の 1Password write 無防備・認証 dir の Claude-tool write 開放がこれ）。**write 防御は必ず `Edit(...)` を書く**（`Write(...)` は組み込み Write tool に無効＝`D3`）。

| クラス | 例 | レシピ |
|--------|-----|--------|
| **A. 全遮断ディレクトリ**（read も write も不可） | `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | Permission `Read(~/dir/**)` + `Edit(~/dir/**)`（read 自動マージで subprocess も。write は Edit で新規作成も止まる）。＋明示性で sandbox `denyRead`/`denyWrite`・`Write(~/dir/**)` も列挙 |
| **B. 公開 dotfile**（read 可・write 不可） | `~/.gitconfig` `~/.npmrc`（home） | Permission `Edit(~/file)`。Read deny は**書かない**。＋ sandbox `denyWrite`・`Write(~/file)` 列挙 |
| **C. 解放だが改ざん防止**（read 可・write 不可） | shell rc（`~/.bashrc` `~/.zshrc` `~/.config/fish`）、gpg conf | exact-file または `~/dir/**` で Permission `Edit`。＋ sandbox `denyWrite`（allow 内例外はここが実効）・`Write(...)` 列挙 |
| **D. 完全遮断**（unsandbox でも） | `~/.config/mise/age.txt`、秘密鍵 `*.pem` 等 | Permission `Read(~/file)` + `Read(//**/X)` + 全 viewer の `Bash` deny + sandbox `denyRead`。`Edit(//**/X)` で FS 全体 |
| **E. プロジェクト内 secret**（read 可・write 不可） | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` | Permission `Edit(**/X)`（組み込み Write tool）＋ `Write(**/X)`（Bash redirect）。両方書く |

| パス | Read | Write | 区分 |
|------|------|-------|------|
| `~/.gitconfig` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `~/.npmrc` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `.env` 等（プロジェクト内 secret） | 解放 | Permission `Edit(**/X)`（Write tool）＋ `Write(**/X)`（Bash redirect） deny | read 解放・write 防止 |
| `~/.config/mise/age.txt` | 全遮断（三層） | 全遮断 | 本丸完全遮断 |
| 秘密鍵 `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` | Permission `Read(//**/...)` で FS 全体遮断 | — | 明示 deny |
| `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | sandbox `denyRead` + Permission `Read(~/dir/**)` deny | sandbox `denyWrite` + Permission `Edit(~/dir/**)` deny（`Write(~/dir/**)` も併記、実効は Edit） | ディレクトリ全遮断（read/write とも subprocess + Claude tool） |
| `~/.docker` | dir 全体: sandbox `denyRead`／config.json: Permission `Read` deny | dir 全体: sandbox `denyWrite`／config.json: Permission `Edit`/`Write` deny | 認証実体 config.json を全経路遮断（他ファイルは Claude tool から読める） |
| `~/.netrc` | sandbox `denyRead` + Permission `Read` deny | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 認証情報遮断 |
| `~/.bashrc` `~/.zshrc` `~/.config/fish` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | rc 改ざん（ログイン時コード実行）防止 |
| `~/.gnupg`（conf 以外） | 解放（agent 通信・署名検証に必要） | sandbox `allowWrite` で許可。ただし `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` は sandbox `denyWrite` + Permission `Edit`/`Write` deny | 署名運用・設定改ざん防止 |

### 公開 dotfile（`~/.gitconfig` / `~/.npmrc`）

read を解放し、write のみ防御する。

- read 解放の理由: `~/.npmrc` は `min-release-age` 等のサプライチェーン防御や registry/proxy 設定を npm/pnpm subprocess に効かせるため（`denyRead` で塞ぐと機能しない）。`~/.gitconfig` は dotfiles で公開管理する設定で秘匿価値がない。
- write が即時攻撃面: `~/.npmrc` は `registry=` で install 先すり替え・`ignore-scripts=false`・`cafile=` で TLS バイパス・`min-release-age` 削除で防御無効化。`~/.gitconfig` は alias 注入や `core.sshCommand` で通常 git 操作時に任意コード実行。
- 規律: **read 解放したファイルに平文 secret を置かない**。`~/.npmrc` の認証トークンは環境変数参照（`_authToken=${NPM_TOKEN}`）で書き、`NPM_TOKEN` は op-cli / mise env で注入する。read 解放経路に技術的フォールバックは無く、平文 secret を置けば即漏洩しうる。

### 本丸完全遮断（`~/.config/mise/age.txt`）

`## SOPS`（README.md）の age 復号鍵。いかなる経路でも遮断する。

- sandbox `denyRead`（exact）→ bash subprocess（mise 含む）の物理遮断。
- Permission `Read(~/.config/mise/age.txt)` → Claude Read tool 直撃。
- Permission `Read`/`Edit`/`Write(//**/age.txt)` → FS 全体の `age.txt` をカバー（リネーム・別パス保険）。
- Permission `Bash(<viewer> *age.txt*)` を全 viewer（`cat`/`head`/`tail`/`less`/`bat`/`more`/`wc`/`sort`/`nl`/`tac`/`xxd`/`od`/`strings`）に展開 → Bash サイドチャネル遮断（Read deny がカバーしない viewer 漏れ `D1` の対策）。

`dangerouslyDisableSandbox: true`（unsandbox）でも Permission 層は維持される。`//**/age.txt` は `age.txt` 完全一致のみで、`age.txt.bak` 等の派生名はカバーしない。

### 秘密鍵・シークレット系

- 秘密鍵は Permission `Read(//**/*.pem)` `Read(//**/*.key)` `Read(//**/id_rsa)` `Read(//**/id_ed25519)` `Read(//**/id_ecdsa)` `Read(//**/id_dsa)` で FS 全体を遮断（sandbox マージで subprocess も OS レベル遮断）。`Read(//**/*.key)` は秘密鍵以外の `.key`（i18n キー等）も巻き込みうる。誤爆時は個別調整。
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため read 解放。書き換えは **`Edit` と `Write` の両方**で防止: `.env`/`.env.*`/`secrets/**`/`*secret*`/`*credential*`、project ローカル認証ファイルは `**/.npmrc`/`**/.netrc`。`Edit(**/X)` が Claude の組み込み Write/Edit tool を、`Write(**/X)` が subprocess の Bash redirect を塞ぐ（二経路。`D3`）。

## Bash コマンドの実行制御（auto-allow / git / gh）

`autoAllowBashIfSandboxed: true`（詳細は公式 sandboxing）:

- sandbox 内コマンドは **auto-allow**（`ask`/prompt 不到達）。`deny` は実行前評価で全経路に効く。`rm`/`rmdir` が `/`・home 直撃時のみ circuit breaker で prompt。
- → 純粋系コマンド（`dirname`/`basename`/`realpath`/`date` 等）の `allow` 列挙は冗長。`allow` が効くのは sandbox 外実行の `gh *` 系と、Bash 外の `WebFetch` だけ。

### git

permission ルールを置かない。read-only git は built-in 認識で allow 不要。write・破壊系は sandbox 内完結で auto-allow（`github.com` は `allowedDomains` 内なので push/fetch も）。`ask` は不到達なので無意味。破壊系は sandbox 境界＋`allowedDomains`（github 限定＝外部流出にならない）を信頼して容認。確実に止めたい操作は `deny` か PreToolUse hook。

### gh

gh は Go 製で **macOS Seatbelt 下で TLS 検証に失敗**する（`gcloud`/`terraform` も同様）。`sandbox.excludedCommands: ["gh *"]` で全 gh を sandbox 外実行させ、**permission flow に乗せる**（git と違い `allow`/`ask`/`deny` が厳密に効く）。

- **allow**: read 系（`gh pr view`/`list`/`diff`/`checks`、`gh issue view`/`list`、`gh repo view`、`gh run view`/`list`、`gh release view`/`list`、`gh search`、`gh label list`、`gh auth status`）＋ SKILL 用 write（`gh pr create`/`edit`/`comment`）。
- **ask**: `gh api *`（GET と書き込みを matcher で区別できないため一律）/ `gh workflow run *` / `gh run rerun *`。
- **deny**: `gh auth token`（トークン実値出力）/ `gh secret *` / `gh repo delete *` / `gh gist create *`（外部送信経路）/ `gh ssh-key *` / `gh gpg-key *`。
- `gh auth status` は完全一致 allow（トークンはマスク表示。ワイルドカードでないため `gh auth token` deny に波及しない）。
- `excludedCommands` は引数含めマッチさせるため**ワイルドカード必須**。`"gh pr create"`（完全一致形）は実呼び出し `gh pr create --title ...` に当たらず不発（sandbox 内実行のまま TLS 失敗）。`"gh *"` で全サブコマンドをカバー。

### 破壊系コマンドの deny（床であって境界ではない）

`sudo`/`su`/`rm -rf /`・`~`/`dd`/`defaults` 等の deny は **blocklist で原理的に airtight にできない**（matcher は別パス・`sh -c` 包みを取りこぼす＝`D2`）。実効を持つのは **sandbox ON か人間が `ask` を捌くとき**だけで、**unsandboxed × bypassPermissions × 注入入力**では床が抜ける。よって deny は「うっかり承認を防ぐ床」と位置づけ、変種網羅は狙わない（境界は sandbox）。

- **`chmod 777 *` は不採用**: sandbox 下で allowWrite 外への chmod は遮断され、床としても `chmod -R 777`・`chmod 0777` を取りこぼす。「効く気がするが穴だらけ」で偽の安心を与えるため。
- **`dd *` は維持**: 正規利用がなく誤爆コスト ≒ 0。sandbox を切った日に効く床。
- **`defaults write`/`delete`/`import` は採用**: `defaults` は cfprefsd デーモン（sandbox 外プロセス）経由で macOS 設定を変えるため、sandbox の filesystem 制限を貫通しうる数少ない「本物の」防御。設定削除・一括上書きも塞ぐ。

## bun のサプライチェーン対策

bun は `.npmrc` の `min-release-age` を読まない（[oven-sh/bun#22679](https://github.com/oven-sh/bun/issues/22679)）。`~/.bunfig.toml` の `[install] minimumReleaseAge` で別途設定する。単位は秒（`604800` = 7 日）。pnpm/npm の `min-release-age` は日単位。

### ccstatusline

statusLine / hooks で使う `ccstatusline` は `bunx -y @latest` を避け、`bun add -g ccstatusline@<固定版>` でグローバル導入し、コマンドを `ccstatusline --hook`（PATH 経由）にする。`@latest` の毎起動 fetch（UserPromptSubmit / PreToolUse / statusLine）はサプライチェーン攻撃経路になる。更新は `bun update -g ccstatusline`（`minimumReleaseAge` が効く）。PATH に `~/.bun/bin` が通っている前提。

## Sandbox 追加設定

### `enableWeakerNetworkIsolation: false`

macOS Sandbox 内のシステム TLS 信頼サービス（`com.apple.trustd.agent`）へのアクセスを許可するフラグ。`true` はセキュリティを低下させる。

- `true` が必要: `httpProxyPort` を MITM プロキシ + カスタム CA と併用し Go ベース CLI に TLS 検証させる環境。
- 本リポジトリ: MITM プロキシを使わないため `false`。gh の TLS 失敗は `excludedCommands: ["gh *"]`（sandbox 外実行）で回避する（「gh」参照）。

### npm install を sandbox 内で通す

sandbox は network を allowlist、write を cwd 中心の allowlist で絞るため、`npm install` には2点の明示許可が要る（実機で発覚）:

- **registry への egress**: `sandbox.network.allowedDomains` に取得先を列挙する。public の `registry.npmjs.org` に加え、scoped パッケージを引く社内 registry（`npm.flatt.tech`）も必要。無いと registry に到達できず install が失敗する。`~/.npmrc` の registry 設定自体は read 解放で効くが、**ネットワーク到達は allowedDomains が別ゲート**なので両方そろえる。
- **キャッシュ書き込み**: `sandbox.filesystem.allowWrite` に `~/.npm/_cacache`（npm の content-addressable cache）を追加する。sandbox は cwd 外への write を塞ぐため、無いと install がキャッシュ書き込みで失敗する。`~/.npm/_logs` は Claude Code デフォルトで許可済みだが `_cacache` は別途必要。他の `~/.npm` 配下書き込みで失敗するなら `~/.npm` に広げる。
- broad な `allowedDomains` は exfiltration 経路になりうる（公式 sandboxing の警告）。registry は必要最小限に絞る。

### GnuPG 署名コミット

署名コミット（`commit.gpgsign=true`、OpenPGP 鍵）は sandbox 外常駐の gpg-agent と Unix socket で通信して署名する（いずれも実機検証で確定）:

- **`allowUnixSockets: ["~/.gnupg/S.gpg-agent"]` は必須**。外すと agent 接続不可で署名できない（`can't connect to the agent`）。socket パスは `gpgconf --list-dirs agent-socket` と一致させる。
- 署名「作成」はクライアント側の `~/.gnupg` 書き込み不要（agent が担う）。一方「検証」（`git verify-commit` / `git log --show-signature`）は trustdb ロックで `~/.gnupg` 書き込みを要求するため、検証を sandbox 内で通すなら `allowWrite: ~/.gnupg` を維持。
- **ハードニング**: `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` の改ざん（特に `pinentry-program` 書き換えによるパスフレーズ窃取）を塞ぐ。**2 経路必要**: sandbox `denyWrite`（subprocess）＋ Permission **`Edit` deny**（組み込み Write/Edit tool。`Write` 併記するが実効は Edit＝`D3`）。秘密鍵 `private-keys-v1.d` も `Edit` deny を併記。
- **注意**: socket を塞ぐと gpg-agent が停止し sandbox 内から再起動できない（fork が Seatbelt で制限）。復活は sandbox 外で `gpgconf --launch gpg-agent`。

## 設定変更時の検証

permission は挙動が直感に反するため、**推測せず公式 Docs ＋実機で検証する**（`.claude/rules/claude-code-settings.md`）。

- ダミーファイルを `$TMPDIR/<test>/` または cwd（`./<test>/`）に作り、Bash と Read/Edit tool で deny されるか確認する（どちらも sandbox 書込可）。
- 設定は live reload で同セッション内に反映される（Bash deny・sandbox filesystem・Read/Edit/Write tool deny いずれも実機確認）。**tool の write 防御は必ず `Edit(...)` deny で試す**。`Write(...)` は組み込み Write tool に効かないため、`Write` だけで試すと「効かない」と誤認する（`D3`）。
- built-in deny の有無を確認する時は、sandbox `denyRead` と Permission `Read(...)` deny の**両方**を外してから確認する（Permission deny が sandbox にマージされ `denyOnly` に出るため、片方だけ外すと出自を誤認する）。
- 一時編集した settings.json は完全復元する。Bash の `cp` 復元は sandbox 自己保護（`denyWithinAllow` に settings.json 実体）で拒否されるため、Edit/Write tool で戻す。
- 破壊的副作用に注意: socket（`allowUnixSockets`）を外す検証は gpg-agent を停止させ sandbox 内から復活できない。検証後は sandbox 外で `gpgconf --launch gpg-agent`。

## 関連

- 公式 Docs（仕様の一次情報・毎回参照）: [permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing)
- `.claude/rules/claude-code-settings.md`: 設定変更時の鉄則（公式 Docs 参照・実機検証）
- `## SOPS`（README.md）: age.txt の用途
- `## AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定
