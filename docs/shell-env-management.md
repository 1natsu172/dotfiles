# シェル環境（PATH / 環境変数）の管理

PATH の追加とシェルに依存しない環境変数は `.config/mise/config.toml` の `[env]` に書く。`_.path` が PATH、他のキーが環境変数になり、fish / zsh / bash のどれも `mise activate` で同じ値を受け取る。キーバインド・色・関数などシェル固有の設定は各シェルの rc に残す。

- `fish_add_path` は使わない。universal variable `fish_user_paths`（`fish_variables` に保存され、追跡対象外）に書くので config.fish と実際の値がずれ、fish から起動していないプロセスには伝わらない。存在しないディレクトリは黙って無視する
- 自分で PATH を出力する仕組みを持つツールはそれに任せ、`_.path` に並べない。Homebrew は `brew shellenv`、mise は自身の tool パス、Ghostty は自分で PATH に入れる
- `JAVA_HOME` `GOROOT` `GOBIN` は mise が設定するので、シェル側で上書きしない。shims だけでは設定されず `mise activate` が要る。`GOBIN` は mise の go の配下を指すので、Go の CLI は `[tools]` の `go:` backend で入れる

## 順序

- `brew shellenv <shell>` は `mise activate` より前に置く。`brew shellenv fish` は `/opt/homebrew/bin` を PATH の先頭へ移すので、後に置くと Homebrew の python3 が mise の python を隠す。`command -v python3` で確かめる
- `_.path` のエントリは mise の tool パスより前に入る。mise で管理しているツールと同名のバイナリを持つディレクトリを `_.path` に置かない。`mise env -s zsh` で確かめる

## brew shellenv

- シェル名（`zsh` / `bash` / `fish`）を必ず渡す。引数が無いと `$SHELL` で構文を決めるので、実行中のシェルと違えば別の構文が流れ込む
- zsh では `.zprofile` ではなく `.zshrc` に置く。`.zprofile` は login shell でしか読まれない。Homebrew のインストーラは `.zprofile` を案内してくるが従わない

## fish の mise は二重に activate されうる

Homebrew の mise は `/opt/homebrew/share/fish/vendor_conf.d/mise-activate.fish` を置き、config.fish より先に `mise activate fish` を実行する。config.fish 側で activate する必要は無く、IDE 向けに shims を足すときだけ書く。止めるなら `MISE_FISH_AUTO_ACTIVATE=0` を、ファイル名順で先に読まれる `conf.d/` のファイルに置く。

```fish
fish --profile-startup /tmp/p.log -lc true; grep -i mise /tmp/p.log
```

## 診断

環境変数を落とした login shell の PATH が、いまの設定が出力する PATH になる。ここに無いのにペインにだけあるものは、herdr などが引き継いだ古い値。

```fish
/usr/bin/env -i HOME=$HOME TERM=xterm USER=$USER fish -l -c 'string join \n $PATH'
string join \n $PATH | sort | uniq -d                    # 重複
for p in $PATH; test -d $p; or echo "missing: $p"; end   # 存在しないエントリ
```

- 設定から消したのに残るなら herdr を疑う（[herdr-session-lifecycle.md](./herdr-session-lifecycle.md)）
- universal variable は config.fish から消しても残る。`set -U --erase <name>` で消す
- Claude Code は起動時の shell snapshot を使うので、設定を変えたら再起動する
- `/usr/libexec/java_home` は sandbox 内では JVM を検出できず `Unable to locate a Java Runtime` を返す。sandbox 外で確かめる
