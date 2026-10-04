# サプライチェーン防御（npm / bun / pnpm）

想定する攻撃は Shai-Hulud 型の即時拡散で、経路は 3 つ。公開直後の汚染版を取り込む、postinstall が install 中に env の秘匿情報を持ち出す、侵害された環境から汚染版を publish して広がる。1 つの対策に頼らず、独立に効く層を重ねる。

Claude Code の sandbox / permission での補強は [claude-code-security.md](./claude-code-security.md)、token の注入は [fnox-token-management.md](./fnox-token-management.md) にある。

## 層 1: 公開直後の版を取り込まない

公開から 7 日経っていない版を取り込まないことで、汚染版が見つかって取り下げられるまでの時間を稼ぐ。主となる防御。

PM ごとに設定ファイル・キー名・単位がすべて違い、間違えてもエラーは出ずに防御だけが消える。

| PM | 設定ファイル | キー | 7 日 |
|----|------------|-----|---------|
| npm | `.npmrc` | `min-release-age` | `7`（日） |
| pnpm 10.16+ | `.npmrc` | `minimum-release-age` | `10080`（分） |
| pnpm 11+ | `.config/pnpm/config.yaml` | `minimumReleaseAge` | `10080`（分） |
| bun | `.config/.bunfig.toml` の `[install]` | `minimumReleaseAge` | `604800`（秒） |

- pnpm は npm の `min-release-age` を読まない。10.15 以前には機能自体が無い
- pnpm 11+ は `.npmrc` を一切読まず、`config.yaml`（camelCase）だけを見る。`saveExact: true` も `config.yaml` に書いておかないと厳密な版固定が黙って外れる
- pnpm は `XDG_CONFIG_HOME` を尊重する。`config.fish` で `XDG_CONFIG_HOME=~/.config` を設定しているので `~/.config/pnpm/config.yaml` が使われ、macOS 既定の `~/Library/Preferences/pnpm/` は使わない
- bun は `XDG_CONFIG_HOME` があると `$XDG_CONFIG_HOME/.bunfig.toml` だけを見て `~/.bunfig.toml` を読まない（[oven-sh/bun#30842](https://github.com/oven-sh/bun/issues/30842)）。`.config/.bunfig.toml` は `../.bunfig.toml` への symlink で、これを消すと bun の global 設定が黙って全部無効になる
- bun は `.npmrc` の `min-release-age` を読まず（[#22679](https://github.com/oven-sh/bun/issues/22679)）、`save-exact` も project に `.npmrc` が無いと home 側を見ない（[#22971](https://github.com/oven-sh/bun/issues/22971)）。`.bunfig.toml` の `exact = true` で代わりにしている

## 層 2: 依存の postinstall

| PM | 依存のスクリプトを既定で実行するか | 止め方 |
|----|----|----|
| npm | する | `ignore-scripts`（allowlist 無しの全停止） |
| yarn 1 | する | `--ignore-scripts` |
| bun | しない | `trustedDependencies` |
| pnpm 10+ | しない | `onlyBuiltDependencies` / `approve-builds` |

穴は npm と yarn 1 だけ。global の `ignore-scripts` は入れない。層 1 で汚染版を取り込む確率は既に下がっており、注入している秘匿情報は rotate できる registry token 1 件だけで被害の範囲が小さい。一方 `ignore-scripts` は自分の project の prepare や native module のビルドまで止め、黙って壊れる。

素性の分からない package は bun か pnpm で入れ、npm で危ないものを単発で入れるときは `--ignore-scripts` を付けて必要な分だけ `npm rebuild` する。

## 層 3: proxy registry（Takumi Guard）

既定の registry を `npm.flatt.tech`（Takumi Guard、旧 Shisho Guard）にしている。npmjs を代理する公開の read-only proxy で、ブロックリストに載った package を手元に届く前に 403 で拒否する。

- token は無くても使えるが、個人の `tg_anon_` token を使うと rate limit が緩み、download の追跡と侵害の通知を受けられる。アクセス制御のためではない。token は fnox で注入する
- 制限の詳細: <https://shisho.dev/docs/ja/t/guard/limitation>
- proxy を通るのは project の依存の install だけ。pnpm / yarn と mise が入れる npm 本体は aqua / github backend なので `registry.npmjs.org` に直接取りに行く。sandbox の `allowedDomains` に両方が要るのはこのため

## 層 4: 実行物の版を固定する

hook や statusLine を `bunx -y <pkg>@latest` で書くと、起動のたびに最新版を取りに行き、攻撃が進行中なら毎回侵害版を取り込む。global に固定版を入れて PATH の名前で呼び、更新は `bun update -g <pkg>` で行う（層 1 が効く）。`ccstatusline` はこの形にしている。
