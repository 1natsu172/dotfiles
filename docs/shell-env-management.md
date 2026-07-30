# シェル環境（PATH / 環境変数）の管理

## 前提

PATH の追加とシェル非依存の環境変数は `.config/mise/config.toml` の `[env]` が正本。`_.path` が PATH、それ以外のキーが環境変数になる。fish / zsh / bash のいずれも `mise activate` 経由で同じ値を受け取る。

`fish_add_path` は使わない。universal variable `fish_user_paths`（実体は `~/.config/fish/fish_variables`、追跡対象外）へ書き込むため config.fish の記述と実効値がずれ、fish 起点でないプロセスには伝わらない。

vendor が自前の env 出力インターフェースを持つものは vendor に任せ、`_.path` に列挙しない。Homebrew は `brew shellenv`、mise 自身は tool パス、Ghostty は自分で PATH に入れる。

キーバインド・色・シェル関数といったシェル固有の設定は各シェルの rc に残す。

## 順序の制約

`brew shellenv <shell>` は `mise activate` より**前**に置く。`brew shellenv fish` は `fish_add_path --global --move --path` で `/opt/homebrew/bin` を先頭へ移すため、後に置くと Homebrew の python3 が mise 管理の python を隠す。

```fish
command -v python3
```

`_.path` のエントリは mise の tool パスより前に入る。mise 管理ツールと同名のバイナリを持つディレクトリを `_.path` に置かないこと。

```sh
mise env -s zsh
```

## brew shellenv

シェル名を明示的に渡す（`zsh` / `bash` / `fish`）。引数なしの `brew shellenv` は `$SHELL` を見て出力構文を決めるため、`$SHELL` と実行中のシェルが一致しないと別シェルの構文が流れ込む。

zsh は `.zprofile` ではなく `.zshrc` に置く。`.zprofile` は login shell でしか読まれず、非ログインの zsh に届かない。Homebrew のインストーラが表示する「Next steps」は `$SHELL` から配布先を決めるため、macOS では `.zprofile` を案内してくる。

## fish では mise が二重に activate されうる

Homebrew の mise formula が `/opt/homebrew/share/fish/vendor_conf.d/mise-activate.fish` を配置する。これは config.fish より先に読まれ、`mise activate fish`（hook-env）を無条件で実行する。

したがって config.fish 側で hook-env を呼ぶ必要はない。IDE 向けに shims を足す場合だけ activate する。

無効化する場合は `MISE_FISH_AUTO_ACTIVATE=0` を vendor conf.d より先に読ませる（`conf.d/` にファイル名順で先行する名前で置く）。

```fish
fish --profile-startup /tmp/p.log -lc true; grep -i mise /tmp/p.log
```

## mise が設定する環境変数

`JAVA_HOME` / `GOROOT` / `GOBIN` は mise が設定する。シェル側で上書きしないこと。

これらは `mise activate` が必要で、shims だけでは設定されない。

`GOBIN` が mise の go install 配下を指すため、`go install` の出力は `~/go/bin` に入らない。Go の CLI ツールは `[tools]` の `go:` backend で管理する（`.default-go-packages` は非推奨）。

```sh
mise env -s zsh
```

## 診断

クリーンな login shell と突き合わせる。ここに出るものは現行の設定が出力しているもので、継承の残骸ではない。

```fish
/usr/bin/env -i HOME=$HOME TERM=xterm USER=$USER fish -l -c 'string join \n $PATH'
```

重複と実体のないエントリを洗う。

```fish
string join \n $PATH | sort | uniq -d
for p in $PATH; test -d $p; or echo "missing: $p"; end
```

## 落とし穴

- **設定を消したのに残る場合は herdr を疑う。** [herdr-session-lifecycle.md](./herdr-session-lifecycle.md) の手順を踏むまで反映されない
- **Claude Code は起動時の shell snapshot を使う。** 設定を変えたら Claude Code の再起動が要る
- **`/usr/libexec/java_home` は sandbox 内では JVM を1つも検出できない。** `Unable to locate a Java Runtime` を返すため、JVM の確認は sandbox 外で実行する
- **`fish_add_path` は存在しないディレクトリを黙って無視する。** 行が残っていても効いていないことがある
- **universal variable は config.fish から記述を消しても残る。** `set -U --erase <name>` で個別に消す
