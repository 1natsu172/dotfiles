# Claude Code のセキュリティ運用

`~/.claude/settings.json` のセキュリティルールは、プロンプトインジェクションや Shai-Hulud 型のサプライチェーン攻撃に対する多層防御として設計している。設計判断の背景と、運用上踏み外しがちなポイントを記録する。設定の実体は `dotfiles/.claude/settings.json` を参照。

## Sandbox と Permission の役割分担

| レイヤ | 対象 | 設定箇所 |
|--------|------|----------|
| Sandbox | bash サブプロセス全体（git CLI / mise / node / 任意の外部プロセス）を OS レベルで物理遮断 | `sandbox.filesystem.denyRead` / `denyWrite` |
| Sandbox 例外解除 | Claude Code 内蔵の denyRead を上書きして特定パスのみ読み取り許可 | `sandbox.filesystem.allowRead` |
| Permission (Read tool) | Claude の Read tool 経由 + 一部の Bash 認識ファイルコマンド | `permissions.deny: Read(...)` |
| Permission (Bash tool) | Claude が叩く Bash 引数文字列 | `permissions.deny: Bash(...)` |

## Read / Edit deny のパス書式

書式によって解釈が大きく変わる。間違えると全く効かない。

| 書式 | 解釈 | 例 |
|------|------|---|
| `~/path` | home 相対 | `Read(~/.gitconfig)` |
| `//path` | 真の絶対パス（leading double-slash） | `Read(//tmp/age.txt)` |
| `/path` | プロジェクトルート相対（cwd 相対ではない） | `Edit(/src/**/*.ts)` |
| `path`, `./path` | 現在のディレクトリ相対 | `Read(*.env)` |
| `**/X` | gitignore セマンティクス、cwd 配下を再帰 | `Read(**/.env)` |
| `//**/X` | ファイルシステム全体を再帰 | `Read(//**/age.txt)` |

**落とし穴**: `Read(/Users/me/foo)` は絶対パスではなく `<cwd>/Users/me/foo` として解釈される。ホーム配下を狙うなら `~/path` または `//Users/me/path` を使う。

## Read deny の Bash カバー範囲

tilde 形式 (`Read(~/path)`) や `//**/` 形式の Read deny は、Claude の Read tool だけでなく Bash の `cat`/`head`/`tail`/`sed` 等の認識ファイルコマンドにも自動的に適用される。Edit/Write deny も同じ書式仕様で動作する（実機確認済み）。

ただし以下の条件で Bash カバー効果が変わる:

- `sandbox.filesystem.allowRead` に入っているパスは、Permission Read deny の Bash カバー効果が消える。Sandbox 層で OS レベル read が許可されると Permission 層が Bash 経由を見逃すため、別途 Bash deny を明示する必要がある
- `xxd`/`od`/`wc`/`less`/`bat`/`more` 等の viewer は Read deny でカバーされない。完全遮断したいパスには別途 Bash deny が必要
- `sed` は read-only 用途 (`sed -n '1,3p' file`) でも Edit 扱いで allowed working directory 制限が走る

## Bash matcher の挙動

- `*` はスラッシュ `/` と leading dot (`.env`, `.npmrc` 等) を貫通する fnmatch 系
- コマンドライン全体を fnmatch 評価。`head -c 100 ~/.gitconfig` のようなオプション先頭呼び出しも `Bash(head *.gitconfig)` でマッチ
- シェルオペレータ (`&&`, `||`, `;`, `|` 等) でサブコマンドに分割して個別評価
- 抜け穴: `.env.local` のような中間ドットサフィックスは `*.env` (末尾) にも `.env.*` (先頭) にもマッチしない。`*.X.*` パターンを別途用意する
- Bash redirect (`echo X > /path/.npmrc`) は `Write(**/.npmrc)` deny に評価される副次保護

## built-in 読み取り専用コマンドは allow 不要

Claude Code は組み込みで読み取り専用コマンドを認識し、権限プロンプト不要で実行する: `ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, `git` の読み取り形式 + `sort`, `uniq`。

これらを `Bash(cat *)` 等で allow に明示するのは冗長。

## `~/.gitconfig`: 一般 dotfile として扱う

`~/.gitconfig` は dotfiles リポジトリで公開管理しているため、AI に見せる必要はあるが秘匿価値はない。Claude Code 内蔵の Sandbox denyRead で gitconfig はデフォルトでブロックされるため、git CLI が動かない問題を回避するために `allowRead` で例外解除する。

- `sandbox.filesystem.allowRead: ["~/.gitconfig"]` で内蔵 deny を解除 → git CLI のサブプロセス read 可能
- `sandbox.filesystem.denyWrite` に維持 → 書き換え防止
- Permission Read deny / Bash viewer deny は **書かない**

## `~/.config/mise/age.txt`: 三層遮断（本丸完全遮断）

`## SOPS` (README.md) の前提となる age 復号鍵。いかなる経路でも AI に触らせない。

- 本丸 (`~/.config/mise/age.txt`) は exact match で明示的に三層遮断:
  - Sandbox `denyRead` → 物理層。bash サブプロセス（mise 含む）も読めない
  - Permission `Read(~/.config/mise/age.txt)` → Claude Read tool で本丸直撃
  - Permission `Bash(<viewer> *age.txt*)` を全 viewer (`cat`/`head`/`tail`/`less`/`bat`/`more`/`wc`/`sort`/`nl`/`tac`/`xxd`/`od`/`strings`) に展開 → Bash サイドチャネル
- リネーム/別パス保険レイヤ:
  - `Read(//**/age.txt)` / `Edit(//**/age.txt)` / `Write(//**/age.txt)` でファイルシステム全体カバー（ホーム配下も `/tmp`/`/var/folders` 等も含む）
  - `Write(//**/age.txt)` の副次保護として Bash redirect (`echo ... > /path/age.txt`) もブロックされる
  - Bash 経由は `*age.txt*` 系で位置非依存に網羅

unsandbox 時 (`dangerouslyDisableSandbox: true`) でも本丸の三層は維持されることが運用上の重要ポイント。

## その他のシークレット系: Sandbox に任せる

`.env`/`.npmrc`/`.netrc`/`*secret*`/`*credential*`/`id_rsa*`/`*.pem`/`*.key`/`*.tfstate*` 等の典型シークレットは Claude Code 内蔵の Sandbox `denyOnly` に glob パターンで含まれているため、Sandbox 有効時はサブプロセスごと OS レベルで物理遮断される。

これらに対する Permission Bash viewer deny の網羅は冗長化を招くため最小化する:

- Permission Read deny で Claude の Read tool 経由はブロック
- Bash 経由は Sandbox に任せる
- unsandbox 時は ask または default モードで都度判断（裏取りシナリオで読みたい時に対応可能）

## bun のサプライチェーン対策（Shai-Hulud 型）

bun は `.npmrc` の `min-release-age` を読まない ([oven-sh/bun#22679](https://github.com/oven-sh/bun/issues/22679)) ため、`~/.bunfig.toml` の `[install] minimumReleaseAge` で別途設定する必要がある:

- 単位差に注意: pnpm/npm は **日単位**、bun は **秒単位**（`604800` = 7日）

### ccstatusline の運用方針

statusLine / hooks で使う `ccstatusline` は、`bunx -y @latest` を避けて `bun add -g` + PATH 経由で運用する。`@latest` で毎起動ごとに fetch する経路はサプライチェーン攻撃の格好の経路（UserPromptSubmit / PreToolUse / statusLine の 3 箇所で頻発）。

- `bun add -g ccstatusline@<固定版>` で global install
- hook/statusLine command を `ccstatusline --hook` (PATH 経由) に置換
- 更新時は `bun update -g ccstatusline` で `minimumReleaseAge` が効いた版を取得

PATH に `~/.bun/bin` が通っている前提（mise 経由 bun で自動設定）。

## Sandbox の追加設定

### `enableWeakerNetworkIsolation: false`

macOS の Sandbox 内でシステム TLS 信頼サービス (`com.apple.trustd.agent`) へのアクセスを許可するフラグ。Docs 上「セキュリティを低下させ、データ流出の可能性のあるパスを開く」と警告されている。

- **`true` が必要なケース**: `httpProxyPort` を MITM プロキシ + カスタム CA と組み合わせて使い、`gh`/`gcloud`/`terraform` 等の Go ベース CLI に TLS 検証させる必要がある環境
- **本リポジトリの方針**: MITM プロキシを使わないため `false` に設定。`gh auth status` で TLS 検証が動作することを実機確認済み
- **変更時の確認**: Go ベース CLI が動くかを `gh auth status` または `gh api user` で検証

## 設定変更時の検証

permission ルールは matcher の挙動が直感に反することが多いため、推測で書かず実機検証する:

- ダミーファイルを `$TMPDIR/<test-name>/` または `~/<test-name>/` に作って、Bash と Read tool の両方で deny されるか確認
- 設定変更は live reload で同セッション内に反映される。sub-agent に検証を渡す方式で完結可能
- 検証用に settings.json を一時編集した場合は完全復元（バックアップを取って diff zero 確認）

## 関連

- `## SOPS` (README.md): age.txt の用途と運用
- `## AI tools` (README.md): MCP / plugins / Agent Skills の管理方針
- `dotfiles/.claude/settings.json`: 設定の実体
- `dotfiles/.bunfig.toml`: bun の supply-chain 設定
