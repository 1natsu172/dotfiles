# dotfiles

## Usage

### シンボリックリンクをルートに張る

```
$ cd ~/
$ git clone https://github.com/1natsu172/dotfiles.git
$ cd dotfiles
$ sh install.sh
```
### Homebrew
1. まずインストールする

* [https://brew.sh/index_ja.html](https://brew.sh/index_ja.html)

2. Homebrew bundleでBrewfileからdependenciesのインストール

* [Homebrew-bundle](https://github.com/Homebrew/homebrew-bundle)

`cask`も`Homebrew bundle`も今はデフォルトでHomebrewに含まれてるはず

`Brewfile`がある場所で以下コマンド(大抵ルートディレクトリなはず)

```
$ brew bundle
```


### シェルのデフォルトをzshにする

* [[MacOSX]ターミナルのデフォルトShellをzshに変更する方法 &middot; DQNEO起業日記](http://dqn.sakusakutto.jp/2014/05/macosx_shell_chsh_zsh.html)

```
# /etc/shells の末尾に /usr/local/bin/zsh を追記します。
sudo sh -c 'echo $(which zsh) >> /etc/shells'

# ユーザのデフォルトシェルを変更します。
chsh -s /usr/local/bin/zsh
```
### Homebrewの対象ディレクトリがPath優先順位負けするので最優先にする

[Homebrew コマンドが優先的に実行されるようにデフォルトパスに/usr/local/binを追加する](https://qiita.com/n-oshiro/items/3c571a4fcdb023b1fe77)

* `/etc/paths`の内容を変える
  * `/usr/local/bin`がHomebrewのアプリケーションディレクトリ、なので一番上へ

```
$ sudo vi /etc/paths
```

```/etc/paths
/usr/local/bin
/usr/bin
/bin
/usr/sbin
/sbin
```

$ exec $SHELLで反映(シェル再起動)


### nodebrewでnode.jsのインスコしたりrubyの環境構築したりする

しましょう

### 参考

* [Macの環境構築自動化 2016年10月版](http://jnst.hateblo.jp/entry/2016/09/30/051636)
