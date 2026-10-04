# 認証トークンのコミット防止（gitleaks）

pre-commit で gitleaks が staged の差分を検査する（`lefthook.yml` の `secret-scan`）。dotfiles は公開リポジトリなので、追跡対象のファイルへ書き込まれた認証トークンを止める。

## 想定している書き込み

| 操作 | 書き込み先（追跡対象） | 書き込まれる形 |
| --- | --- | --- |
| `npm login` | `.npmrc`（`~/.npmrc` から symlink） | `//registry.npmjs.org/:_authToken=npm_…` |
| `pnpm login`（pnpm 12） | `.config/pnpm/config.yaml`（`~/.config/pnpm/` とハードリンク） | `_auth:` 配下の入れ子 YAML の `authToken: npm_…` |

npm login のトークンは 2 時間で失効するセッショントークンなので、管理せずに publish のたびに login し、書き込まれた行をコミットしない運用にしている。gitleaks はその取りこぼしを止める。

## 既定ルールで足りる

上の 2 形式は `npm-access-token`、`npm_` 接頭辞のない旧形式は `generic-api-key` で検出し、`${VAR}` の env 参照は検出しない（gitleaks 8.30.1 で確認）。そのため `.gitleaks.toml` は置いていない。

置くときは次の 2 点に注意する。

- `.gitleaks.toml` は既定設定に足されるのではなく、既定設定を置き換える。`[extend] useDefault = true` を書かないと既定ルールがすべて外れ、エラーも出ないまま何も検出しなくなる。
- install.sh が `.??*` を `$HOME` へ symlink するので、除外リストに足す。

誤検知を個別に黙らせるだけなら、`.gitleaks.toml` は要らない。その行に `gitleaks:allow` のコメントを付けるか、`.gitleaksignore` に fingerprint を書く。

## 検出されたとき

追記された行を消して stage し直す。`config.yaml` は `git checkout` で戻すとファイルが作り直されてハードリンクが切れるので、エディタで消す。
