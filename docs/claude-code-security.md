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

## Bash matcher の挙動

- `*` はスラッシュ `/` と leading dot（`.env` `.npmrc` 等）を貫通する fnmatch 系。
- コマンドライン全体を評価する。`head -c 100 ~/.gitconfig` のようなオプション先頭呼び出しも `Bash(head *.gitconfig)` でマッチする。
- シェルオペレータ（`&&` `||` `;` `|`）でサブコマンドに分割し、個別評価する。各サブコマンドが独立してルールにマッチする必要がある。
- prefix allow（`Bash(gh pr list *)` 等）は複合コマンドにマッチしにくい。`gh pr list ... ; echo ...` のように suffix を付けると allow が外れて prompt/denied になる。allow の恩恵を受けるには単体で呼ぶ。
- 中間ドットサフィックス（`.env.local` 等）は `*.env`（末尾）にも `.env.*`（先頭）にもマッチしない。`*.X.*` を別途用意する。
- Bash redirect（`echo X > path`）は対応する `Write(...)` deny で評価される。
- 読み取り専用コマンド（`ls` `cat` `echo` `pwd` `head` `tail` `grep` `find` `wc` `which` `diff` `stat` `du` `cd` `git` の読み取り + `sort` `uniq`）は built-in 認識で、allow への明示は不要。

## ファイル別の保護方針

| パス | Read | Write | 区分 |
|------|------|-------|------|
| `~/.gitconfig` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `~/.npmrc` | 解放 | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 公開 dotfile |
| `.env`（プロジェクト内） | 解放 | Permission `Write(**/.env)` deny | read 解放・write 防止 |
| `~/.config/mise/age.txt` | 全遮断（三層） | 全遮断 | 本丸完全遮断 |
| 秘密鍵 `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` | Permission `Read(//**/...)` で FS 全体遮断 | — | 明示 deny |
| `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.kube` `~/.config/1Password` `~/.gnupg/private-keys-v1.d` `~/.docker` | sandbox `denyRead` + Permission `Read` deny | sandbox `denyWrite` | ディレクトリ遮断 |
| `~/.netrc` | sandbox `denyRead` + Permission `Read` deny | sandbox `denyWrite` + Permission `Edit`/`Write` deny | 認証情報遮断 |

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
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため解放のまま。書き換えのみ `Write(**/.env)` で防止する。

## Bash コマンドの実行制御（auto-allow / git / gh）

`autoAllowBashIfSandboxed: true`（本リポジトリの設定）の効き方:

- sandbox 内で完結する Bash コマンドは **auto-allow** され、`ask` / default prompt は**到達しない**。`ask` / `allow` が評価されるのは、sandbox で fall back したコマンドか `excludedCommands` で sandbox 外実行されたコマンドだけ。
- **`deny` は sandbox 実行前に評価され、全経路で常に効く**。確実に止めたいものは `deny` に書く（`ask` では止まらない）。
- `rm` / `rmdir` が `/`・home 等を直撃する場合のみ circuit breaker で prompt。

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

## 設定変更時の検証

permission matcher は挙動が直感に反するため、推測せず実機検証する。

- ダミーファイルを `$TMPDIR/<test>/` または `~/ghq/<test>/` に作り、Bash と Read tool の両方で deny されるか確認する。
- 設定は live reload で同セッション内に反映される。
- built-in deny の有無を確認する時は、sandbox `denyRead` と Permission `Read(...)` deny の両方を外してから確認する（Permission deny が sandbox にマージされて `denyOnly` に出るため、片方だけ外すと出自を誤認する）。
- 一時編集した settings.json は完全復元する。

## 関連

- `## SOPS`（README.md）: age.txt の用途
- `## AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定
