# Claude Code のセキュリティ設定

> **仕様の一次情報は公式 Docs**（[permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing)）。仕様はバージョンで変わりドリフトするため、permissions / sandbox を変更する前に必ず公式 Docs を参照する（`.claude/rules/claude-code-settings.md` で常設指示）。本書は **dotfiles 固有の判断**と、**公式から自明でない検証済み挙動（delta、検証日つき）**だけを書く。仕様の写経はしない。

脅威モデル: プロンプトインジェクション（実行主体は Claude の Bash / Write / Edit tool）と Shai-Hulud 型サプライチェーン攻撃。設定の実体は `dotfiles/.claude/settings.json`。

## 設計の前提（公式仕様のうち、判断の土台になる点だけ）

詳細は公式 Docs に譲り、ここでは**うちの判断が依存する核**だけを明記する（出典: permissions / sandboxing）:

- **Sandbox（OS 強制）は Bash subprocess とその子だけ**に効く。**Permission rule は全 tool**（Read/Edit/Write/Bash/WebFetch…）に効く。別レイヤ。
- **built-in deny は無い**。sandbox の default は全 read 可（`~/.aws/credentials`・`~/.ssh/` すら読める）。塞ぐパスは自分で `denyRead` / Permission `Read` deny に列挙する。
- **Permission の `Read`/`Edit` deny は sandbox 境界にマージ**され subprocess にも効く。逆に **sandbox の `denyRead`/`denyWrite` は Claude の Read/Edit/Write tool には効かない**（tool は permission を直接使う）。
- **「Edit rules apply to all built-in tools that edit files」**（Docs 原文）。→ 組み込み **Write tool も Edit カテゴリ**。Claude tool の write を縛るのは **`Edit(...)`**（`Write(...)` は組み込み Write tool に無効。実機挙動は `D3`）。
- **`Read` deny は同一パスの Edit tool もブロックする**（新規作成を含む。2.1.208+）。ただし **Write / NotebookEdit は覆わない**ため、「どの tool にも変更させない」パスには `Edit(...)` deny を必ず併記する（Docs 原文: "Write and NotebookEdit aren't covered, so add an `Edit` deny rule for paths no tool may change"）。read 遮断だけで write も止まったと考えないこと。
- sandbox の **write は allowlist**（cwd `.`・`$TMPDIR`・`~/.gnupg`・`~/.npm`（cache/logs）等のみ可）、**read は denylist**（全許可からの除外）。
- Permission パス書式の要注意点: **`/path` は絶対でなくプロジェクトルート相対**（絶対は `//path`、home は `~/path`）。取り違えると home 配下を全く守れない。書式詳細は公式 Docs。

### 帰結（うちの運用判断）

- パスを subprocess と Claude tool の両方から守るには **Permission `Read`/`Edit` deny** を書けば足りる（sandbox にマージされる）。**write 防御は必ず `Edit(...)`**（`Write(...)` は組み込み Write tool に無効＝`D3`）。
- **2 つの deny リストを丸ごと同期する必要はない**。read は Permission deny が自動マージ（`sandbox.denyRead` への複製は冗長）、write は sandbox allowlist が home を元から塞ぐ（home 系 `sandbox.denyWrite` は冗長で、実効を持つのは allow 内の例外＝`~/.gnupg/*`・cwd 内のみ）。
- **冗長な sandbox 列挙は意図的に残す**: 「sandbox config 単体で何が遮断されるか」が明示され、Permission 層を取り違えても安全側に倒れるため。
- **Permission 層に `Write(...)` deny は書かない**（`D3`）。無機能なうえ CC 2.1.20x 以降は起動時 WARN を出す。write を縛るのは組み込み file tool 経路＝`Edit(...)`、Bash subprocess 経路＝sandbox `denyWrite` の 2 つ。この「冗長でも明示」方針は **sandbox 側の列挙にのみ**適用し、`Write(...)` permission rule には適用しない（後者は明示ですらなく雑音）。

## 検証済み delta（インデックス）

公式 Docs に明記が無い／読み落としやすい実機挙動。**仕様変更でドリフトしうる**ため、各行に**最終確認日と Claude Code バージョン**を記録する（その行を最後に真と確認した時点＝鮮度。「いつまで真だったか」の履歴ではない）。本文からは ID（`D1` 等）で参照する。permission を触るときは公式 Docs と実機で**再確認し、挙動が変わっていたらその行を上書き更新（日付・バージョン・内容）、不要になったら削除**する。**表は常に現状のみを映す**（経緯は git 履歴が持つので、古い記述を残して肥大化させない）。

| ID | 検証日 | CC ver | 挙動（要約） |
|----|--------|--------|-------------|
| `D1` | 2026-05-23 | 未記録 | Read/Edit deny が Permission 層でカバーする Bash コマンドは `cat`/`head`/`tail`/`sed` 等の**認識コマンドのみ**で、`xxd`/`od`/`wc`/`less`/`bat`/`more`/`strings` は漏れる。ただし **sandbox 内では Read deny が sandbox にマージされ全 read が OS 遮断されるので顕在化しない**。漏れるのは **unsandbox / `excludedCommands` 経路**で、対策は必要時に明示 Bash viewer deny（現状は未配備）。`sed` は read-only 用途でも Edit 扱い。`allowRead` 内のパスは Read deny の Bash カバーが外れる |
| `D2` | 2026-05-25 | 2.1.150 | Bash matcher はシェルオペレータ（`&&` `;` `\|` 等）と `$(...)` を分解して各部に適用するが、**別パス名（`/bin/echo` 等）・インタプリタ包み（`sh -c` / `bash -c` / `python -c`）は取りこぼす**。`sh -c '<denied>'` 一発で deny を回避できる → Bash deny は「うっかり承認を防ぐ床」であって境界ではない（境界は sandbox） |
| `D3` | 2026-07-15 | 2.1.210 | **`Write(...)` permission rule は file permission check の対象外＝無機能**。組み込み Write tool（作成/上書き）は Edit カテゴリで `Edit(...)` のみが縛る（公式 Docs: 「Read and Edit deny rules apply to Claude's built-in file tools」／「add an `Edit` deny rule for paths no tool may change」）。`Write(...)` は Bash redirect も含め何も gate しない（Bash subprocess の write 遮断は sandbox `denyWrite` の OS 強制が担い、permission rule には依存しない）。パス形式（`~/dir/**`/exact/`**/X`）で差は無く `Edit` の有無が全て。live-reload は file tool でも正常。実証2件（2026-07-15・2.1.210）: (1) 現行有効な `Edit(**/*secret*)` にマッチするパスへ組み込み Write tool で新規作成→`denied by your permission settings` でブロック（Edit が Write tool を縛る）。(2) `Edit`・sandbox 非該当のテストパスに `Write(...)` のみ deny を仕込み bash redirect（`echo x > path`）→**成功**（Write() は redirect も弾かない。deny は auto-allow より優先評価されるので機能していれば必ず発火するが、しなかった）。旧記述の「`Write(...)` の実効は Bash redirect 遮断のみ」は誤り（2.1.150 での誤帰属か挙動変更）で、CC 2.1.20x 以降は起動時に `Write(...)` deny を「not matched by file permission checks — Use Edit(...)」と WARN する→`Write(...)` deny は書かず全て `Edit(...)` に寄せる。**無機能なのは `Write(path)` 形式**で、**パスなしのツール名ルール（`Write` 単体）は別扱い**＝tool 全体にマッチし WARN も出ない（Docs 明記。うちでは未使用だが「Write は一切禁止」としたい場合の唯一の書き方） |
| `D4` | 2026-05-25 | 2.1.150 | **`Read(//**/*.pem)`（秘密鍵保護）が公開 CA バンドル（`cert.pem`）まで巻き込み**、sandbox 内で CA を read 遮断する。結果、sandbox 内の `git push`/`curl` 等が CA をロードできず **TLS 確立前に失敗**（`error setting certificate verify locations`）。commit はローカルのみで無傷。対策は「sandbox 内で TLS を通す」節（CA バンドルを `allowRead` 例外＋env で参照）。問題は **Claude Code sandbox 固有**（通常ターミナルでは `Read(...)` deny が効かないので無関係） |
| `D6` | 2026-07-12 | 2.1.207 | **sandbox の filesystem 判定は symlink 解決後の実体パス**（macOS Seatbelt）。`allowWrite` に symlink 側パス（例 `~/.bun/install/cache`）を書いても、実体（`~/dotfiles/.bun/install/cache`）への書き込みは `Operation not permitted` のまま。dotfiles 管理で `~/.X` が symlink のパスを許可するときは**実体側パスも併記**する（symlink 側単独では無効、将来 symlink を外しても壊れないよう二重記載が正）。実証: 別リポジトリの worktree 作成で bun cache 書き込みが symlink 側許可のみで拒否→実体側追加で解消 |
| `D5` | 2026-06-08 | 2.1.168 | **`.git/config`（完全一致）と `.git/hooks/` は harness 組み込みで sandbox-write-deny**（settings.json 由来でない。worktree 非依存で main repo でも `git config --local` 書き込みが `Operation not permitted`）。`objects`/`refs`/`logs`/`index`/`.git` 直下・`config.xxx` は許可なので **`git commit` は通るが `git push -u`/`--set-upstream`/`push.autoSetupRemote` は落ちる非対称**（tracking を `.git/config` に書くため）。しかも config 書き込み拒否でも **git は exit 0 ＋「branch '...' set up to track」でサイレント失敗** → upstream 永続化されず次の素 `git push` が「no upstream configured」。理由は `.git/config` の `core.sshCommand`/`fsmonitor`/alias/`hooksPath` が RCE 源（`~/.gitconfig` deny と同系統）。対策は §git の `excludedCommands` 行き。**Claude の Edit tool は `.git/config` を書ける**（seatbelt 外・`Edit(.git/config)` deny も無し）＝in-sandbox の `git branch -D` が残す orphan config section の手当てに使える。D4 の TLS 失敗（push が落ちる別原因）とは無関係 |
| `D8` | 2026-06-18 | 未記録 | **`autoAllowBashIfSandboxed: true` でも明示 `ask` ルールは auto-allow を上書きし、sandbox 内で発火する**（優先順位 `deny` > 明示 `ask` > auto-allow）。auto-allow は「明示ルールに当たらなかったコマンドの受け皿」でしかない。実測: `grep -n … \| sed -n '1,40p'` で `Ask rule Bash(sed *) overrides auto mode for this command.`。`\|`/`&&` はサブコマンド分割評価（`D2`）なのでパイプ後段の `sed` 単体が当たる。**旧記述「sandbox 内では `ask` に到達しない」は誤り**。実用含意: 純 read-only viewer（`sed`/`awk`/`od`/`xxd`/`strings`/`more`/`nl`/`tac`）を `ask` に置くとページング用途（`sed -n '1,Np'`）で毎回発火し、**非対話 subagent（`/code-review`）は ask を捌けず denied 扱い**になって実害が出る。しかも防御には寄与しない（`/bin/sed`・`sh -c` で迂回可＝`D2`。秘匿 read/改ざんの実効防御は sandbox `denyRead` ＋ `Read`/`Edit(//**/X)` の OS 層）→ これらは 2026-06-18 に `ask` から削除済み |
| `D7` | 2026-07-22 | 2.1.216 | **sandbox は keychain 書き込み（osxkeychain の store）を遮断**。git の credential helper `osxkeychain` は認証成功後に資格情報を keychain へ store するが、sandbox 下では keychain write が拒否され `fatal: failed to store: <数字>`（実測 `100001`）を毎回吐く（`get`＝認証は通るので **cosmetic・exit 0**）。helper が system(`/opt/homebrew/etc/gitconfig`)＋global(`~/.gitconfig`)の**二重設定＝多値リストで2件連結**なので2行出る（行数＝helper 件数）。対策は §git の CLAUDECODE 条件 helper。keychain を sandbox allowlist に足す方向は不採用（機微）。`.git/config` 書き込み(D5)とは別系統の write-deny |

## ファイル別の保護方針

新しい機密パスを足すときは、まず**保護クラス**を決め、レシピを**丸ごと**適用する。層ごとに場当たりで一部だけ書くとドリフトして片方の層に穴が残る（過去の 1Password write 無防備・認証 dir の Claude-tool write 開放がこれ）。**write 防御は必ず `Edit(...)` を書く**（組み込み file tool 全経路をカバー。`Write(...)` は無機能なので書かない＝`D3`）。Bash subprocess 経路は sandbox `denyWrite` が担う。

| クラス | 例 | レシピ |
|--------|-----|--------|
| **A. 全遮断ディレクトリ**（read も write も不可） | `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | Permission `Read(~/dir/**)` + `Edit(~/dir/**)`（read 自動マージで subprocess も。write は Edit で新規作成も止まる）。＋明示性で sandbox `denyRead`/`denyWrite` も列挙 |
| **B. 公開 dotfile**（read 可・write 不可） | `~/.gitconfig` `~/.npmrc`（home） | Permission `Edit(~/file)`。Read deny は**書かない**。＋ sandbox `denyWrite` |
| **C. 解放だが改ざん防止**（read 可・write 不可） | shell rc（`~/.bashrc` `~/.zshrc` `~/.config/fish`）、gpg conf | exact-file または `~/dir/**` で Permission `Edit`。＋ sandbox `denyWrite`（allow 内例外はここが実効） |
| **D. FS 全体対称 deny**（`//**`） | 秘密鍵 `*.pem` `*.key` `id_rsa` 等 | Permission `Read(//**/X)` + `Edit(//**/X)`（read は sandbox マージで subprocess も遮断。unsandbox は `D1` の viewer 漏れが残る。**Bash subprocess の write は sandbox `denyWrite` 未列挙のため OS 遮断されない**＝Claude file tool 経路のみ Edit で塞ぐ限界を許容） |
| **E. プロジェクト内 secret**（read 可・write 不可） | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` | Permission `Edit(**/X)`（組み込み file tool を塞ぐ）。**Bash subprocess の write は sandbox `denyWrite` 未列挙のため OS 遮断されない**（プロジェクト内 glob なので sandbox denyWrite に列挙せず、Claude file tool 経路のみ Edit で塞ぐ限界を許容） |

| パス | Read | Write | 区分 |
|------|------|-------|------|
| `~/.gitconfig` | 解放 | sandbox `denyWrite` + Permission `Edit` deny | 公開 dotfile |
| `~/.npmrc` | 解放 | sandbox `denyWrite` + Permission `Edit` deny | 公開 dotfile |
| `.env` 等（プロジェクト内 secret） | 解放 | Permission `Edit(**/X)` deny（組み込み file tool のみ。Bash subprocess は sandbox 未列挙で非遮断） | read 解放・write 防止（tool 経路のみ） |
| 秘密鍵 `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` | Permission `Read(//**/...)` で FS 全体遮断 | Permission `Edit(//**/...)` で FS 全体遮断（改ざん・偽鍵設置防止。組み込み file tool 経路） | 明示 deny（read は対称遮断、write は tool 経路のみ） |
| `~/.ssh` `~/.aws` `~/.config/gh` `~/.config/op` `~/.config/1Password` `~/.kube` `~/.gnupg/private-keys-v1.d` | sandbox `denyRead` + Permission `Read(~/dir/**)` deny | sandbox `denyWrite` + Permission `Edit(~/dir/**)` deny | ディレクトリ全遮断（read/write とも subprocess + Claude tool） |
| `~/.docker` | dir 全体: sandbox `denyRead`／config.json: Permission `Read` deny | dir 全体: sandbox `denyWrite`／config.json: Permission `Edit` deny | 認証実体 config.json を全経路遮断（他ファイルは Claude tool から読める） |
| `~/.netrc` | sandbox `denyRead` + Permission `Read` deny | sandbox `denyWrite` + Permission `Edit` deny | 認証情報遮断 |
| `~/.bashrc` `~/.zshrc` `~/.config/fish` | 解放 | sandbox `denyWrite` + Permission `Edit` deny | rc 改ざん（ログイン時コード実行）防止 |
| `~/.gnupg`（conf 以外） | 解放（agent 通信・署名検証に必要） | sandbox `allowWrite` で許可。ただし `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` は sandbox `denyWrite` + Permission `Edit` deny | 署名運用・設定改ざん防止 |

### 公開 dotfile（`~/.gitconfig` / `~/.npmrc`）

read を解放し、write のみ防御する。

- read 解放の理由: `~/.npmrc` は `min-release-age` 等のサプライチェーン防御や registry/proxy 設定を npm/pnpm subprocess に効かせるため（`denyRead` で塞ぐと機能しない）。`~/.gitconfig` は dotfiles で公開管理する設定で秘匿価値がない。
- write が即時攻撃面: `~/.npmrc` は `registry=` で install 先すり替え・`ignore-scripts=false`・`cafile=` で TLS バイパス・`min-release-age` 削除で防御無効化。`~/.gitconfig` は alias 注入や `core.sshCommand` で通常 git 操作時に任意コード実行。
- 規律: **read 解放したファイルに平文 secret を置かない**。認証トークンは平文でなく環境変数参照（例: `~/.npmrc` の `_authToken=${FLATT_NPM_TOKEN}`）で書き、実体は実行時に消費プロセスの env にのみ注入する（fnox 経由。[docs/fnox-token-management.md](./fnox-token-management.md)）。read 解放経路に技術的フォールバックは無く、平文 secret を置けば即漏洩しうる。

### 秘密鍵・シークレット系

- 秘密鍵は `*.pem` `*.key` `id_rsa` `id_ed25519` `id_ecdsa` `id_dsa` の各パターンを **`Read` は `//**/...`（FS 全体）で対称遮断**（read=exfil 防止。sandbox マージで subprocess も OS レベル遮断）し、**`Edit(//**/...)` で改ざん・偽鍵設置を防止**（組み込み file tool 経路。`Write(...)` は無機能なので書かない＝`D3`）。`Read(//**/*.key)`/`Read(//**/*.pem)` は秘密鍵以外の `.key`（i18n キー等）や**公開 CA バンドル（`cert.pem`）**も巻き込む。CA バンドルを巻き込むと sandbox 内 TLS が壊れる（`D4`）→「sandbox 内で TLS を通す」で read だけ個別解放（write は `Edit` ルールのまま遮断）。
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため read 解放。書き換えは **`Edit(**/X)`** で防止: `.env`/`.env.*`/`secrets/**`/`*secret*`/`*credential*`、project ローカル認証ファイルは `**/.npmrc`/`**/.netrc`。`Edit(**/X)` が Claude の組み込み file tool（Write/Edit/NotebookEdit）を塞ぐ。**これらプロジェクト内 glob は sandbox `denyWrite` に列挙していないため、Bash subprocess の直接 write は OS 遮断されない**（tool 経路のみの防御という限界を許容。`D3`）。

## Bash コマンドの実行制御（auto-allow / git / gh）

`autoAllowBashIfSandboxed: true`（詳細は公式 sandboxing）:

- 優先順位は **`deny` > 明示 `ask` ルール > auto-allow**。auto-allow が受けるのは**明示ルールに当たらなかったコマンドだけ**で、**明示 `ask` は sandbox 内でも発火する**（`D8`）。`deny` は実行前評価で全経路に効く。`rm`/`rmdir` が `/`・home 直撃時のみ circuit breaker で prompt。
- → 純粋系コマンド（`dirname`/`basename`/`realpath`/`date` 等）の `allow` 列挙は冗長。`allow` が効くのは sandbox 外実行（`excludedCommands`）の `gh *`・`git push -u origin *` 系と、Bash 外の `WebFetch` だけ。
- `ask` は sandbox 内でも実効を持つため、**境界（sandbox）の内側で「人間に一拍置かせたい」操作の置き場**になる（→「ask」節）。ただし高頻度コマンドを置くと摩擦が実害になる（`D8`）。

### ask（sandbox の内側で人間を挟む操作）

`ask` は sandbox 内でも発火する（`D8`）ので、**sandbox 境界だけでは止まらない性質の操作**を人間に捌かせるレイヤとして使う。置いているのは次の3系統で、いずれも「実行そのものは正当だが、AI が自律的にやると取り返しがつかない／気づけない」ものに限る。

- **exfiltration と破壊の都度承認**: `curl *` / `wget *` / `rm *`。curl/wget は `allowedDomains` の外へ出る送信経路、`rm` は不可逆な削除。sandbox の内側に留まっていても外部到達・データ喪失は起きるため、人間が捌く。
- **環境変数の一括ダンプ**: `env` / `printenv *`。fnox は token を消費プロセスの env にだけ注入する（[docs/fnox-token-management.md](./fnox-token-management.md)）ので、env の一括ダンプは**注入済み token を出力に載せる直接経路**になる。Shai-Hulud 型マルウェアが env を漁って認証情報を持ち出す挙動そのものでもあり、ダンプ操作自体を情報収集の前段として扱って承認を挟む。
- **外部公開（publish）**: `* publish *`。registry への公開は不可逆かつ外部到達で、AI が自律実行してよい操作ではない。加えて Shai-Hulud 型は**侵害環境から汚染版を publish して拡散する**ワーム挙動を取るため、publish を人間の承認点に固定しておくこと自体が拡散の遮断になる。

`gh` 系の `ask`（`gh api *` / `gh workflow run *` / `gh run rerun *`）は別の理由（matcher で read/write を区別できない・CI を動かす）で置いている。→「gh」節。

read-only viewer 系（`sed`/`awk`/`od` 等）を `ask` に置くのは**不採用**。防御に寄与せず（`sh -c` 等で迂回可＝`D2`）、非対話 subagent が捌けず実害だけが残る（`D8`）。

### git

**in-sandbox の git には permission ルールを置かない**（auto-allow なので冗長）。read-only git は built-in 認識で allow 不要。write・破壊系は sandbox 内完結で auto-allow（`github.com` は `allowedDomains` 内なので push/fetch も）。**`ask` を置けば sandbox 内でも発火する（`D8`）が、git には置かない判断**＝破壊系は sandbox 境界＋`allowedDomains`（github 限定＝ローカル/自リポジトリに留まり外部流出にならない）を信頼して容認し、高頻度な git 操作に prompt を挟む摩擦を避ける。確実に止めたい操作は `deny` か PreToolUse hook。

**例外: upstream 設定の push は `excludedCommands` 行き＝§gh と同じ扱い**。`git push -u origin *` / `git push --set-upstream origin *` は sandbox 外実行にする。理由は upstream tracking（`branch.X.remote`/`merge`）の書き込み先 `.git/config` が sandbox-write-deny で、in-sandbox だと **exit 0 のサイレント失敗で upstream が永続化されない**ため（`D5`）。sandbox 外＝permission flow に乗るので、§gh の write 系と同様に **allow が必要**（無いと default mode で `ask` に落ち毎回プロンプト。in-sandbox の auto-allow は効かない）。

- **リモートは `origin` にピン留め必須**: `remote.origin.url` 自体が `.git/config` write 保護下で改竄不能なので origin は信頼できる固定先。`git push -u *`（wildcard リモート）は `git push -u https://evil` や `ext::sh -c '<cmd>'` を通し**任意ホスト流出/ローカル RCE** を開くため禁止。allow も `Bash(git push -u origin *)` / `Bash(git push --set-upstream origin *)` と origin 固定で書く。
- upstream 設定後の素 `git push` は config 書き込み不要なので sandbox 内で OK（除外不要）。`excludedCommands` 変更は seatbelt プロファイルがセッション開始時に焼かれるため**セッション再起動で反映**。

**credential store の keychain 書き込み失敗は store no-op helper で黙らせる（`D7`）**。osxkeychain helper は認証後に資格情報を keychain へ store するが sandbox が keychain write を遮断し `fatal: failed to store: 100001` を毎回吐く（`get`＝認証は通る cosmetic）。`git push`/`fetch` を `excludedCommands` で sandbox 外に出せば消えるが、**git を sandbox に留める方針を崩す＋複合コマンド（`cd && git`・`git -C`）や子プロセス経由の git に前置一致が効かず取りこぼす**ため不採用。代わりに `~/.gitconfig` で helper を**リセット（`helper =`）して1本に置換**し、その helper が **Claude Code 配下（`$CLAUDECODE` set）でのみ `store`/`erase` を no-op、`get` は常に osxkeychain 委譲、通常ターミナルでは全委譲**（資格情報キャッシュを壊さない）。実体は dotfiles 管理スクリプト `~/dotfiles/bin/credential-helper.sh`（`helper = "!$HOME/dotfiles/bin/credential-helper.sh"`）。**スクリプトは実行権必須**（`!` 形式は `sh -c 'script get'` で exec するため、非実行権だと exit 126 "permission denied"→`get` が資格情報を返せず git が対話プロンプトにフォールバックして**ハング**する。実測の罠）。スクリプトは純 POSIX で `#!/bin/sh`（shebang は自己完結＝親シェル非依存。credential helper は git が操作ごとに spawn するので軽量・常在の sh が向く）。`set -u` を使うなら **`${CLAUDECODE:-}`/`${1:-}` 必須**（素の `$CLAUDECODE` は通常ターミナルで未設定＝`set -u` 下で unbound で helper がクラッシュし認証が壊れる・実証）。`pipefail` は非 POSIX（dash に無い）＋パイプ無しなので付けない。brew の `/opt/homebrew/etc/gitconfig`（git 導入時に自動生成・`brew reinstall/upgrade` で復活しうる）は**消さず reset で無効化**する（消しても durable でない）。

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

## サプライチェーン対策（新規公開版の保持期間）

新規公開版を一定期間掴まないための保持設定は、**PM ごとに設定ファイル・キー名・単位がすべて違う**。本リポジトリは 7 日保持で揃えている:

| PM | 設定ファイル | キー | 7 日相当 |
|----|------------|-----|---------|
| npm | `.npmrc` | `min-release-age` | `7`（日） |
| pnpm <=10 | `.npmrc` | `minimum-release-age` | `10080`（分） |
| pnpm 11+ | `.config/pnpm/config.yaml` | `minimumReleaseAge` | `10080`（分） |
| bun | `.config/.bunfig.toml` の `[install]` | `minimumReleaseAge` | `604800`（秒） |

**キーやファイルを取り違えると、エラーを出さずに防御が丸ごと無効化される**（設定した気になるのが最大のリスク）。要点:

- **npm の `min-release-age` を pnpm は読まない**（no-op）。キー名が別なので `.npmrc` に両方書く。
- **pnpm 11+ は `.npmrc`（INI）を一切読まない**。`config.yaml`(YAML/camelCase) のみで、`save-exact` も同様に無視されるため `saveExact: true` を併記しないと 11 昇格で厳密固定が静かに失われる。置き場は `XDG_CONFIG_HOME=~/.config`（fish の `config.fish` で設定）前提の `~/.config/pnpm/config.yaml`。設定が無いと macOS 既定の `~/Library/Preferences/pnpm/config.yaml` を見に行く。
- **bun の設定は `~/.bunfig.toml` では効かない**。`XDG_CONFIG_HOME` が設定されていると bun は `$XDG_CONFIG_HOME/.bunfig.toml` だけを見て**ホーム側にフォールバックしない**（[oven-sh/bun#30842](https://github.com/oven-sh/bun/issues/30842)）。本リポジトリは `.config/.bunfig.toml` を `../.bunfig.toml` への**相対 symlink** にして同一実体を 2 箇所から参照させている。この symlink を外すと `minimumReleaseAge` ごと bun のグローバル設定が全滅する。
- bun は `.npmrc` の `min-release-age` も読まない（[oven-sh/bun#22679](https://github.com/oven-sh/bun/issues/22679)）。`save-exact` もプロジェクトローカルに `.npmrc` が無いとホーム側にフォールバックしない（[oven-sh/bun#22971](https://github.com/oven-sh/bun/issues/22971)）ため、`.bunfig.toml` の `exact = true` で代替している。

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

### bun install を sandbox 内で通す

`bun install` は既定キャッシュ **`~/.bun/install/cache`** に書く（インストールの staging temp もこの中）。sandbox は cwd 外 write を塞ぐため、許可が無いと file: 依存のオフライン install ですら `bun is unable to write files to tempdir: PermissionDenied` で失敗する（実機で発覚）。

- **`sandbox.filesystem.allowWrite` に cache を追加**。ただし dotfiles 管理で **`~/.bun` は symlink**（→ `~/dotfiles/.bun`）なので、判定が実体パスで行われる（`D6`）ことから **`~/.bun/install/cache` と `~/dotfiles/.bun/install/cache` の両方を書く**。symlink 側単独では無効。二重記載は冗長ではなく、symlink 構成の変更に対する両対応。
- 粒度は `~/.bun` 全体ではなく `install/cache` に絞る（`~/.bun/bin` 等への write 開放は `$PATH` 実行物の改ざん経路になるため）。`bun add -g` 等で別の書き込みが必要になったらその時に個別判断。
- 対して `~/.npm/_cacache`・`~/.gnupg` が単記で効くのは、これらが symlink でない実ディレクトリだから。

### mise を sandbox 内で通す

mise は cwd 外の 2 箇所に書くため `sandbox.filesystem.allowWrite` に追加している。npm/bun の cache と同じく「sandbox は cwd 外 write を allowlist で塞ぐ」の帰結:

- `~/.local/state/mise/trusted-configs`: mise が config ファイルの信頼状態を記録する先（追加経緯は `5b5c0b3`）。
- `~/Library/Caches/mise`: mise のキャッシュ（追加経緯は `720ca53`）。

粒度は `~/.local/state` や `~/Library/Caches` 全体に広げず、mise の 2 パスに絞る。

### sandbox 内で TLS を通す（CA バンドル）

`Read(//**/*.pem)`（秘密鍵保護）が sandbox にマージされ、**公開 CA バンドル（`cert.pem`）まで read 遮断**してしまう（`D4`）。このため sandbox 内の `git push`/`curl`/openssl 系ツールが CA をロードできず TLS で失敗する。秘密鍵の `*.pem` 遮断は維持したまま、**公開 CA バンドルだけ例外解放**して解消する:

- **`sandbox.filesystem.allowRead` に CA バンドルを追加**: `/opt/homebrew/etc/ca-certificates/cert.pem`（arm64 Homebrew の実バンドル）。`allowRead` は denyRead 領域内の再許可なので、`*.pem` 遮断を保ったままこの1ファイルだけ subprocess に**読ませる**。中身は公開ルート CA 証明書のみ（秘密鍵 0 件）なので read 解放は安全。**write/改ざん（偽 CA 追記→MITM）は別軸の脅威**で、これは `Edit(//**/*.pem)`（FS 全体ルール、組み込み file tool 経路）で引き続き遮断される。read だけ解放、write は塞ぐ、の非対称が成立。
- **ツールを読めるパスに向ける env**: git のデフォルト CA（`/etc/ssl/cert.pem`）も `*.pem` 遮断＋`/private/etc` 制限で読めないので、`settings.json` の `env` で CA を明示する。`GIT_SSL_CAINFO`（git。`SSL_CERT_FILE` 単体では git は不可と実機確認）＋ `SSL_CERT_FILE`/`CURL_CA_BUNDLE`（openssl/curl 系）を同バンドルに向ける。
- **置き場は Claude Code の `settings.json`**（mise 等のグローバル env ではない）。この問題は **Claude Code sandbox 固有**（通常ターミナルでは `Read(...)` deny が効かず git は普通に通る）なので、修正も Claude スコープに閉じる。`settings.json` の `env` は sandbox サブプロセスに継承される。
- 補足: commit はローカル操作（`.git` 書き込み＋gpg socket 署名）で TLS 不要のため、この問題でも成功する。push だけが TLS を要して落ちる、という非対称になる。

### GnuPG 署名コミット

署名コミット（`commit.gpgsign=true`、OpenPGP 鍵）は sandbox 外常駐の gpg-agent と Unix socket で通信して署名する（いずれも実機検証で確定）:

- **`allowUnixSockets: ["~/.gnupg/S.gpg-agent"]` は必須**。外すと agent 接続不可で署名できない（`can't connect to the agent`）。socket パスは `gpgconf --list-dirs agent-socket` と一致させる。
- 署名「作成」はクライアント側の `~/.gnupg` 書き込み不要（agent が担う）。一方「検証」（`git verify-commit` / `git log --show-signature`）は trustdb ロックで `~/.gnupg` 書き込みを要求するため、検証を sandbox 内で通すなら `allowWrite: ~/.gnupg` を維持。
- **ハードニング**: `gpg-agent.conf`/`gpg.conf`/`dirmngr.conf` の改ざん（特に `pinentry-program` 書き換えによるパスフレーズ窃取）を塞ぐ。**2 経路必要**: sandbox `denyWrite`（subprocess）＋ Permission **`Edit` deny**（組み込み file tool。`Write` deny は無機能なので書かない＝`D3`）。秘密鍵 `private-keys-v1.d` も `Edit` deny を書く。
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
- `### AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定（実効パスは `.config/.bunfig.toml` の symlink 経由）
- `dotfiles/.config/pnpm/config.yaml`: pnpm 11+ の supply-chain 設定
