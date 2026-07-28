# Brewfileのメンテナンスオペレーション

## 前提

Brewfile は**生成物**であり、状態の実体は各 formula の `INSTALL_RECEIPT.json`（Homebrew 内部の呼称は Tab）にあります。

`brew bundle dump` が formula を出力する条件は以下です。

```ruby
installed_on_request? || !installed_as_dependency?
```

つまり **Brewfile のテキストを消しても、レシートを直さない限り次の dump で必ず復活します**。剪定は必ずレシートの変更とセットで行ってください。

## 日常フロー

```sh
brew bundle dump --force
git diff Brewfile
```

差分が自分の意図通りなら commit。身に覚えのない行があれば下記へ。

## 身に覚えのない行が出たとき

用途に応じて実体側を修正し、再度 dump します。

| 状況 | コマンド |
| --- | --- |
| もう不要 | `brew uninstall <formula>` |
| 依存としては必要／実体は残す | `brew tab --no-installed-on-request <formula>` |

`brew tab` が編集できるのは `installed_on_request` のみです（`--installed-as-dependency` は存在しません）。これだけで `brew autoremove` の対象にはなりますが、`installed_as_dependency` が false のままだと上記の条件式が OR のため **dump には出続けます**。実体を残したまま Brewfile からも消したい場合は、入れ直しでフラグを両方正しくしてください。

```sh
brew uninstall --ignore-dependencies <formula>
brew install --as-dependency <formula>
```

```sh
brew bundle dump --force   # 修正が反映されたか確認
git diff Brewfile
```

レシートを直しているので収束します。同じ行を繰り返し消す作業にはなりません。

## アンインストール前の確認

`brew uses --installed` は既定で build / test / optional 依存を除外します。判断には以下を使ってください。

```sh
brew uses --installed --include-build --include-test --include-optional <formula>
brew uses --installed --cask <formula>
```

依存元が残っている場合 `brew uninstall` は拒否されるため、誤操作のリスクは低いです。実行後は `brew missing` で検証します。

## 新規マシンのセットアップ

```sh
brew bundle
```

`brew bundle cleanup` は不要です。Brewfile 外のものが存在しないため no-op になります。

## 定期メンテナンス

```sh
brew autoremove --dry-run
brew autoremove
```

`brew tab` で依存扱いに戻した formula は、依存元を削除した時点で孤児になります。`autoremove` はこれを回収します。`installed_on_request: true` のものは対象外なので、意図して入れたものが消えることはありません。

## 補助コマンド

| コマンド | 用途 |
| --- | --- |
| `brew leaves -r` | 手動インストールされた葉（誰からも依存されていないもの） |
| `brew leaves -p` | 依存として入った孤児。`brew autoremove` の対象 |
| `brew bundle list --brews` | Brewfile に記載されているエントリ |
| `brew install --as-dependency <formula>` | 最初から依存扱いで入れる。後から `brew tab` を叩く手間を省く |

## 落とし穴

- `brew bundle` は Brewfile の各行を明示インストールとして実行するため、`installed_on_request: true` が立ちます。一度混入した行は放置すると恒久的に残り、マシンを移すたびに複製されます。
- そのため **dump 後の `git diff` 確認を省略しない**ことが、この運用の唯一の防波堤です。
- `brew reinstall` や `brew upgrade` の中断でレシートの状態が変わる場合があります。覚えのない行が出たら、この可能性を疑ってください。
