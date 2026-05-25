# Claude Code のセキュリティ設定

`~/.claude/settings.json` の Sandbox / Permission 設定の仕様と、各ファイルの保護方針をまとめる。脅威モデルはプロンプトインジェクションと Shai-Hulud 型サプライチェーン攻撃。設定の実体は `dotfiles/.claude/settings.json`。

## Sandbox と Permission の二層モデル

| レイヤ | 対象 | 設定箇所 |
|--------|------|----------|
| Sandbox | bash サブプロセス全体（git / mise / node / 任意の外部プロセス）を OS レベルで制御 | `sandbox.filesystem.denyRead` / `denyWrite` / `allowRead` / `allowWrite` |
| Permission (Read/Edit/Write) | Claude の Read/Edit/Write tool + Bash 認識ファイルコマンド | `permissions.deny: Read(...)` 等 |
| Permission (Bash) | Claude が叩く Bash 引数文字列 | `permissions.deny: Bash(...)` |

仕様:

- **built-in deny は存在しない**。Sandbox の default read は「コンピュータ全体読める」。`~/.aws/credentials` や `~/.ssh/` すら、明示的に `denyRead` しない限り読める。読ませたくないものは自分で列挙する。
- **Permission の Read/Edit deny は sandbox config にマージされ、bash subprocess にも適用される**。glob 形式（`Read(//**/*.pem)`）もマージされ、subprocess の read を OS レベルで遮断する。
- **Sandbox の denyRead/denyWrite は Claude の Read/Edit/Write tool には効かない**。built-in file tools は permission system を直接使い、sandbox を通らない。
- 実機 system prompt の `read.denyOnly` は「sandbox denyRead + Permission Read/Edit deny」の合算。Permission rule 由来のエントリはチルダ形式のみ出て、絶対パス形式は出ない。

帰結:

- あるパスを subprocess と Claude tool の両方から守るには、Permission の Read/Edit/Write deny を書けば足りる（sandbox にマージされる）。
- sandbox `denyWrite` だけのパスは Claude tool 経由の write を防げない。write 防御には Permission `Edit`/`Write` deny を併記する。
- **Claude tool の write を縛るのは `Edit(...)` deny**（後述「組み込み Write tool は Edit ルールで制御される」）。公式 Docs「Edit rules apply to all built-in tools that edit files」のとおり、組み込みの **Write tool も Edit カテゴリ**として扱われる。`Write(...)` deny は組み込み Write tool をブロックしない（実機確認）。脅威モデル（プロンプトインジェクション＝Claude の Write/Edit tool が実行主体）に効かせるには、防御したいパスに `Edit(...)` を必ず書く。

### Read は自動マージ / Write は allowlist（層の非対称）

2つの deny リストを丸ごと同期させる必要はない。層の効き方が非対称なため:

- **Read**: `permissions.deny: Read`/`Edit` は sandbox config に**自動マージ**され subprocess にも効く（2026-05-24 実機確認）。よって Permission `Read` deny を書けば subprocess + Claude tool の両方が塞がる。`sandbox.denyRead` への複製は**機能的には冗長**。
- **Write**: sandbox の write は denylist ではなく **allowlist**（`allowOnly`）。書けるのは cwd（`.`）・`$TMPDIR`・`~/ghq`・`~/.gnupg` 等**だけ**で、**home 直下（`~/.ssh` `~/.zshrc` `~/.gitconfig` 等）は最初から subprocess 書込不可**（実機確認: home への `rm` が sandbox 下で `Operation not permitted`）。よって home 系の `sandbox.denyWrite` も subprocess に対しては**冗長**で、実効を持つのは **allow 内に空いた穴を塞ぐ例外**だけ（`~/.gnupg/private-keys-v1.d`・gpg conf は許可された `~/.gnupg` の中、`settings.json` は許可された `.` の中）。Claude tool の write は別途 Permission `Edit`/`Write` deny が必要。

**冗長分は意図的に残す**: 上記のとおり `sandbox.denyRead`/`denyWrite` の多くは Permission deny / allowlist と重複するが、「sandbox config 単体で何が遮断されるか」が明示され、Permission 層を取り違えても安全側に倒れるため、削らず列挙を維持する方針。

## Permission パス書式

| 書式 | 解釈 |
|------|------|
| `~/path` | home 相対 |
| `//path` | 絶対パス（leading double-slash） |
| `/path` | プロジェクトルート相対 |
| `path`, `./path` | カレントディレクトリ相対 |
| `**/X` | gitignore セマンティクス、cwd 配下を再帰 |
| `//**/X` | ファイルシステム全体を再帰 |

- `Read(/Users/me/foo)` は絶対パスではなく `<project-root>/Users/me/foo` と解釈される。home を狙うなら `~/path` か `//Users/me/path` を使う。
- この書式は Permission rule 専用。Sandbox filesystem のパス prefix は別仕様（`/`=絶対、`~/`=home、prefix なし=相対）。

## Read/Edit/Write deny の Bash カバー範囲

- `~/path` 形式・`//**/` 形式の Read/Edit/Write deny は、Claude tool に加え Bash の `cat`/`head`/`tail`/`sed` 等の認識ファイルコマンドにも適用される。
- `xxd`/`od`/`wc`/`less`/`bat`/`more`/`strings` 等の viewer は Read deny でカバーされない。完全遮断には Bash viewer deny を別途列挙する。
- `sed` は read-only 用途（`sed -n '1,3p' file`）でも Edit 扱いで、working directory 制限が走る。
- `allowRead` に入れたパスは Permission Read deny の Bash カバーが外れる（sandbox 層で OS read が許可されるため）。

## 組み込み Write tool は Edit ルールで制御される（実機検証）

公式 Docs:

> Edit rules apply to all built-in tools that edit files.

組み込みの **Write tool（新規作成・上書き）も「Edit カテゴリ」**として扱われる。したがって Claude の Write/Edit tool による書き込みを縛るのは **`Edit(...)` deny** であり、**`Write(...)` deny は組み込み Write tool をブロックしない**（2026-05-25 実機検証で確定）。

| ルール | 組み込み Write tool（作成/上書き） | 組み込み Edit tool |
|--------|-----------------------------------|-------------------|
| `Edit(path)` | **ブロック** | **ブロック** |
| `Write(path)` のみ | 素通り | （Edit には無関係） |

実機での確認（同一パス形式 `~/dir/**` で対照）:

- `Write(~/.kube/**)` のみ → Write tool で `~/.kube/x` 作成が**通った**。
- `Edit(~/.kube/**)` 追加 → 同じ作成が**ブロックされた**。
- `Edit(~/.config/fish/**)`・`Edit(~/.gnupg/gpg-agent.conf)` も Write/Edit tool をブロック。

含意:

- **防御したいパスには必ず `Edit(...)` を書く**。`Write(...)` は組み込み Write tool に効かないので、単独では防御にならない（明示性のため併記するのは可。実効は Edit が担う）。
- パス形式（`~/dir/**`・exact-file・`**/X`）による効き方の差は無い。当初「形式依存」と見えたのは、ブロックした例にだけ `Edit` ルールがあったことによる誤認。`**/.env` 等が Write tool を素通りしていたのも cwd 相対だからではなく `Edit(**/.env)` が無かったため（現在は追加済み）。
- **live-reload は file tool でも正常**。`Edit` ルールは同セッション内で追加しても即反映される（実機確認）。当初の「live-reload 不安定」も同じ Write/Edit 取り違えによる誤診だった。
- 認証系ディレクトリは Read 遮断済みでも、Write tool の**新規作成**（read を伴わない）を塞ぐため `Edit(~/dir/**)` が必要。`Write(~/dir/**)` だけでは不十分。

## Bash matcher の挙動

- `*` はスラッシュ `/` と leading dot（`.env` `.npmrc` 等）を貫通する fnmatch 系。
- コマンドライン全体を評価する。`head -c 100 ~/.gitconfig` のようなオプション先頭呼び出しも `Bash(head *.gitconfig)` でマッチする。
- シェルオペレータ（`&&` `||` `;` `|`）とコマンド置換 `$(...)` でサブコマンドに分割し、個別評価する。各サブコマンドが独立してルールにマッチする必要がある（`true && X`・`x=$(X)` とも deny が当たることを実機確認）。
- **すり抜ける形（重要）**: バイナリ名の別名化（`/bin/echo`・`/usr/bin/X` 等の別パス）とインタプリタ包み（`sh -c '...'`・`bash -c`・`python -c`・`node -e`）はマッチしない。`sh -c '<denied コマンド>'` 一発で deny リスト全体を無力化できる（実機確認）。
- prefix allow（`Bash(gh pr list *)` 等）は複合コマンドにマッチしにくい。`gh pr list ... ; echo ...` のように suffix を付けると allow が外れて prompt/denied になる。allow の恩恵を受けるには単体で呼ぶ。
- 中間ドットサフィックス（`.env.local` 等）は `*.env`（末尾）にも `.env.*`（先頭）にもマッチしない。`*.X.*` を別途用意する。
- Bash redirect（`echo X > path`）は対応する `Write(...)` deny で評価される。
- 読み取り専用コマンド（`ls` `cat` `echo` `pwd` `head` `tail` `grep` `find` `wc` `which` `diff` `stat` `du` `cd` `git` の読み取り + `sort` `uniq`）は built-in 認識で、allow への明示は不要。

## ファイル別の保護方針

新しい機密パスを足すときは、まず**保護クラス**を決め、そのレシピを**丸ごと**適用する。層ごとに場当たりで一部だけ書くと、片方の層に穴が残る（過去の 1Password write 無防備・認証 dir の Claude-tool write 開放はこのドリフトが原因）。

**Claude tool の write 防御は必ず `Edit(...)` を書く**（「組み込み Write tool は Edit ルールで制御される」参照）。`Write(...)` は組み込み Write tool に効かないので、防御目的では `Edit(...)` が load-bearing。

| クラス | 例 | レシピ |
|--------|-----|--------|
| **A. 全遮断ディレクトリ**（read も write も不可） | `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | Permission `Read(~/dir/**)` + `Edit(~/dir/**)`（read は自動マージで subprocess も。Claude tool write は `Edit` で塞ぐ。新規作成も Edit で止まる）。＋ 明示性のため sandbox `denyRead`/`denyWrite`・`Write(~/dir/**)` も列挙 |
| **B. 公開 dotfile**（read 可・write 不可） | `~/.gitconfig` `~/.npmrc`（home） | Permission `Edit(~/file)`。Read deny は**書かない**。＋ sandbox `denyWrite`・`Write(~/file)` 列挙 |
| **C. 解放だが改ざん防止**（read 可・write 不可の個別/allow 内） | shell rc（`~/.bashrc` `~/.zshrc` `~/.config/fish`）、gpg conf | exact-file または `~/dir/**` で Permission `Edit`。＋ sandbox `denyWrite`（allow 内例外はここが実効）・`Write(...)` 列挙 |
| **D. 完全遮断**（unsandbox でも） | `~/.config/mise/age.txt`、秘密鍵 `*.pem` 等 | Permission `Read(~/file)` + `Read(//**/X)` + 全 viewer の `Bash` deny + sandbox `denyRead`。`Edit(//**/X)` で FS 全体 |
| **E. プロジェクト内 secret**（read 可・write 不可） | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` | Permission `Edit(**/X)`（組み込み Write tool を塞ぐ）＋ `Write(**/X)`（Bash redirect を塞ぐ）。両方書く |

注意:

- パス形式（`~/dir/**`・exact-file・`**/X`）で効き方は変わらない。要は **`Edit(...)` が書いてあるか**。Read 遮断済みディレクトリでも Write tool の新規作成を止めるため `Edit(~/dir/**)` は必須（`Write` だけでは不十分）。
- `Write(...)` の唯一の実効は **Bash redirect（`echo X > path`）の遮断**。組み込み Write/Edit tool には効かない。

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
| `~/.gnupg`（conf 以外） | 解放（agent 通信・署名検証に必要） | sandbox `allowWrite` で許可。ただし `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` は sandbox `denyWrite` + Permission `Edit`/`Write` deny（Claude tool も遮断） | 署名運用・設定改ざん防止 |

### 公開 dotfile（`~/.gitconfig` / `~/.npmrc`）

read を解放し、write のみ防御する。

read 解放の理由:

- `~/.npmrc`: `min-release-age` 等のサプライチェーン防御や registry/proxy 設定を npm/pnpm subprocess に効かせるため。`denyRead` で塞ぐとこれらが機能しない。
- `~/.gitconfig`: dotfiles で公開管理する設定で秘匿価値がない。

write を両経路で防ぐ:

- sandbox `denyWrite` → subprocess の書き換え。
- Permission `Edit`/`Write` deny → Claude tool の書き換え（sandbox を通らないため必須）。

write が即時攻撃面である理由:

- `~/.npmrc`: `registry=` で install 先すり替え、`ignore-scripts=false` で install scripts 実行、`cafile=` で TLS 検証バイパス、`min-release-age` 削除で防御無効化。
- `~/.gitconfig`: alias 注入や `core.sshCommand` で、通常の git 操作時に任意コード実行。

規律: read 解放したファイルに平文 secret を置かない。`~/.npmrc` の認証トークンは環境変数参照（`_authToken=${NPM_TOKEN}` の形式）で書き、`NPM_TOKEN` は op-cli / mise env 等で注入する。read 解放経路に技術的フォールバックは無く、平文 secret を置けば即漏洩しうる。

### 本丸完全遮断（`~/.config/mise/age.txt`）

`## SOPS`（README.md）の age 復号鍵。いかなる経路でも遮断する。

- sandbox `denyRead`（exact）→ bash subprocess（mise 含む）の物理遮断。
- Permission `Read(~/.config/mise/age.txt)` → Claude Read tool 直撃。
- Permission `Read`/`Edit`/`Write(//**/age.txt)` → FS 全体の `age.txt` をカバー（リネーム・別パス保険）。
- Permission `Bash(<viewer> *age.txt*)` を全 viewer（`cat`/`head`/`tail`/`less`/`bat`/`more`/`wc`/`sort`/`nl`/`tac`/`xxd`/`od`/`strings`）に展開 → Bash サイドチャネル。

`dangerouslyDisableSandbox: true`（unsandbox）でも Permission 層は維持される。`//**/age.txt` はファイル名が `age.txt` に完全一致するもののみ対象で、`age.txt.bak` 等の派生名はカバーしない。

### 秘密鍵・シークレット系

built-in deny が無いため、`denyRead` か Permission `Read` deny に明示しない限り、subprocess・Claude tool の双方から読める。

- 秘密鍵は Permission `Read(//**/*.pem)` `Read(//**/*.key)` `Read(//**/id_rsa)` `Read(//**/id_ed25519)` `Read(//**/id_ecdsa)` `Read(//**/id_dsa)` で FS 全体を遮断（sandbox マージで subprocess も OS レベル遮断）。
- `Read(//**/*.key)` は秘密鍵以外の `.key`（i18n キー等）も巻き込みうる。誤爆時は個別調整する。
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため解放のまま。書き換えは **`Edit` と `Write` の両方**で防止する: `.env` / `.env.*`（`.env.local` 等）/ `secrets/**` / `*secret*` / `*credential*`、project ローカルの認証ファイルは `**/.npmrc` / `**/.netrc`。
- **役割分担**: `Edit(**/X)` が **Claude の組み込み Write/Edit tool** を塞ぎ、`Write(**/X)` が **subprocess の Bash redirect** を塞ぐ（組み込み Write tool には効かない）。両方書いて二経路をカバーする（「組み込み Write tool は Edit ルールで制御される」参照）。

## Bash コマンドの実行制御（auto-allow / git / gh）

`autoAllowBashIfSandboxed: true`（本リポジトリの設定）の効き方:

- sandbox 内で完結する Bash コマンドは **auto-allow** され、`ask` / default prompt は**到達しない**。`ask` / `allow` が評価されるのは、sandbox で fall back したコマンドか `excludedCommands` で sandbox 外実行されたコマンドだけ。
- **`deny` は sandbox 実行前に評価され、全経路で常に効く**。確実に止めたいものは `deny` に書く（`ask` では止まらない）。
- `rm` / `rmdir` が `/`・home 等を直撃する場合のみ circuit breaker で prompt。
- このため **sandbox 内で完結する純粋系コマンド（`dirname`/`basename`/`realpath`/`date` 等）を `allow` に列挙するのは冗長**（auto-allow で通るので `allow` の有無は挙動に影響しない）。`allow` が実効を持つのは sandbox 外実行される `gh *` 系と、Bash でない `WebFetch` だけ。

### git

permission ルールを置かない。

- read-only git（`status` / `log` / `diff` / `show` / `branch` 一覧 / `rev-parse` / `stash list` 等）は built-in 認識で allow 不要。
- write・破壊系（`add` / `switch` / `push` / `reset` / `rebase` / `checkout` / `clean` 等）は sandbox 内で完結し auto-allow される。`github.com` は `allowedDomains` 内なので `push`/`fetch` も auto-allow。**`ask` は到達しないため無意味**。
- 破壊系は sandbox 境界＋`allowedDomains`（github 限定＝ローカル/自リポジトリ破壊に留まり外部流出にならない）を信頼して auto-allow を容認する。確実に止めたい操作があれば `deny` か PreToolUse hook を使う。

### gh

gh は Go 製のため **macOS Seatbelt 下で TLS 検証に失敗**する（`gcloud`/`terraform` も同様の既知仕様）。sandbox 内では全 gh コマンドがネットワークに到達できない。公式の対処は `excludedCommands` で sandbox 外実行させること。

- `sandbox.excludedCommands: ["gh *"]` で全 gh を sandbox 外へ出す。sandbox 外の gh は **permission flow に乗る**ため、git と異なり `allow`/`ask`/`deny` が厳密に効く。
- **allow**: read 系（`gh pr view`/`list`/`diff`/`checks`、`gh issue view`/`list`、`gh repo view`、`gh run view`/`list`、`gh release view`/`list`、`gh search`、`gh label list`、`gh auth status`）＋ SKILL 用 write（`gh pr create`/`edit`/`comment`）。
- **ask**: `gh api *`（GET と書き込みを matcher で区別できないため一律）/ `gh workflow run *` / `gh run rerun *`。
- **deny**: `gh auth token`（トークン実値を出力）/ `gh secret *` / `gh repo delete *` / `gh gist create *`（外部送信経路）/ `gh ssh-key *` / `gh gpg-key *`。
- `gh auth status` は完全一致 allow。トークンはマスク表示で実値を出さず、ワイルドカードでないため `gh auth token`（deny）に波及しない。

### 破壊系コマンドの deny（床であって境界ではない）

`sudo` / `su` / `rm -rf /`・`~` 系 / `dd` / `defaults` などの deny は、**blocklist であり原理的に airtight にできない**（matcher は別パス・`sh -c` 包みを取りこぼす。「Bash matcher の挙動」参照）。実効を持つのは **sandbox ON か、人間が `ask` を捌くとき**のどちらかが成立している場合だけで、**unsandboxed × bypassPermissions × 注入されうる入力**の三つ揃いでは床が抜ける。よって deny リストは「境界」ではなく「うっかり承認を防ぐ床」と位置づけ、変種の網羅は狙わない（sandbox を実防御線とする）。

この方針で整理した結果:

- **`chmod 777 *` は不採用**。sandbox 下では allowWrite 外への chmod はそもそも遮断され、床としても `chmod -R 777`・`chmod 0777` 等を取りこぼす。「効いている気がするが穴だらけ」で偽の安心を与えるため、列挙しない。
- **`dd *` は維持**。本ワークフローで正規に使う場面がなく誤爆コスト ≒ 0 のため、sandbox を切った日に効く床として残す。
- **`defaults write` / `delete` / `import` は採用**。`defaults` は cfprefsd デーモン（sandbox 外プロセス）経由で macOS 設定を変えるため、sandbox の filesystem 制限を貫通しうる数少ない「本物の」防御。`write` だけでなく設定削除（`delete`）・一括上書き（`import`）も塞ぐ。

`excludedCommands` は引数を含めてマッチさせるため**ワイルドカードが必須**。`"gh pr create"`（完全一致形）は引数付きの実呼び出し `gh pr create --title ...` にマッチせず**不発**になる（sandbox 内実行のまま TLS 失敗）。`"gh *"` で全サブコマンドをカバーする。

## bun のサプライチェーン対策

bun は `.npmrc` の `min-release-age` を読まない（[oven-sh/bun#22679](https://github.com/oven-sh/bun/issues/22679)）。`~/.bunfig.toml` の `[install] minimumReleaseAge` で別途設定する。単位は秒（`604800` = 7 日）。pnpm/npm の `min-release-age` は日単位。

### ccstatusline

statusLine / hooks で使う `ccstatusline` は `bunx -y @latest` を避け、`bun add -g ccstatusline@<固定版>` でグローバル導入し、コマンドを `ccstatusline --hook`（PATH 経由）にする。`@latest` の毎起動 fetch（UserPromptSubmit / PreToolUse / statusLine）はサプライチェーン攻撃経路になる。更新は `bun update -g ccstatusline`（`minimumReleaseAge` が効く）。PATH に `~/.bun/bin` が通っている前提。

## Sandbox 追加設定

### `enableWeakerNetworkIsolation: false`

macOS Sandbox 内のシステム TLS 信頼サービス（`com.apple.trustd.agent`）へのアクセスを許可するフラグ。`true` はセキュリティを低下させる。

- `true` が必要: `httpProxyPort` を MITM プロキシ + カスタム CA と併用し、`gh`/`gcloud`/`terraform` 等の Go ベース CLI に TLS 検証させる環境。
- 本リポジトリ: MITM プロキシを使わないため `false`。gh の TLS 失敗は `enableWeakerNetworkIsolation` ではなく `excludedCommands: ["gh *"]`（sandbox 外実行）で回避する（「Bash コマンドの実行制御 / gh」参照）。

### GnuPG 署名コミット

署名コミット（`commit.gpgsign=true`、OpenPGP 鍵）は sandbox 外に常駐する gpg-agent と Unix socket で通信して署名する。必要設定と根拠（いずれも実機検証で確定）:

- **`allowUnixSockets: ["~/.gnupg/S.gpg-agent"]` は必須**。外すと agent 接続不可で署名できない（`can't connect to the agent`）。socket パスは `gpgconf --list-dirs agent-socket` と一致させる。
- **署名の実体は agent が担う**ため、署名「作成」自体はクライアント側の `~/.gnupg` 書き込みを必要としない。一方で署名「検証」（`git verify-commit` / `git log --show-signature`）は trustdb ロック取得で `~/.gnupg` 書き込みを要求するため、検証を sandbox 内で通すなら `allowWrite: ~/.gnupg` を維持する。
- **ハードニング**: 署名で読むだけの `gpg-agent.conf` / `gpg.conf` / `dirmngr.conf` を保護し、最大リスク（`gpg-agent.conf` の `pinentry-program` 書き換えによるパスフレーズ窃取）を塞ぐ。`allowWrite: ~/.gnupg` は検証のため維持。**保護は2経路必要**: sandbox `denyWrite`（subprocess）＋ Permission **`Edit` deny**（組み込み Write/Edit tool を統括。`Write` も併記するが実効は Edit）。sandbox `denyWrite` だけだと Claude tool で conf を書き換えられるため、exact-file の `Edit` deny を併記する。秘密鍵 `private-keys-v1.d` も同様に `Edit` deny を併記（`Write` だけでは Write tool を塞げない）。三層遮断済みで流出経路はない。
- **注意**: socket を塞ぐと gpg-agent が停止し、sandbox 内からは再起動できない（agent の fork が Seatbelt で制限される）。復活は sandbox 外で `gpgconf --launch gpg-agent`。

## 設定変更時の検証

permission matcher は挙動が直感に反するため、推測せず実機検証する。

- ダミーファイルを `$TMPDIR/<test>/` または `~/ghq/<test>/` に作り、Bash と Read tool の両方で deny されるか確認する。
- 設定は live reload で同セッション内に反映される（Bash deny・sandbox filesystem・Read/Edit/Write tool の permission deny いずれも実機確認）。tool の write 防御を検証する際は **`Edit(...)` deny で試す**こと。`Write(...)` deny は組み込み Write tool に効かないため、`Write` だけで試すと「効かない」と誤認する（実際に一度この取り違えで live-reload 不安定と誤診した）。
- built-in deny の有無を確認する時は、sandbox `denyRead` と Permission `Read(...)` deny の両方を外してから確認する（Permission deny が sandbox にマージされて `denyOnly` に出るため、片方だけ外すと出自を誤認する）。
- 一時編集した settings.json は完全復元する。Bash の `cp` での復元は sandbox の自己保護（`denyWithinAllow` に settings.json 実体）で拒否されるため、Edit/Write tool で戻す。
- 破壊的副作用に注意: socket（`allowUnixSockets`）を外す検証は gpg-agent を停止させ sandbox 内から復活できない。検証後は sandbox 外で `gpgconf --launch gpg-agent`。

## 関連

- `## SOPS`（README.md）: age.txt の用途
- `## AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定
