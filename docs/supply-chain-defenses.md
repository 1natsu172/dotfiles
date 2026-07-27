# サプライチェーン防御（npm / bun / pnpm）

脅威モデルは **Shai-Hulud 型の即時拡散**。公開直後の汚染版を掴む、postinstall が install 中に env の秘匿情報を持ち出す、侵害環境から汚染版を publish して広がる、の3経路を想定する。単一の対策に賭けず、独立に効く層を重ねる。

関連する別レイヤ:

- Claude Code の sandbox / permission による補強（`env` ダンプや publish の承認、registry への egress 許可）: [docs/claude-code-security.md](./claude-code-security.md)
- 秘匿情報を消費プロセスにだけ絞って注入する仕組み: [docs/fnox-token-management.md](./fnox-token-management.md)

## 層1: 新規公開版の保持期間（min-release-age 系）

「公開直後の版を掴まない」ことで、汚染版が発見・撤回されるまでの時間を稼ぐ主防御。本リポジトリは 7 日で揃えている。

**PM ごとに設定ファイル・キー名・単位がすべて違う**:

| PM | 設定ファイル | キー | 7 日相当 |
|----|------------|-----|---------|
| npm | `.npmrc` | `min-release-age` | `7`（日） |
| pnpm <=10 | `.npmrc` | `minimum-release-age` | `10080`（分） |
| pnpm 11+ | `.config/pnpm/config.yaml` | `minimumReleaseAge` | `10080`（分） |
| bun | `.config/.bunfig.toml` の `[install]` | `minimumReleaseAge` | `604800`（秒） |

**取り違えてもエラーは出ず、防御だけが静かに消える**。「設定した気になる」のがこの層の最大のリスクで、実際に長期間無効だった事例がある（bun の項）。

- **npm の `min-release-age` を pnpm は読まない**（no-op）。キー名が別なので `.npmrc` に両方書く。
- **pnpm は 9.x には機能自体が無く**、10.16+ で導入された。**11+ は `.npmrc`（INI）を一切読まず** `config.yaml`（YAML / camelCase）のみを見る。`save-exact` も同様に無視されるため `saveExact: true` を併記しないと、11 へ上がった時点で厳密固定が黙って失われる。
- **bun のグローバル設定は `~/.bunfig.toml` では効かない**。`XDG_CONFIG_HOME` が設定されていると bun は `$XDG_CONFIG_HOME/.bunfig.toml` だけを見てホーム側へフォールバックしない（[oven-sh/bun#30842](https://github.com/oven-sh/bun/issues/30842)）。本リポジトリは fish で `XDG_CONFIG_HOME=~/.config` を設定しているため、`.config/.bunfig.toml` を `../.bunfig.toml` への相対 symlink にし、同一実体を 2 箇所から参照させている。**この symlink を外すと bun のグローバル設定が丸ごと無効になる**（エラーは出ない）。
- bun は `.npmrc` の `min-release-age` も読まない（[oven-sh/bun#22679](https://github.com/oven-sh/bun/issues/22679)）。`save-exact` もプロジェクトローカルに `.npmrc` が無いとホーム側へフォールバックしない（[oven-sh/bun#22971](https://github.com/oven-sh/bun/issues/22971)）ため、`.bunfig.toml` の `exact = true` で代替している。

### pnpm の config を XDG に寄せる

pnpm は macOS 既定では `~/Library/Preferences/pnpm/config.yaml` を見るが、`XDG_CONFIG_HOME` を尊重する。fish の `config.fish`（mise 活性化より前）で `XDG_CONFIG_HOME=~/.config` を設定し、`~/.config/pnpm/config.yaml` を正としている。dotfiles は `~/.config` が `dotfiles/.config` への dir symlink なので、ファイルを置くだけで反映され個別 symlink は要らない。

XDG を設定しても影響範囲は限定的で、`~/Library/Preferences` 配下にある他の Node CLI の設定は env-paths 製で XDG を無視するため動かない。

## 層2: 依存ライフサイクルスクリプト（postinstall）

汚染依存の postinstall 等が install 中に env を読んで token を持ち出すベクタ。**既定挙動が PM で違う**:

| PM | 依存のスクリプトを既定実行するか | 無効化 / allowlist |
|----|----|----|
| npm | **する** | `ignore-scripts` のみ（allowlist 無しの全停止） |
| yarn 1 (classic) | **する** | `--ignore-scripts` |
| bun | しない | `trustedDependencies` |
| pnpm 10+ | しない（11 は既定でビルド要承認） | `onlyBuiltDependencies` / `approve-builds` |

bun と pnpm 10+ は safe-by-default なので、**穴は npm と yarn-classic に限られる**。

**グローバルな `ignore-scripts` は不採用（YAGNI）**。層1が「汚染版を掴む確率」を先に潰しており、注入される秘匿情報は registry token 1 件（rotate 可能。provider 認証 token は env に載せていない）で blast radius が小さい。対して npm の `ignore-scripts` は allowlist を持たない全停止で、自プロジェクトの prepare や native module のビルドまで止めてサイレント失敗を招く。摩擦が便益を上回ると判断した。

運用レバーとして、高リスクな単発 install は手動で `--ignore-scripts` を付けて必要分だけ `npm rebuild` し、素性の分からない package は bun / pnpm を優先する。

## 層3: proxy registry（Takumi Guard）

既定 registry にセキュリティプロキシを据え、汚染版が手元へ届く前に弾く層。本リポジトリは `npm.flatt.tech`（Takumi Guard、旧 Shisho Guard, by GMO）を既定 registry にしている。npmjs を代理する**公開 read-only のセキュリティプロキシ**で、ブロックリスト該当の悪性 package を**コードが手元へ到達する前に 403 で拒否**する。社内 / private registry ではない。

token は任意だが rate limit が変わる（匿名 2,000 req/min/IP・ブロックのみ ／ 個人 `tg_anon_` 10,000 req/min/token ＋ download 追跡と breach 通知 ／ `tg_org_` 10,000 req/10s/token・有料 org。超過は 429）。**マシングローバルに個人 `tg_anon_` token** を使う。目的は rate 緩和と追跡であって、アクセス制御ではない。ORG token は不使用で、使うなら repo 単位の `.npmrc` と repo 単位の token 運用に切る。token の実体は disk に置かず実行時に注入する（[docs/fnox-token-management.md](./fnox-token-management.md)）。

出典: <https://shisho.dev/docs/ja/t/guard/>、rate limit は <https://shisho.dev/docs/ja/t/guard/limitation>

プロキシを通るのは**プロジェクト依存の install** で、pnpm / yarn と mise 経由の npm 本体は非 FLATT backend（aqua / github 等）のため公開 `registry.npmjs.org` へ直接当たる。この非対称は sandbox の egress 許可にも影響する（[docs/claude-code-security.md](./claude-code-security.md)）。

## 層4: 実行物を固定版で持つ

`bunx -y <pkg>@latest` の形で hook や statusLine を書くと、**起動のたびに最新版を取りに行く**。即時拡散型の攻撃が進行している最中はその都度侵害版を掴む経路になり、しかも同じ呼び出しが複数の hook に散らばって攻撃面が広がりやすい。

対処は固定版のグローバル install に寄せ、コマンドは PATH 経由の名前で書くこと。更新は `bun update -g <pkg>` で行う（層1の保持期間が効く）。

## 関連

- [docs/claude-code-security.md](./claude-code-security.md): Claude Code の sandbox / permission（egress 許可、`env` ダンプと publish の承認）
- [docs/fnox-token-management.md](./fnox-token-management.md): registry token を disk に置かず注入する仕組み
- `dotfiles/.npmrc` / `dotfiles/.bunfig.toml` / `dotfiles/.config/pnpm/config.yaml`: 設定の実体
