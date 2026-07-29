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
- **冗長な sandbox 列挙は意図的に残す**: 「sandbox config 単体で何が遮断されるか」が明示され、Permission 層を取り違えても安全側に倒れるため。これは**層をまたぐ冗長**（同じパスを permission と sandbox の両方に書く）の話で、**同じパスを 2 通りの綴りで書く冗長は採らない**（symlink 綴り＋実体パスの併記は片方が無言で効かず、読み手に区別が伝わらない＝`D10`）。
- **Permission 層に `Write(...)` deny は書かない**（`D3`）。無機能なうえ CC 2.1.20x 以降は起動時 WARN を出す。write を縛るのは組み込み file tool 経路＝`Edit(...)`、Bash subprocess 経路＝sandbox `denyWrite` の 2 つ。この「冗長でも明示」方針は **sandbox 側の列挙にのみ**適用し、`Write(...)` permission rule には適用しない（後者は明示ですらなく雑音）。

## 検証済み delta（インデックス）

公式 Docs に明記が無い／読み落としやすい実機挙動。**仕様変更でドリフトしうる**ため、各行に**最終確認日と Claude Code バージョン**を記録する（その行を最後に真と確認した時点＝鮮度。「いつまで真だったか」の履歴ではない）。本文からは ID（`D1` 等）で参照する。permission を触るときは公式 Docs と実機で**再確認し、挙動が変わっていたらその行を上書き更新（日付・バージョン・内容）、不要になったら削除**する。**表は常に現状のみを映す**（経緯は git 履歴が持つので、古い記述を残して肥大化させない）。

| ID | 検証日 | CC ver | 挙動（要約） |
|----|--------|--------|-------------|
| `D1` | 2026-05-23 | 未記録 | Read/Edit deny が Permission 層でカバーする Bash コマンドは `cat`/`head`/`tail`/`sed` 等の**認識コマンドのみ**で、`xxd`/`od`/`wc`/`less`/`bat`/`more`/`strings` は漏れる。ただし **sandbox 内では Read deny が sandbox にマージされ全 read が OS 遮断されるので顕在化しない**。漏れるのは **unsandbox / `excludedCommands` 経路**で、対策は必要時に明示 Bash viewer deny（現状は未配備）。`sed` は read-only 用途でも Edit 扱い。`allowRead` 内のパスは Read deny の Bash カバーが外れる |
| `D2` | 2026-05-25 | 2.1.150 | Bash matcher はシェルオペレータ（`&&` `;` `\|` 等）と `$(...)` を分解して各部に適用するが、**別パス名（`/bin/echo` 等）・インタプリタ包み（`sh -c` / `bash -c` / `python -c`）は取りこぼす**。`sh -c '<denied>'` 一発で deny を回避できる → Bash deny は「うっかり承認を防ぐ床」であって境界ではない（境界は sandbox） |
| `D3` | 2026-07-15 | 2.1.210 | **`Write(...)` permission rule は file permission check の対象外＝無機能**。組み込み Write tool（作成/上書き）は Edit カテゴリで `Edit(...)` のみが縛る（公式 Docs: 「Read and Edit deny rules apply to Claude's built-in file tools」／「add an `Edit` deny rule for paths no tool may change」）。`Write(...)` は Bash redirect も含め何も gate しない（**ただし `Edit(...)` deny は sandbox 境界へマージされ Bash redirect も遮断する**＝`D9`。ここで無機能なのは `Write(...)` のみ）。パス形式（`~/dir/**`/exact/`**/X`）で差は無く `Edit` の有無が全て。live-reload は file tool でも正常。実証2件（2026-07-15・2.1.210）: (1) 現行有効な `Edit(**/*secret*)` にマッチするパスへ組み込み Write tool で新規作成→`denied by your permission settings` でブロック（Edit が Write tool を縛る）。(2) `Edit`・sandbox 非該当のテストパスに `Write(...)` のみ deny を仕込み bash redirect（`echo x > path`）→**成功**（Write() は redirect も弾かない。deny は auto-allow より優先評価されるので機能していれば必ず発火するが、しなかった）。旧記述の「`Write(...)` の実効は Bash redirect 遮断のみ」は誤り（2.1.150 での誤帰属か挙動変更）で、CC 2.1.20x 以降は起動時に `Write(...)` deny を「not matched by file permission checks — Use Edit(...)」と WARN する→`Write(...)` deny は書かず全て `Edit(...)` に寄せる。**無機能なのは `Write(path)` 形式**で、**パスなしのツール名ルール（`Write` 単体）は別扱い**＝tool 全体にマッチし WARN も出ない（Docs 明記。うちでは未使用だが「Write は一切禁止」としたい場合の唯一の書き方） |
| `D4` | 2026-05-25 | 2.1.150 | **`Read(//**/*.pem)`（秘密鍵保護）が公開 CA バンドル（`cert.pem`）まで巻き込み**、sandbox 内で CA を read 遮断する。結果、sandbox 内の `git push`/`curl` 等が CA をロードできず **TLS 確立前に失敗**（`error setting certificate verify locations`）。commit はローカルのみで無傷。対策は「sandbox 内で TLS を通す」節（CA バンドルを `allowRead` 例外＋env で参照）。問題は **Claude Code sandbox 固有**（通常ターミナルでは `Read(...)` deny が効かないので無関係） |
| `D6` | 2026-07-12 | 2.1.207 | **sandbox の filesystem 判定は symlink 解決後の実体パス**（macOS Seatbelt）。`allowWrite` に symlink 側パス（例 `~/.bun/install/cache`）を書いても、実体（`~/dotfiles/.bun/install/cache`）への書き込みは `Operation not permitted` のまま。dotfiles 管理で `~/.X` が symlink のパスを扱うときは**実体パス（`~/dotfiles/...`）で書く**。symlink 側の綴りは無効なので併記しない（deny 側の同じ性質は `D10`）。実証: 別リポジトリの worktree 作成で bun cache 書き込みが symlink 側許可のみで拒否され、実体側パスで解消 |
| `D5` | 2026-06-08 | 2.1.168 | **`.git/config`（完全一致）と `.git/hooks/` は harness 組み込みで sandbox-write-deny**（settings.json 由来でない。worktree 非依存で main repo でも `git config --local` 書き込みが `Operation not permitted`）。`objects`/`refs`/`logs`/`index`/`.git` 直下・`config.xxx` は許可なので **`git commit` は通るが `git push -u`/`--set-upstream`/`push.autoSetupRemote` は落ちる非対称**（tracking を `.git/config` に書くため）。しかも config 書き込み拒否でも **git は exit 0 ＋「branch '...' set up to track」でサイレント失敗** → upstream 永続化されず次の素 `git push` が「no upstream configured」。理由は `.git/config` の `core.sshCommand`/`fsmonitor`/alias/`hooksPath` が RCE 源（`~/.gitconfig` deny と同系統）。対策は §git の `excludedCommands` 行き。**Claude の Edit tool は `.git/config` を書ける**（seatbelt 外・`Edit(.git/config)` deny も無し）＝in-sandbox の `git branch -D` が残す orphan config section の手当てに使える。D4 の TLS 失敗（push が落ちる別原因）とは無関係 |
| `D8` | 2026-06-18 | 未記録 | **`autoAllowBashIfSandboxed: true` でも明示 `ask` ルールは auto-allow を上書きし、sandbox 内で発火する**（優先順位 `deny` > 明示 `ask` > auto-allow）。auto-allow は「明示ルールに当たらなかったコマンドの受け皿」でしかない。実測: `grep -n … \| sed -n '1,40p'` で `Ask rule Bash(sed *) overrides auto mode for this command.`。`\|`/`&&` はサブコマンド分割評価（`D2`）なのでパイプ後段の `sed` 単体が当たる。実用含意: 純 read-only viewer（`sed`/`awk`/`od`/`xxd`/`strings`/`more`/`nl`/`tac`）を `ask` に置くとページング用途（`sed -n '1,Np'`）で毎回発火し、**非対話 subagent（`/code-review`）は ask を捌けず denied 扱い**になって実害が出る。しかも防御には寄与しない（`/bin/sed`・`sh -c` で迂回可＝`D2`。秘匿 read/改ざんの実効防御は sandbox `denyRead` ＋ `Read`/`Edit(//**/X)` の OS 層）→ これらは `ask` に置かない |
| `D9` | 2026-07-27 | 2.1.220 | **`Edit(...)` deny は sandbox の write 境界へマージされ、Bash subprocess の書き込みも OS レベルで遮断する**（公式 Docs sandboxing: "Filesystem restrictions in the sandbox combine the `sandbox.filesystem` settings with Read and Edit deny rules"）。実証: cwd 配下に `Edit(//**/*auth*.json)` 等にマッチする名前で `echo x > <path>` を実行 → シェルが `operation not permitted`（EPERM）で失敗。非マッチ名（`plain.json`/`mytoken.txt`）は書けたので、Bash matcher ではなく OS 境界による遮断。含意: パス名で表現できる保護は `Edit(...)` 1 本で file tool と subprocess の両経路を塞げる。`sandbox.denyWrite` が要るのは**パターンで表現しない／Edit deny を掛けたくない**ケース（例: ディレクトリ全体の subprocess 書き込みは止めるが Claude の file tool では編集したい `~/dotfiles/.codex`） |
| `D10` | 2026-07-27 | 2.1.220 | **deny rule のパスが「symlink されたディレクトリ」を経由すると、file tool にしか効かない**（Bash の認識コマンドにも OS 層にも届かず、無言で通る）。**ファイル自体の symlink は解決される**ので `~/.gitconfig`・`~/.zshrc`（dotfiles への file symlink）は実体パス経由でも遮断された一方、`~/.config/fish/**`・`~/.codex/auth.json`（`~/.config`・`~/.codex` が dir symlink）は実体パス経由で read/write とも素通りした。**実体パス（`~/dotfiles/...`）で書けば1本で3層すべてに効く**（symlink 綴りでのアクセスも止まる＝公式 Docs「When Claude accesses a symlink, permission rules check two paths: the symlink itself and the file it resolves to」の挙動）。逆は成り立たない。実証（ダミー `probe/link → real`）: rule を symlink 綴りで書くと file tool のみ deny・`cat`/`wc` は素通り、実体綴りで書くと file tool も `cat` も `wc` も deny。**Docs は「Read/Edit deny は Bash の `cat`/`head`/`tail`/`sed` にも適用される」と書いているので、この Bash 層の取りこぼしは記述との乖離**（upstream は `#71072` で `.claude/rules` の同種問題を bug 扱いで 2.1.198 修正、settings ファイル保護の symlink 解決も 2.1.210 で後追い追加＝個別に塞いでいる最中）。**実体パスで書くのは upstream が直しても正しいままなので、剥がす前提の回避策ではない** |
| `D11` | 2026-07-27 | 2.1.220 | **相対アンカー `**/X` の deny は層ごとに効き方が食い違うので使わない。FS 全体アンカー `//**/X` で書く**。dotfiles の外（`/tmp/cc-permcheck` を cwd にした別セッション）で実測した結果: **ファイル型 `Edit(**/.env)`・`Edit(**/.npmrc)` は file tool を素通りし（`String to replace not found` に到達＝permission 通過）Bash/OS 層でのみ遮断**、逆に**ディレクトリ型 `Edit(**/secrets/**)` は file tool では遮断されたが Bash からの書き込みは通った**。どちらも片肺で、`**/` は cwd 基準でもない（file tool 側）。公式 Docs は「Bare filenames follow gitignore semantics and match at any depth」かつ「A rule only matches files under its anchor」と書いており、user settings のアンカーは設定の置き場（`~/.claude`）。**dotfiles リポジトリで検証すると cwd と `~/.claude` が同じツリーになるため、この食い違いは検出できない**（`~/.claude` は `~/dotfiles/.claude` への symlink）。`//**/` 形式にすれば file tool 層は全パターンで遮断される（別 cwd セッションで確認）。OS 層まで届くかは接頭辞の形に依存する＝`D12` |
| `D12` | 2026-07-27 | 2.1.220 | **deny が OS 層まで届くかは「ディレクトリ型かどうか」ではなく「接頭辞が具体パスかワイルドカードか」で決まる**。`//**/*.pem` 等のファイル名型と、`~/dotfiles/.config/gh/**` のような**具体接頭辞のディレクトリ型**は配下まで OS 層に載る（Bash の read/write とも遮断を実測）。一方 **`//**/secrets/**` のようにディレクトリ名までワイルドカードだと、OS 層にはディレクトリ自体の作成禁止までしか届かず、既存ディレクトリ配下のファイルへの Bash 書き込みは通る**（実測: `mkdir ./secrets`・`mkdir $TMPDIR/secrets` は `Operation not permitted`、しかし別 cwd セッションで既存 `secrets/inner.txt` への追記は成功）。file tool 層では両方とも効く。**含意**: 守る対象を具体パスで名指しできるなら接頭辞を具体にする（例 `~/dotfiles/.config/gh/**`）。任意プロジェクトの `secrets/` のように名指しできないものは、file tool 経路とディレクトリ新規作成までが防御範囲で、**既存ディレクトリへの Bash 書き込みは残る**と割り切る（permission rule の書き方では塞げない。塞ぐなら対象プロジェクト側の `sandbox.denyWrite` に実パスを列挙する） |
| `D13` | 2026-07-28 | 2.1.220 | **`ConfigChange` hook は settings の変更で確実に発火するが、変更の反映は止められない**。公式 Docs は「exit 2 で設定変更の反映をブロック」「top-level `decision: block` に対応」と書いているが、**どちらでも新しい permission rule はそのまま効いた**。実証: hook 側で判定用マーカーを吐かせて発火を確認（1 変更につき複数回発火）したうえで、`Bash(echo <probe> *)` の deny を bad path と同時に投入 → clean な状態では probe が通り、投入後は拒否された＝反映済み。exit 2 版・`decision: block` 版とも同結果で、hook 由来の通知はモデル側にも届かなかった。**含意**: 防御の実効は別イベントに置く（うちでは PostToolUse がモデルへの差し戻し、SessionStart が起動時の掃き出し）。**うちでは ConfigChange を採らない**: 反映も止められずモデルにも届かないうえ、1 変更につき 4 回発火する（`systemMessage` が user の画面に出るかもセッション内からは確認できていない） |
| `D14` | 2026-07-28 | 2.1.220 | **hook の `if` フィルタは symlink を解決しない**。`if: "Edit(//Users/<user>/dotfiles/.claude/settings*.json)"`（実体パス）は、**同じファイルを `~/.claude/settings.json`（symlink 綴り）で編集した tool call にマッチせず hook が発火しなかった**。permission の deny rule は実体パスで書けば symlink 綴りのアクセスも捕まえる（`D10`）のに対し、`if` は tool の引数文字列に対する素のマッチという非対称。**対処は suffix アンカー**（`if: "Edit(//**/.claude/settings*.json)"`）で、実体パス・symlink 綴り・他プロジェクトの `.claude/settings.json` の 3 者とも発火を実測（非マッチのファイルではプロセスも起きない）。綴りごとに `if` を並べる必要はない |
| `D15` | 2026-07-28 | 2.1.220 | **user へ出る hook 通知は 200 文字で打ち切られる（末尾 `…`）。しかも `[<hook の command>]: ` の接頭辞がその 200 文字に含まれる**。実測: SessionStart（exit 2）の表示が `[bun <スクリプトの絶対パス>]: ` 80 文字＋本文 120 文字＝ちょうど 200 文字＋`…`。**モデルへ返る PostToolUse の stderr は全文**（複数行そのまま）なので、切り詰めは「表示側の通知」だけ。**含意**: user 向けの hook は (1) 1 行目に結論を詰める、(2) 後ろから消えるので derive しやすい情報を末尾へ、(3) **command 文字列を短く書くほど本文の予算が増える**（`bun ~/dotfiles/…` と書けば絶対パスより 12 文字得。`~` はシェル経由で展開されるので動作は同じ＝実測）。接頭辞が出ること自体は upstream `#41226` で報告済み（closed）だが、**200 文字打ち切りの issue は検索した範囲では見つからなかった** |
| `D16` | 2026-07-29 | 2.1.220 | **git hook manager の hook 自動同期が `.git/hooks/` の write-deny（`D5`）に当たり、commit のたびにエラー行を吐く**。lefthook は設定が変わっていると `lefthook run` のたびに hook を再生成するが、その処理が `.git/hooks/pre-commit` の**削除**を伴うため sandbox 内では `sync hooks: ❌ Skipping hook sync: could not replace the hook: remove … operation not permitted`。**commit 自体は成功する**ので `D5` の push と違ってサイレント失敗ではないが、毎回出ると原因の切り分けを誤らせる。対策は `.git/hooks/` の deny を緩めるのではなく（緩めると git 操作での任意コード実行を開く）、**tool 側で自動同期を切る**＝`lefthook.yml` に `no_auto_install: true`。生成される hook は `lefthook run <hook>` を呼ぶだけのランチャで設定は実行時に読まれるため、**既存 hook の内容変更は同期なしで反映される**（手動 `lefthook install` が要るのは新しい hook 種別を足したときだけ）。実証: `.git/info/lefthook.checksum` を削除して同期パスを踏ませ、`no_auto_install` の有無だけでエラーの再現と解消を確認。**発火条件そのものは未特定**（checksum は `<md5> <config の mtime>` だが、`touch` や設定内容の書き換えだけでは同期が走らないケースがあった）。`no_auto_install` は条件によらず同期パスに入らなくするので、対策の妥当性は条件の解明に依存しない。lefthook `#1392`（sandbox で `setsid()` が弾かれ `run:` のコマンドが全て失敗する件）は PR `#1393` で修正済みの**別問題**で、2.1.10 では再現しない |
| `D7` | 2026-07-22 | 2.1.216 | **sandbox は keychain 書き込み（osxkeychain の store）を遮断**。git の credential helper `osxkeychain` は認証成功後に資格情報を keychain へ store するが、sandbox 下では keychain write が拒否され `fatal: failed to store: <数字>`（実測 `100001`）を毎回吐く（`get`＝認証は通るので **cosmetic・exit 0**）。helper が system(`/opt/homebrew/etc/gitconfig`)＋global(`~/.gitconfig`)の**二重設定＝多値リストで2件連結**なので2行出る（行数＝helper 件数）。対策は §git の CLAUDECODE 条件 helper。keychain を sandbox allowlist に足す方向は不採用（機微）。`.git/config` 書き込み(D5)とは別系統の write-deny |

## ファイル別の保護方針

新しい機密パスを足すときは、まず**保護クラス**を決め、レシピを**丸ごと**適用する。層ごとに場当たりで一部だけ書くとドリフトして片方の層に穴が残る（過去の 1Password write 無防備・認証 dir の Claude-tool write 開放がこれ）。**write 防御は必ず `Edit(...)` を書く**（組み込み file tool 全経路をカバー。`Write(...)` は無機能なので書かない＝`D3`）。Bash subprocess 経路は sandbox `denyWrite` が担う。

| クラス | 例 | レシピ |
|--------|-----|--------|
| **A. 全遮断ディレクトリ**（read も write も不可） | `~/.ssh` `~/.aws` `~/.kube` `~/.gnupg/private-keys-v1.d`、および dotfiles 管理下は実体パスで `~/dotfiles/.config/{gh,op,1Password}`（`D10`） | Permission `Read(~/dir/**)` + `Edit(~/dir/**)`（read 自動マージで subprocess も。write は Edit で新規作成も止まる）。＋明示性で sandbox `denyRead`/`denyWrite` も列挙 |
| **B. 公開 dotfile**（read 可・write 不可） | `~/.gitconfig` `~/.npmrc`（home） | Permission `Edit(~/file)`。Read deny は**書かない**。＋ sandbox `denyWrite` |
| **C. 解放だが改ざん防止**（read 可・write 不可） | shell rc（`~/.bashrc` `~/.zshrc` `~/.config/fish`）、gpg conf | exact-file または `~/dir/**` で Permission `Edit`。＋ sandbox `denyWrite`（allow 内例外はここが実効） |
| **D. FS 全体対称 deny**（`//**`） | 秘密鍵 `*.pem` `*.key` `id_rsa` 等 | Permission `Read(//**/X)` + `Edit(//**/X)`（read は sandbox マージで subprocess も遮断。unsandbox は `D1` の viewer 漏れが残る。**Bash subprocess の write は sandbox `denyWrite` 未列挙のため OS 遮断されない**＝Claude file tool 経路のみ Edit で塞ぐ限界を許容） |
| **E. secret / 認証ファイル名**（read 可・write 不可） | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` `*auth*.{json,toml,yaml,yml}` | Permission `Edit(//**/X)` を **FS 全体アンカー**で書く。`D9` により file tool と Bash subprocess の**両経路**が塞がる（sandbox `denyWrite` への列挙は不要） |
| **F. ツールの認証ファイル・ディレクトリ**（read も不可） | `~/dotfiles/.codex/auth.json`・`~/dotfiles/.config/{gh,op}` | クラスE の write 防御に加えて `Read(...)` deny を書く。パスは**実体のある側**で書く（`D10`）。`sandbox.credentials.files` は使わない（`Read()` で足りる） |

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
- `.env`（プロジェクト内）は開発上の正当な read 用途があるため read 解放。書き換えは `Edit` で防止する。`D9` により Edit deny は sandbox 境界へマージされるので、**組み込み file tool と Bash subprocess の両方**がこれ 1 本で止まる。

### 認証ファイルは名前のパターンで塞ぐ

ツールごとの認証ファイルは名前が揃っていない（`auth.json` / `.credentials.json` / `credentials.toml` / `oauth.yaml` …）。**個別列挙は必ず穴が残る**ので、ファイル名をワイルドカードにし、**FS 全体アンカー `//**/`** で書く:

```
Edit(//**/*secret*)  Edit(//**/*credential*)
Edit(//**/*auth*.json)  Edit(//**/*auth*.toml)  Edit(//**/*auth*.yaml)  Edit(//**/*auth*.yml)
```

- **`*auth*` に拡張子の制約を付ける**のが要点。無制約の `*auth*` はソースコード（`useAuth.tsx`・`authors.md`・`src/auth/`）まで巻き込んで日常の編集を壊す。設定・データ形式に限れば、実質すべての認証ファイルを捕まえつつ誤爆がほぼ無い。`oauth-*.yaml` のような派生も `*auth*` が拾う。
- アンカーは `**/`（cwd 相対）ではなく **`//**/`**（FS 全体）にする。前者は home 側の `~/.<tool>/auth.json` を取りこぼす。
- 遮断範囲（`D9`・`D11` で検証済み）: `service-auth.json` / `app.auth.toml` / `oauth-cache.yaml` / `my-credential.txt` / `api-secret.env` は Bash・組み込み file tool の双方で拒否。非マッチの `plain.json` / `mytoken.txt` は通常どおり編集できる。

**read まで塞ぐのは認証ファイル・認証ディレクトリだけ**にする（クラスF）。名前パターンで一律に read を止めるとテスト fixture や公開設定まで読めなくなり、摩擦が防御を上回る。

### dotfiles 管理下のパスは実体パスで deny する

`~/.config`・`~/.codex`・`~/.claude`・`~/.gemini`・`~/.agents` は dotfiles への**ディレクトリ symlink**。この配下を守る deny rule を `~/.config/...` の綴りで書くと、**file tool しか守れず Bash と OS 層は素通りする**（`D10`）。実体パス `~/dotfiles/...` で書けば 1 本で 3 層すべてに効き、symlink 綴りでのアクセスも止まる。

判定は **実体が dotfiles 側にあるか** の一点で足りる。

| 対象 | 綴り | 例 |
|------|------|-----|
| home に実体があるもの | `~/...`（それが実体） | `~/.ssh` `~/.aws` `~/.kube` `~/.docker` `~/.gnupg` `~/.netrc` |
| **dotfiles に実体があるもの** | **`~/dotfiles/...`** | `~/dotfiles/{.gitconfig,.npmrc,.bashrc,.zshrc}`、`~/dotfiles/.config/{gh,op,1Password,fish}/**`、`~/dotfiles/.codex` |

ファイル単体の symlink（`~/.gitconfig` 等）は sandbox が解決するので `~/...` 綴りでも 3 層に効くが、**綴りを使い分けない**。dir symlink 経由かどうかを読み手に判別させるより、dotfiles 管理下は一律に実体パスで書く方が誤りが起きない。

**両方の綴りを併記しない。** 実体パス形式は symlink 綴りでのアクセスも止める（包含関係にある）ので併記は純粋な冗長で、しかも「片方が無言で効いていない」状態を読み手に伝えられない。`~/.config` を symlink でなくす等、実体の置き場を変えたときはこの表に戻って綴りを見直す。この綴りの陳腐化は次節の hook が機械的に検出する。

### settings のパス綴りを hook で検査する

上の規約は「人とエージェントの注意力」でしか担保できず、`~/.config` を symlink でなくす等の構成変更で無言に陳腐化する。そこで `node-scripts/src/claude-settings-symlink-guard.ts` が `settings.json` を走査し、**symlink を経由するパスがあれば実体パスの綴りを添えて報告する**。

判定はパスの literal な接頭辞を root から 1 要素ずつ辿り、symlink があるかを見るだけ（実体が home にある `~/.ssh` 等は素通り、接頭辞が glob で始まる `//**/*.pem` 等は実体を特定できないので対象外）。**解決は「見つかった要素ごと」に行う**: 既に deny を掛けた `~/dotfiles/.config/gh` は自プロセスからも lstat が EPERM で落ちるため、一括 `realpath` にすると**最も守りたい行だけが例外で黙って落ちる**。

深刻度は 2 段階:

| 対象 | 深刻度 | 理由 |
|------|--------|------|
| permissions の `Read`/`Edit`/`Write` deny、sandbox の `denyRead`/`denyWrite` | error | 防御が効かないまま効いたつもりになる（`D10`） |
| permissions の allow / ask、sandbox の `allowRead`/`allowWrite`/`allowUnixSockets` | warn | 許可が効かず動かなくなるだけで穴にはならない（`D6`） |

配線は 2 つだけにする。**hook はイベントを増やすほど効くわけではない**（`ConfigChange` は発火しても反映を止められず、モデルにも届かないので採らない＝`D13`）:

| イベント | 検査対象 | error のとき |
|---|---|---|
| **PostToolUse**（`matcher: Edit\|Write` ＋ `if: Edit(//**/.claude/settings*.json)`） | 編集された当のファイル（`tool_input.file_path`） | exit 2 → **stderr がモデルに返り、その場で直させられる**。実効的な防御線はここ |
| **SessionStart**（`startup\|resume`） | user settings（`~/.claude/settings.json` と `settings.local.json`） | exit 2 → stderr を user に表示（起動は止まらない。表示は実測済み）。構成変更による陳腐化はここでしか拾えない |

**報告の 1 行目に結論を詰める**のは表示の都合。user 向け通知は接頭辞込み 200 文字で打ち切られる（`D15`）ので、`⚠️ NG <ファイル名>: symlink 綴りの <該当記述> → <直した形>（ほかN件）` の順で、後ろから消えても困らない並びにしてある。hook の command も `bun ~/dotfiles/…` と短く書いて本文の予算を稼ぐ。**接頭辞をさらに縮める案（`~/dotfiles/bin` は PATH 上なので bare name のラッパーを置けば 25 文字まで縮む）は採らない**: hook の PATH は claude を起動した親プロセスからの継承なので（fish の設定がその場で読まれるわけではない）、fish 経由でない起動では引けなくなる。現状は `bun` だけが PATH 依存で、スクリプトは絶対で指している。

`if` を **`//**/.claude/settings*.json`（suffix アンカー）**で書くのが要点:

- **綴りを 1 本で吸収する**。`if` は symlink を解決しない（`D14`）ため実体パスで書くと `~/.claude/...` 綴りの編集を取り逃がすが、suffix アンカーなら実体・symlink どちらの綴りでもマッチする（両方で発火を実測）
- **プロジェクト側の `.claude/settings.json` も検査対象になる**。permission 設定はプロジェクトでも普通に書くもので、そこに `~/.config/...` を書けば同じ欠陥になる。グローバル設定に置いた hook から全プロジェクトを見る形にして、各プロジェクトへ hook を挿さない
- 発火は settings ファイルの編集時のみ（`if` は harness 側で評価され、非マッチならプロセスも起こさない。NG を含む別名の JSON を編集しても発火しないことを実測）

手動実行は `bun ./node-scripts/src/claude-settings-symlink-guard.ts <settings.json ...>`（error があれば exit 1）。検査ロジックのテストは `node-scripts` で `bun run test`（一時ディレクトリに `link -> real` を作って回すので、machine の symlink 構成に依存しない）。テストは**辿れないパスでも検出できること**（上の EPERM）と**1 行目が短く収まること**も縛っているので、直すときはそこを壊さない。

コストは実測で **1 回 47ms**、うち 42ms が bun の起動で走査は約 5ms（58 エントリ・lstat 236 回）。**キャッシュは採らない**: 削れるのは 5ms 側だけなうえ、settings のハッシュでキャッシュすると「ファイルは無変更で FS 構成だけ変わった」という**検出したい当のケースで skip する**。

### Codex の設定を dotfiles 管理下に置く

`~/.codex` は `dotfiles/.codex` への symlink（他のツール dir と同じ型。追跡は `.gitignore` の allowlist で `AGENTS.md` のみ）。dotfiles 配下は cwd＝sandbox の write allowlist 内にあるため、**home 直下に置く場合と違って Bash subprocess から書き換えられる**点に注意する。`~/.claude` 配下のような harness 組み込みの保護は `.codex` には無い。

- `auth.json`: クラスF。`Read(~/dotfiles/.codex/auth.json)` と実体パスで書く
- `.codex` ディレクトリ全体: `sandbox.denyWrite` に `~/dotfiles/.codex` を置く。`hooks.json` を書き換えられると Codex 起動時のコード実行に繋がるため、subprocess からの write を丸ごと止める。Claude の file tool は sandbox を通らないので `AGENTS.md` の編集はできる

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

## サプライチェーン対策

PM（npm / bun / pnpm）側の多層防御は Claude Code 固有の話ではないため [docs/supply-chain-defenses.md](./supply-chain-defenses.md) が扱う。本書の範囲は、それを Claude Code の sandbox / permission で補強する部分（`env` ダンプと publish の `ask`、registry への egress 許可、cache の write 許可）。

### ccstatusline

statusLine / hooks で使う `ccstatusline` は `bunx -y @latest` を避け、`bun add -g ccstatusline@<固定版>` でグローバル導入し、コマンドを `ccstatusline --hook`（PATH 経由）にする。`@latest` は UserPromptSubmit / PreToolUse / statusLine の毎起動 fetch になり攻撃面が広い（理由は supply-chain-defenses の「層4」）。更新は `bun update -g ccstatusline`。PATH に `~/.bun/bin` が通っている前提。

## Sandbox 追加設定

### `enableWeakerNetworkIsolation: false`

macOS Sandbox 内のシステム TLS 信頼サービス（`com.apple.trustd.agent`）へのアクセスを許可するフラグ。`true` はセキュリティを低下させる。

- `true` が必要: `httpProxyPort` を MITM プロキシ + カスタム CA と併用し Go ベース CLI に TLS 検証させる環境。
- 本リポジトリ: MITM プロキシを使わないため `false`。gh の TLS 失敗は `excludedCommands: ["gh *"]`（sandbox 外実行）で回避する（「gh」参照）。

### npm install を sandbox 内で通す

sandbox は network を allowlist、write を cwd 中心の allowlist で絞るため、`npm install` には2点の明示許可が要る（実機で発覚）:

- **registry への egress**: `sandbox.network.allowedDomains` に取得先を列挙する。**proxy registry `npm.flatt.tech` と公開 `registry.npmjs.org` の両方**が要る。プロジェクト依存の install は proxy 経由だが、pnpm / yarn と mise 経由の npm 本体は非 FLATT backend で npmjs へ直接当たるため（この非対称の理由は [docs/supply-chain-defenses.md](./supply-chain-defenses.md) の「層3」）。`~/.npmrc` の registry 設定は read 解放で効くが、**ネットワーク到達は allowedDomains が別ゲート**なので両方そろえる。
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

## 別セッションでの実地検証

permission の効き方は cwd と設定の置き場に依存する。dotfiles では `~/.claude` が `~/dotfiles/.claude` への symlink なので、**この repo を cwd にしている限り両者が同じツリーに重なり、アンカー由来の欠陥を観測できない**（実際 `D11`・`D12` はこの方法でしか見つからなかった）。

**subagent は代替にならない。** 公式 Docs（sandboxing / Scope）に "subagents run in the same process as the parent session and use the same sandbox configuration" とあるとおり、親の cwd と sandbox 設定をそのまま引き継ぐため、cwd 依存の問題は原理的に再現できない。**シェルもセッションも独立した別インスタンスを user に起動してもらう**必要がある。

手順:

1. dotfiles の外に検証用ディレクトリを作る（`.claude/` を置かない＝project 設定が載らない素の状態にする）
2. **fixture は sandbox 外から作る**。deny 対象の名前を持つファイルは検証セッション自身では作れないため、呼び出し元が `dangerouslyDisableSandbox` で用意しておく
3. 引き継ぎ資料を同ディレクトリに置く。含めるのは**期待値つきのテスト手順**、**判定方法**（Bash は EPERM の有無、file tool は `denied by your permission settings` か `String to replace not found` かで判別）、**報告項目**
4. 禁止事項を明記する: 設定を変更しない／問題を修正しない（報告のみ）／認証ファイルを `cat` しない（`wc -c` を使う）／**`dangerouslyDisableSandbox` で再実行しない**／拒否されたコマンドを別手段で迂回しない。拒否されること自体が測定結果なので、回避されるとデータが失われる
5. 書き込み拒否は原因の切り分けを添える。cwd 外への write は deny ルールとは無関係に sandbox の write allowlist で拒否されるため、保護対象でないファイルを対照に置く

## 設定変更時の検証

permission は挙動が直感に反するため、**推測せず公式 Docs ＋実機で検証する**（`.claude/rules/claude-code-settings.md`）。

- ダミーファイルを `$TMPDIR/<test>/` または cwd（`./<test>/`）に作り、Bash と Read/Edit tool で deny されるか確認する（どちらも sandbox 書込可）。
- 設定は live reload で同セッション内に反映される（Bash deny・sandbox filesystem・Read/Edit/Write tool deny いずれも実機確認）。**tool の write 防御は必ず `Edit(...)` deny で試す**。`Write(...)` は組み込み Write tool に効かないため、`Write` だけで試すと「効かない」と誤認する（`D3`）。
- built-in deny の有無を確認する時は、sandbox `denyRead` と Permission `Read(...)` deny の**両方**を外してから確認する（Permission deny が sandbox にマージされ `denyOnly` に出るため、片方だけ外すと出自を誤認する）。
- 一時編集した settings.json は完全復元する。Bash の `cp` 復元は sandbox 自己保護（`denyWithinAllow` に settings.json 実体）で拒否されるため、Edit/Write tool で戻す。
- 破壊的副作用に注意: socket（`allowUnixSockets`）を外す検証は gpg-agent を停止させ sandbox 内から復活できない。検証後は sandbox 外で `gpgconf --launch gpg-agent`。

## 関連

- 公式 Docs（仕様の一次情報・毎回参照）: [permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing)
- [docs/supply-chain-defenses.md](./supply-chain-defenses.md): PM のサプライチェーン防御（保持期間・postinstall・proxy registry）
- `.claude/rules/claude-code-settings.md`: 設定変更時の鉄則（公式 Docs 参照・実機検証）
- `### AI tools`（README.md）: MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定（実効パスは `.config/.bunfig.toml` の symlink 経由）
- `dotfiles/.config/pnpm/config.yaml`: pnpm 11+ の supply-chain 設定
