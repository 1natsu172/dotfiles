# herdr のセッション寿命とシェル設定の反映

## 前提

herdr は tmux と同じ server / client 構成です。`herdr server` は PPID 1（launchd 直下）に daemonize され、**client の detach（`prefix+q`）でも Ghostty の `cmd+q` でも終了しません**。

各ペインのシェルは server の子プロセスです。detach 後に再度 `herdr` を打ったときに現れる「ワークスペースとパネルの復元」は、保存レイアウトからの再構築ではなく **生存し続けているシェルプロセスへの再 attach** です。再 attach ではシェルが起動し直されないため、config.fish を書き換えてもそのペインは起動時に読んだ内容のまま動き続けます。

さらに、ペインは server の子として起動するため、**herdr 内で新しくペインを作っても server の起動時に確定した環境変数を継承します**。config.fish の `brew shellenv` と `mise activate` はその継承値に prepend するので、削除したはずの PATH エントリが残り、既存エントリは二重化します。

## 症状

config.fish から `set -gx` や PATH エントリを削除しても、herdr のペインでは消えません。herdr を経由しない Ghostty の新規タブでは正しく消えています。この非対称が出たらこの問題です。

## 対処

```sh
herdr server stop
```

を実行したうえで、**herdr を経由していないシェル**（ターミナルの新規タブなど）から `herdr` を起動し直します。server の環境が現在の設定で作り直され、以降のペインすべてに反映されます。

シェル設定を変更したら、この手順を踏むまで反映されないと考えてください。

## 落とし穴

- **`exec fish` では直りません。** config.fish は再読み込みされますが、`exec` は自プロセスの環境変数をそのまま引き継ぐため、削除した exported 変数も PATH の残骸・重複も残ります。環境を作り直すには server の再起動が必要です。
- **herdr のペイン内から `herdr` を起動し直しても直りません。** 古い環境を継承した状態で新しい server が立ち上がります。必ず herdr 外のシェルから起動してください。
- **`herdr server reload-config` は無関係です。** config.toml のリロード専用で、環境変数には触りません。
- **`herdr server stop` は配下の全プロセスを終了させます。** 実行中の agent やコマンドは落ちるため、作業を畳んでから実行してください。

## 診断

server の起動時刻を見れば、いつの環境を掴んでいるかが分かります。

```fish
ps -eo pid,ppid,lstart,command | grep '[h]erdr'
```

PATH の重複と、実体が存在しないエントリを洗います。

```fish
string join \n $PATH | sort | uniq -d
for p in $PATH; test -d $p; or echo "missing: $p"; end
```

**重複や見慣れないエントリを見つけても、それだけで継承の残骸と判断しないでください。** 環境変数を落としたクリーンな login fish と突き合わせます。

```fish
/usr/bin/env -i HOME=$HOME TERM=xterm USER=$USER fish -l -c 'string join \n $PATH'
```

ここに出るものは現行の設定が出力しているもので、server を再起動しても消えません。conf.d 配下や各ツールの activate が追加するパスがこれに当たります。herdr のペインにだけ出るものが継承の残骸です。
