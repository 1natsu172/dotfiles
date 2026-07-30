# herdr のセッション寿命とシェル設定の反映

## 前提

herdr は tmux と同じ server / client 構成。`herdr server` は PPID 1（launchd 直下）に daemonize され、**client の detach（`prefix+q`）でも Ghostty の `cmd+q` でも終了しない**。

各ペインのシェルは server の子プロセス。detach 後に再度 `herdr` を打ったときに現れる「ワークスペースとパネルの復元」は、保存レイアウトからの再構築ではなく **生存し続けているシェルプロセスへの再 attach**。再 attach ではシェルが起動し直されないため、config.fish を書き換えてもそのペインは起動時に読んだ内容のまま動き続ける。

さらに、ペインは server の子として起動するため、**herdr 内で新しくペインを作っても server の起動時に確定した環境変数を継承する**。config.fish の `brew shellenv` と `mise activate` はその継承値に prepend するので、削除したはずの PATH エントリが残り、既存エントリは二重化する。

## 症状

config.fish から `set -gx` や PATH エントリを削除しても、herdr のペインでは消えない。herdr を経由しない Ghostty の新規タブでは正しく消えている。この非対称が出たらこの問題。

## 対処

```sh
herdr server stop
```

を実行したうえで、**herdr を経由していないシェル**（ターミナルの新規タブなど）から `herdr` を起動し直す。server の環境が現在の設定で作り直され、以降のペインすべてに反映される。

シェル設定を変更したら、この手順を踏むまで反映されないと考えること。

マシンの再起動はこの手順を兼ねる。herdr は LaunchAgent を登録しないため再起動後に自動復帰せず、次に `herdr` を起動した時点で server が作り直される。ワークスペースとパネルは `session.json` から復元されるが、復元されるのはレイアウトと各ペインの cwd だけで、シェルは起動し直されるため環境は新しくなる。

## 落とし穴

- **`exec fish` では直らない。** config.fish は再読み込みされるが、`exec` は自プロセスの環境変数をそのまま引き継ぐため、削除した exported 変数も PATH の残骸・重複も残る。環境を作り直すには server の再起動が必要。
- **herdr のペイン内から `herdr` を起動し直しても直らない。** 古い環境を継承した状態で新しい server が立ち上がる。必ず herdr 外のシェルから起動する。
- **`herdr server reload-config` は無関係。** config.toml のリロード専用で、環境変数には触らない。
- **`herdr server stop` は配下の全プロセスを終了させる。** 実行中の agent やコマンドは落ちるため、作業を畳んでから実行する。

## 診断

server の起動時刻を見れば、いつの環境を掴んでいるかが分かる。

```fish
ps -eo pid,ppid,lstart,command | grep '[h]erdr'
```

PATH の重複と、実体が存在しないエントリを洗う。

```fish
string join \n $PATH | sort | uniq -d
for p in $PATH; test -d $p; or echo "missing: $p"; end
```

**重複や見慣れないエントリを見つけても、それだけで継承の残骸と判断しないこと。** 環境変数を落としたクリーンな login fish と突き合わせる。

```fish
/usr/bin/env -i HOME=$HOME TERM=xterm USER=$USER fish -l -c 'string join \n $PATH'
```

ここに出るものは現行の設定が出力しているもので、server を再起動しても消えない。conf.d 配下や各ツールの activate が追加するパスがこれに当たる。herdr のペインにだけ出るものが継承の残骸。
