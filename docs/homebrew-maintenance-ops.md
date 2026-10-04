# Brewfile のメンテナンス

Brewfile は生成物で、状態の実体は各 formula の `INSTALL_RECEIPT.json` にある。`brew bundle dump` は次の条件に当たる formula を出力する。

```ruby
installed_on_request? || !installed_as_dependency?
```

したがって Brewfile の行を消しても、レシートを直さない限り次の dump で戻ってくる。行を消すときは必ずレシートも直す。

## 日常の流れ

```sh
brew bundle dump --force
git diff Brewfile
```

差分が意図どおりなら commit する。新しい formula を入れると、依存の一部が `installed_on_request` で入って Brewfile に出てくることがある。Homebrew の仕様で避けられないので、dump 後の `git diff` は省かない。`brew bundle` は Brewfile の各行を明示インストールとして扱うので、一度混ざった行はマシンを移るたびに複製される。

依存として入れると分かっているなら、最初から指定すれば後始末が要らない。

```sh
brew install --as-dependency <formula>
```

## 覚えのない行が出たとき

| 状況 | コマンド |
| --- | --- |
| もう要らない | `brew uninstall <formula>` |
| 依存としては要る | `brew tab --no-installed-on-request <formula>` |

`brew tab` が変えられるのは `installed_on_request` だけ。これで `brew autoremove` の対象にはなるが、`installed_as_dependency` が false のままだと上の条件の OR で dump には出続ける。Brewfile からも消すなら入れ直す。

```sh
brew uninstall --ignore-dependencies <formula>
brew install --as-dependency <formula>
brew bundle dump --force && git diff Brewfile
```

`brew reinstall` や `brew upgrade` が途中で止まるとレシートが変わることがある。覚えのない行はこれも疑う。

## アンインストール前の確認

`brew uses --installed` は既定で build / test / optional の依存を数えない。

```sh
brew uses --installed --include-build --include-test --include-optional <formula>
brew uses --installed --cask <formula>
```

依存元が残っていれば `brew uninstall` は拒否する。実行後は `brew missing` で確かめる。

## 新しいマシン

`brew bundle` だけでよい。Brewfile の外のものが無いので `brew bundle cleanup` は要らない。

## 定期メンテナンス

```sh
brew autoremove --dry-run
brew autoremove
```

`brew tab` で依存扱いに戻した formula は、依存元を消した時点で孤児になり `autoremove` が回収する。`installed_on_request: true` のものは対象外。

## 大規模な棚卸し

Brewfile が汚れた状態から立て直す手順。1 ステップずつ出力を確かめて進める。

```fish
brew list --installed-on-request | sort > /tmp/before.txt
cp /tmp/before.txt ~/keep.txt
```

`~/keep.txt` から使っていない行を消す。迷う行は残す。残す誤りはゴミが 1 つ残るだけだが、消す誤りは手戻りになる。

降格する対象を表示する。ここではまだ変えない。

```fish
set -g keep (string replace -r '.*/' '' < ~/keep.txt | string trim)
for f in (brew list --installed-on-request)
    contains -- $f $keep; or echo $f
end
```

出力が keep.txt から消した行と一致したら、`echo $f` を差し替えて実行する。

```fish
for f in (brew list --installed-on-request)
    contains -- $f $keep; or brew tab --no-installed-on-request $f
end

brew autoremove --dry-run
```

keep.txt にある formula が 1 つでも dry-run に出たら実行しない。

```fish
brew autoremove
brew missing
```

- keep リストを `brew leaves -r` から作らない。他から依存されていない formula しか出ないので、`fish`（`fisher` が依存）のように明示的に入れたが依存でもあるものが漏れ、降格される
- tap の formula は `user/tap/name` の形で出ることがあり、`contains` の完全一致が外れる。上の手順は両側を短い名前にそろえている
- 誤って降格したら `brew tab --installed-on-request` で戻せる。`autoremove` するまでは何も消えない。`brew tab` の出力は `is now marked` と `already marked` を区別するので、実際に変えたものだけ抜き出して戻せる

## 補助コマンド

| コマンド | 用途 |
| --- | --- |
| `brew list --installed-on-request` | Brewfile の元になる一覧 |
| `brew list --no-installed-on-request` | 依存として入ったもの |
| `brew leaves -p` | 依存として入った孤児。`autoremove` の対象 |
| `brew bundle list --formula` | Brewfile に書かれているもの |
