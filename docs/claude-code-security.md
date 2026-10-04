# Claude Code のセキュリティ設定

設定の実体は `.claude/settings.json`。仕様は公式 Docs（[permissions](https://code.claude.com/docs/en/permissions) / [sandboxing](https://code.claude.com/docs/en/sandboxing)）を見る。ここには dotfiles での判断と、公式 Docs から読み取れない検証済みの挙動（delta 表）だけを書く。

脅威モデルは 2 つ。プロンプトインジェクション（実行主体は Claude の Bash / Edit / Write tool）と、Shai-Hulud 型のサプライチェーン攻撃。

## 層の分担

- sandbox は Bash の subprocess にだけ効く。permission rule は全 tool に効く
- permission の `Read` / `Edit` deny は sandbox の境界にも反映される（`D9`）。逆に sandbox の `denyRead` / `denyWrite` は Claude の file tool に効かない
- したがってパスの保護は permission の `Read(...)` / `Edit(...)` deny を書けば両方の経路に効く。sandbox 側にも同じパスを並べているのは、sandbox の設定だけ見て何が遮断されるか分かるようにするためで、意図した冗長である
- write の deny は `Edit(...)` で書く。`Write(path)` は何も止めないうえ起動時に WARN が出る（`D3`）

## 検証済み delta

公式 Docs に無い、または読み落としやすい実機の挙動。検証日とバージョンは最後に真と確認した時点を表す。挙動が変わっていたら行を書き換え、不要になったら消す。

| ID | 検証日 | CC ver | 挙動 |
|----|--------|--------|------|
| `D1` | 2026-05-23 | 未記録 | Read / Edit deny が Bash に及ぶのは `cat` `head` `tail` `sed` などの認識済みコマンドだけで、`xxd` `od` `wc` `less` `strings` などは漏れる。sandbox 内では OS 層で遮断されるので表に出ず、漏れるのは `excludedCommands` など sandbox 外の経路。`sed` は読み取りでも Edit 扱い |
| `D2` | 2026-05-25 | 2.1.150 | Bash の matcher は `&&` `;` `\|` `$(...)` を分解して評価するが、別パス名（`/bin/echo`）やインタプリタ経由（`sh -c`）は取りこぼす。Bash の deny は誤承認を防ぐ程度のもので、境界は sandbox |
| `D3` | 2026-07-15 | 2.1.210 | `Write(path)` の permission rule は何も止めない。組み込み Write tool は Edit 扱いで `Edit(...)` が止め、Bash の redirect も `Write(...)` では止まらない。パス無しの `Write`（tool 全体）は別扱いで有効 |
| `D4` | 2026-05-25 | 2.1.150 | 秘密鍵用の `Read(//**/*.pem)` が公開 CA バンドル（`cert.pem`）まで遮断し、sandbox 内の `git push` や `curl` が TLS 確立前に失敗する。対処は「sandbox 内で TLS を通す」 |
| `D5` | 2026-10-04 | 2.1.288 | `.git/config` と `.git/hooks/` は harness 組み込みで sandbox から書けない。`git push -u` と `git branch -d` は本体の操作だけ成功し、config の更新は失敗する。`git push -u` は exit 0 で「set up to track」と表示するので失敗に気付けない。Claude の Edit tool からは書ける |
| `D6` | 2026-07-12 | 2.1.207 | sandbox のファイル判定は symlink を解決した実体パスで行う。`allowWrite` に symlink 側の綴りを書いても効かないので、dotfiles 管理のパスは `~/dotfiles/...` で書く |
| `D7` | 2026-07-22 | 2.1.216 | sandbox は keychain への書き込みを遮断する。git の `osxkeychain` helper は認証後の store で `fatal: failed to store: 100001` を出すが、認証は通っていて exit 0。helper が system と global の 2 箇所で設定されていると 2 行出る |
| `D8` | 2026-06-18 | 未記録 | `autoAllowBashIfSandboxed` でも明示の `ask` は sandbox 内で発火する（`deny` > `ask` > auto-allow）。パイプの後段も単独で判定される。`sed` などの viewer を `ask` に置くと、ページングのたびに発火し、非対話の subagent は denied として扱う |
| `D9` | 2026-07-27 | 2.1.220 | `Edit(...)` deny は sandbox の write 境界に反映され、Bash の書き込みも EPERM で止まる。sandbox の `denyWrite` が別途要るのは、パターンで書けないものや Claude の file tool には編集させたいもの（`~/dotfiles/.codex`）だけ |
| `D10` | 2026-07-27 | 2.1.220 | deny のパスが dir symlink を経由すると file tool にしか効かず、Bash と OS 層を素通りする。ファイル単体の symlink（`~/.gitconfig`）は解決される。実体パスで書けば 3 層すべてに効き、symlink 綴りのアクセスも止まる。upstream が直しても実体パスの記述は正しいまま残る |
| `D11` | 2026-07-27 | 2.1.220 | `**/X` の deny は層によって効き方が違う。ファイル型（`**/.env`）は Bash にだけ効いて file tool を通し、ディレクトリ型（`**/secrets/**`）は file tool にだけ効いて Bash を通す。user settings の rule は `~/.claude` を起点に照合されるので、dotfiles を cwd にすると cwd と照合の起点が同じツリーに重なり、この食い違いを検出できない。`//**/X` なら file tool では全パターンが止まる |
| `D12` | 2026-07-27 | 2.1.220 | deny が OS 層まで届くかは接頭辞で決まる。`//**/*.pem` や `~/dotfiles/.config/gh/**` は配下まで届く。`//**/secrets/**` のように接頭辞が wildcard だと、OS 層ではディレクトリの作成禁止までしか届かず、既存ディレクトリ配下への Bash の書き込みは通る |
| `D13` | 2026-07-28 | 2.1.220 | `ConfigChange` hook は発火するが、exit 2 でも `decision: block` でも設定の反映を止められず、通知もモデルに届かない。1 回の変更で複数回発火する。採用していない |
| `D14` | 2026-07-28 | 2.1.220 | hook の `if` は symlink を解決しない。実体パスで書くと symlink 綴りの tool call を取り逃がす。`//**/.claude/settings*.json` のように末尾で合わせれば両方の綴りに当たる |
| `D15` | 2026-07-28 | 2.1.220 | user に表示される hook の通知は `[<hook の command>]: ` を含めて 200 文字で切られる。モデルに返る PostToolUse の stderr は全文。1 行目に結論を書き、command は `bun ~/dotfiles/...` のように短く書く |
| `D16` | 2026-07-29 | 2.1.220 | lefthook の hook 自動同期が `.git/hooks/` の書き込み禁止（`D5`）に当たり、commit のたびにエラーを出す。commit 自体は成功する。`lefthook.yml` の `no_auto_install: true` で止め、hook の種類を増やしたときだけ手で `lefthook install` する |
| `D17` | 2026-06-26 | 未記録 | macOS の `security` CLI の書き込み系（`list-keychains -s` など）は sandbox 内で exit 0 のまま何もしない。読み取り系は通るので成功したように見える。sandbox 外で実行し直す |
| `D18` | 2026-08-17 | 2.1.233 | hook の `if` は tool 名をそのまま比べるので、permission と逆に `Edit(...)` は Write tool に当たらない。Edit と Write の両方を捕まえるなら `if` を 2 エントリ並べる |
| `D19` | 2026-10-05 | 2.1.289 | `excludedCommands` はコマンド全体が除外パターンに当たるときだけ効く。同じパターン同士の `&&` `;` と `2>&1` は sandbox 外で動く。パイプ、ファイルへのリダイレクト、`$(...)`、heredoc、ほかのコマンドとの連結を含むと、全体が sandbox 内で動く |

## ファイル別の保護方針

新しい機密パスを足すときは、まずクラスを決めてその方法をまとめて適用する。層ごとに一部だけ書くと、片方の層に穴が残る。

| クラス | 例 | 書き方 |
|--------|-----|--------|
| A. read も write も禁止 | `~/.ssh` `~/.aws` `~/.kube` `~/.gnupg/private-keys-v1.d` `~/dotfiles/.config/{gh,op,1Password}` | `Read(~/dir/**)` と `Edit(~/dir/**)`。sandbox の `denyRead` / `denyWrite` にも並べる |
| B. 公開 dotfile | `~/dotfiles/.gitconfig` `~/dotfiles/.npmrc` | `Edit(...)` だけ。sandbox の `denyWrite` にも並べる |
| C. 改ざん防止 | `~/dotfiles/{.bashrc,.zshrc}` `~/dotfiles/.config/fish` gpg の conf | `Edit(...)`。sandbox の `denyWrite` にも並べる |
| D. どこにあっても read も write も禁止 | `*.pem` `*.key` `id_rsa` など秘密鍵 | `Read(//**/X)` と `Edit(//**/X)` |
| E. どこにあっても write を禁止 | `.env` `.env.*` `secrets/**` `*secret*` `*credential*` `*auth*.{json,toml,yaml,yml}` | `Edit(//**/X)` |
| F. ツールの認証ファイル | `~/dotfiles/.codex/auth.json` `~/dotfiles/.config/{gh,op}` | E に加えて `Read(...)`。`sandbox.credentials.files` は使わない |

- 公開 dotfile の read を開けているのは、`.npmrc` のサプライチェーン設定を npm / pnpm の subprocess に読ませる必要があるため。`.gitconfig` は公開しているもので秘匿の価値がない。write は塞ぐ。`.npmrc` は registry のすり替えや `min-release-age` の削除、`.gitconfig` は alias や `core.sshCommand` によるコード実行につながる
- read を開けたファイルに平文の秘匿情報を置かない。token は `${VAR}` で参照し、実体は fnox で注入する（[fnox-token-management.md](./fnox-token-management.md)）
- 秘密鍵の `*.key` / `*.pem` は秘密鍵以外も巻き込む。CA バンドルだけは read を個別に開けている（「sandbox 内で TLS を通す」）
- 認証ファイルは名前が揃わないので個別に列挙せず、パターンで塞ぐ。`*auth*` は拡張子を設定形式に絞らないと `useAuth.tsx` などソースまで巻き込む。`*secret*` と `*credential*` は markdown の名前にも当たるので、doc のファイル名にこれらの語を入れない
- read まで塞ぐのは認証ファイルだけにする。名前のパターンで read を止めると test fixture まで読めなくなる

### dotfiles 管理下のパスは実体パスで deny する

`~/.config` `~/.codex` `~/.claude` `~/.gemini` `~/.agents` は dotfiles へのディレクトリ symlink なので、配下の deny は `~/dotfiles/...` で書く（`D10`）。home に実体があるもの（`~/.ssh` など）は `~/...` のまま書く。両方の綴りを並べると、片方が効いていなくても気付けないので並べない。ファイル単体の symlink（`~/.gitconfig`）は `~/...` でも効くが、dotfiles 管理下は一律に実体パスで書く。

### settings のパス綴りを hook で検査する

`node-scripts/src/claude-settings-symlink-guard.ts` が settings を走査し、symlink を経由するパスを実体パスの綴りと一緒に報告する。`~/.config` を symlink でなくすなど、構成が変わって綴りが古くなったときも検出できる。

| 対象 | 深刻度 | 理由 |
|------|--------|------|
| permission の deny、sandbox の `denyRead` / `denyWrite` | error | 効いていないのに効いているように見える（`D10`） |
| permission の allow / ask、sandbox の `allowRead` / `allowWrite` / `allowUnixSockets` | warn | 許可が効かないだけで穴にはならない（`D6`） |

| hook | 検査対象 | error のとき |
|---|---|---|
| PostToolUse（`if` は `Edit(//**/.claude/settings*.json)` と `Write(...)` の 2 本） | 編集されたファイル | exit 2 で stderr をモデルに返し、その場で直させる |
| SessionStart（`startup\|resume`） | `~/.claude/settings.json` と `settings.local.json` | exit 2 で user に表示する（起動は止まらない） |

- `if` は末尾で合わせる（`D14`）。実体と symlink の両方の綴りに当たり、他 project の `.claude/settings.json` も検査できる
- symlink は見つかった要素ごとに解決する。一括の `realpath` だと、deny 済みの `~/dotfiles/.config/gh` で lstat が EPERM になり、最も守りたい行だけが黙って落ちる
- 報告の 1 行目に結論を書く（`D15`）。test はこの長さと EPERM の扱いも検査している
- キャッシュはしない。1 回 47ms のうち 42ms は bun の起動で、settings のハッシュでキャッシュすると「ファイルは同じで FS の構成だけ変わった」場合を見逃す

手動で回すときは `bun ./node-scripts/src/claude-settings-symlink-guard.ts <settings.json ...>`（error があれば exit 1）。test は `node-scripts` で `bun run test`。

### Codex

`~/.codex` も dotfiles への symlink で、実体は cwd の中にあるので Bash から書ける。`~/.claude` のような harness の保護は無い。`auth.json` はクラス F。ディレクトリ全体は sandbox の `denyWrite` に置き、`hooks.json` の書き換えによる起動時のコード実行を防ぐ。Claude の file tool は sandbox を通らないので `AGENTS.md` は編集できる。

## Bash コマンドの実行制御

`autoAllowBashIfSandboxed: true` なので、sandbox 内のコマンドは明示ルールに当たらなければ自動で許可される（`D8`）。`allow` が意味を持つのは sandbox 外で実行するコマンド（`excludedCommands`）と WebFetch だけ。

`excludedCommands` はコマンド全体が当たるときしか効かない（`D19`）ので、AI には除外したコマンドを単独で打たせる（`.claude/rules/sandbox-excluded-commands.md`）。

### ask

sandbox の中でも外部への送信やデータの消失は起こりうるので、そういう操作だけ `ask` に置く。

- `curl *` `wget *` `rm *`: 外部への送信と不可逆な削除
- `env` `printenv *`: fnox が注入した token をまとめて出力する経路で、Shai-Hulud 型が env を漁る挙動そのもの
- `* publish *`: 不可逆な外部公開で、侵害された環境から汚染版を publish して広がる経路でもある
- `gh workflow run *` `gh run rerun *`: CI を動かす

`sed` などの viewer は置かない（`D8`）。迂回できる（`D2`）ので防御にならず、subagent が止まるだけになる。

### git

sandbox 内の git には permission rule を置かない。auto-allow で動き、push 先は `allowedDomains` の github に限られる。

upstream を設定する push だけは `excludedCommands` で sandbox 外に出す（`D5`）。

- remote は `origin` に固定する。`git push -u *` を許すと `ext::sh -c ...` や任意のホストへの送信が通る。`remote.origin.url` は `.git/config` にあって sandbox から書き換えられないので信頼できる
- sandbox 外のコマンドは permission の判定を受けるので、`allow` にも同じ形で書く
- `excludedCommands` の変更はセッションの再起動で反映される

keychain への store 失敗（`D7`）は `~/.gitconfig` の credential helper で黙らせる。helper を `helper =` でリセットしてから `~/dotfiles/bin/credential-helper.sh` 1 本に置き換え、Claude Code の中でだけ `store` / `erase` を何もしないようにしている。

- git の push / fetch 全体を sandbox 外に出す案は採らない。複合コマンド（`D19`）や子プロセスの git には効かない
- スクリプトに実行権が無いと `get` が exit 126 で失敗し、git が対話プロンプトで止まる
- Homebrew の `/opt/homebrew/etc/gitconfig` は `brew upgrade` で復活するので、消さずにリセットで無効化する

### gh

gh は Go 製で、Seatbelt の中では TLS 検証に失敗する。`excludedCommands: ["gh *"]` で sandbox 外に出し、permission で制御する。`excludedCommands` は引数まで照合するので wildcard が要る。

- allow: 読み取り系（`pr view` `pr list` `pr diff` `pr checks` `issue view` `issue list` `repo view` `run view` `run list` `release view` `release list` `search` `label list` `auth status`）と `pr create` `pr edit` `pr comment`
- deny: `auth token` `secret *` `repo delete *` `gist create *` `ssh-key *` `gpg-key *`
- `gh auth status` は完全一致で書き、`gh auth token` の deny と重ならないようにする

### fnox

fnox が呼ぶ op も Go 製で、Seatbelt の中では TLS 検証に失敗する。`excludedCommands: ["fnox *"]` で sandbox 外に出す。

- 除外するのは `op *` ではなく `fnox *`。`excludedCommands` は Claude が送るコマンド文字列の先頭に当たるので、子プロセスの op は名前では捕まらない
- `fnox get *` と `fnox export *` は値を出力するので deny。`fnox exec` は値を出さずに子プロセスへ注入するだけなので許可する
- シェル関数のラッパー経由の `npm install` は送信文字列が `npm ...` なので sandbox 内に残り、401 になる。token が要る操作は `fnox exec -- <pm> ...` と打つ（`.claude/rules/sandbox-excluded-commands.md`）。`npm *` を丸ごと除外するより範囲が狭く、token の要らない install は sandbox に残せる
- 原因は Go と Seatbelt の TLS 検証で、通信先の許可ではない。`allowedDomains` に足しても `SSL_CERT_FILE` を設定しても直らない

### hunk

hunk はローカルのデーモンと通信する。sandbox は localhost への接続も塞ぐので、TUI は起動するのにセッションが無いように見える。`excludedCommands: ["hunk *"]` で sandbox 外に出す。`allow` は書いていないので毎回確認が出る。

### 破壊系コマンドの deny

`sudo` `su` `rm -rf /` `dd` `defaults write` などの deny は `sh -c` などで迂回できる（`D2`）ので、誤承認を防ぐ程度のものと割り切り、変種を網羅しない。

- `defaults write / delete / import` は sandbox の外にある cfprefsd 経由で設定を変えるので、sandbox では止まらない。deny が実際に効く数少ない例
- `chmod 777 *` は置かない。sandbox で既に止まり、`chmod -R 777` などの変種も漏れるので、効いている気がするだけになる

## Sandbox の追加設定

- `enableWeakerNetworkIsolation: false`: MITM プロキシを使わないので有効にしない。gh の TLS 失敗は `excludedCommands` で避ける
- `allowedDomains` に `npm.flatt.tech` と `registry.npmjs.org` の両方を入れる。project の依存は proxy 経由だが、pnpm / yarn や mise が入れる npm 本体は npmjs に直接取りに行く（[supply-chain-defenses.md](./supply-chain-defenses.md) の層 3）。通信先は必要最小限に絞る
- `allowWrite` は cwd の外へ書く cache だけを個別に足す。範囲を広げると `$PATH` 上の実行物を書き換えられる経路になる

| パス | 用途 |
|---|---|
| `~/.npm/_cacache` | npm の cache。`~/.npm/_logs` は既定で許可されている |
| `~/dotfiles/.bun/install/cache` | bun の cache と install の一時領域。`~/.bun` は symlink なので実体パスで書く（`D6`） |
| `~/.local/state/mise/trusted-configs` | mise の config の信頼状態 |
| `~/Library/Caches/mise` | mise の cache |
| `~/.gnupg` | 署名の検証が trustdb のロックで書き込む |

### sandbox 内で TLS を通す

`Read(//**/*.pem)` が CA バンドルまで遮断する（`D4`）ので、次の 2 つで通す。

- `allowRead` に `/opt/homebrew/etc/ca-certificates/cert.pem` を足す。中身は公開のルート証明書だけなので read を開けてよい。偽の CA の追記は `Edit(//**/*.pem)` で引き続き止まる
- settings の `env` で `GIT_SSL_CAINFO`・`SSL_CERT_FILE`・`CURL_CA_BUNDLE` を同じファイルに向ける。git は `SSL_CERT_FILE` だけでは読まない。Claude Code の sandbox に固有の問題なので、mise などの global env には置かない

### GnuPG 署名

- `allowUnixSockets: ["~/.gnupg/S.gpg-agent"]` が無いと署名できない。パスは `gpgconf --list-dirs agent-socket` と合わせる
- `gpg-agent.conf` `gpg.conf` `dirmngr.conf` は `pinentry-program` の書き換えでパスフレーズを盗まれるので、sandbox の `denyWrite` と `Edit(...)` の両方で塞ぐ
- socket を塞ぐと gpg-agent が止まり、sandbox 内からは起動し直せない。sandbox 外で `gpgconf --launch gpg-agent` を実行する

## 別セッションでの実地検証

dotfiles を cwd にすると `~/.claude` と cwd が同じツリーに重なり、rule の照合の起点に由来する欠陥が見えない（`D11` と `D12` はこの方法でしか見つからなかった）。subagent は親と同じ cwd と sandbox 設定で動くので代わりにならない。user に別のセッションを起動してもらう。

1. dotfiles の外に `.claude/` を置かない検証用ディレクトリを作る
2. deny 対象の名前を持つ fixture は検証セッション自身では作れないので、呼び出し側が sandbox 外で用意する
3. 期待値つきの手順、判定方法、報告項目を書いた引き継ぎ資料を置く。判定は、Bash なら EPERM の有無、file tool なら `denied by your permission settings` と `String to replace not found` のどちらが出るかで行う
4. 設定の変更、修正、認証ファイルの `cat`、`dangerouslyDisableSandbox` での再実行、拒否されたコマンドの迂回を禁じる。拒否されたこと自体が測定結果になる
5. cwd の外への書き込みは deny と関係なく sandbox の allowlist で拒否されるので、保護対象でないファイルを対照に置く

## 設定変更時の検証

- 同じセッション内の確認は `$TMPDIR` か cwd にダミーを作り、Bash と file tool の両方で試す。sandbox 内の `$TMPDIR` は `/tmp/claude-<uid>` に置き換わっている
- 設定は同じセッションに live reload される。ただし `ask` を消した直後の数コマンドは古いルールが発火することがあるので、`/permissions` で確かめる
- 組み込みの deny の有無を調べるときは、sandbox の `denyRead` と permission の `Read(...)` の両方を外す。片方だけだと出どころを取り違える
- 一時的に書き換えた settings は file tool で戻す。settings の実体は sandbox が書き込みを禁じているので `cp` では戻せない

## 関連

- [claude-code-instruction-loading.md](./claude-code-instruction-loading.md): rule の `paths` の解決規則
- [supply-chain-defenses.md](./supply-chain-defenses.md): npm / bun / pnpm 側の防御
- [fnox-token-management.md](./fnox-token-management.md): token の注入
