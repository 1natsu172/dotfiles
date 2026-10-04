# herdr のセッション寿命とシェル設定の反映

herdr は tmux と同じ server / client 構成で、`herdr server` は launchd 直下に常駐する。client の detach（`prefix+q`）でも Ghostty の `cmd+q` でも server は終わらない。

- detach 後に `herdr` を打って戻るペインは、生き続けていたシェルへの再接続で、シェルは起動し直されない。config.fish を変えても、そのペインは起動時に読んだ設定のまま動く
- 新しいペインも server の子として起動し、server の起動時の環境変数を引き継ぐ。config.fish の `brew shellenv` と `mise activate` はそこへ追記するので、消したはずの PATH が残り、残ったエントリは重複する

config.fish から消した変数や PATH が herdr のペインにだけ残り、herdr を通さない Ghostty の新規タブでは消えているなら、これが原因。

## 対処

`herdr server stop` を実行し、herdr を通していないシェルから `herdr` を起動し直す。シェル設定を変えたら、これをするまで herdr には反映されない。

- `herdr server stop` は配下のプロセスをすべて終わらせる。実行中の agent やコマンドを片付けてから行う
- herdr のペインの中から起動し直すと、古い環境を引き継いだまま新しい server が立つ
- `exec fish` では直らない。config.fish は読み直すが、export 済みの変数と PATH はそのまま引き継ぐ
- `herdr server reload-config` は config.toml を読み直すだけで、環境変数には触らない
- マシンの再起動でも直る。herdr は LaunchAgent を持たないので、次に `herdr` を起動したとき server が作り直される。`session.json` から戻るのはレイアウトと各ペインの cwd だけで、シェルは新しく起動する

## 診断

server がいつ起動したかで、どの時点の環境を持っているか分かる。

```fish
ps -eo pid,ppid,lstart,command | grep '[h]erdr'
```

重複や見慣れないエントリがあっても、それだけで引き継いだ古い値とは判断しない。[shell-env-management.md](./shell-env-management.md) の「診断」でクリーンな login shell と比べ、herdr のペインにだけあるものが古い値。
