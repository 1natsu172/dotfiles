# dotfiles

# Memo

*ルートにシンボリックリンク張りたくないファイル*は`install.sh`で除外指定します。

*gitで管理したくないファイル*は`.gitignore`で指定します。

# Usage

## シンボリックリンクをルートに張る

`dotfiles`の中にある`.hoge`類のファイルをもとにルートにシンボリックリンクを張る。

```
$ cd ~/
$ git clone https://github.com/1natsu172/dotfiles.git
$ cd dotfiles
$ sh install.sh
```
## Homebrew
1. まずインストールする

* [https://brew.sh/index_ja.html](https://brew.sh/index_ja.html)

2. Homebrew bundleでBrewfileからdependenciesのインストール

* [Homebrew-bundle](https://github.com/Homebrew/homebrew-bundle)

`cask`も`Homebrew bundle`も今はデフォルトでHomebrewに含まれてるはず

`Brewfile`がある場所で以下コマンド(大抵ルートディレクトリなはず)

```
$ brew bundle
```

なおBrewfile再生成は以下でできる

```
$ brew bundle dump --force
```

## シェルのデフォルトを変更する

### zshにするなら

* [[MacOSX]ターミナルのデフォルトShellをzshに変更する方法 &middot; DQNEO起業日記](http://dqn.sakusakutto.jp/2014/05/macosx_shell_chsh_zsh.html)

```
# /etc/shells の末尾に /usr/local/bin/zsh を追記します。
sudo sh -c 'echo $(which zsh) >> /etc/shells'

# ユーザのデフォルトシェルを変更します。
chsh -s /usr/local/bin/zsh
```

### fishにするなら

```
# /etc/shells の末尾に /usr/local/bin/fish を追記します。
sudo sh -c 'echo $(which fish) >> /etc/shells'

# ユーザのデフォルトシェルを変更します。
chsh -s /usr/local/bin/fish
```

## Homebrewの対象ディレクトリがPath優先順位負けするので最優先にする

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


## nodebrewでnode.jsのインスコしたりrubyの環境構築したりする

しましょう

## Gitアカウントの設定

### メインアカウント設定
リポジトリはhttps形式でcloneするようにして、認証キーは`credential-osxkeychain`で管理するようにする。

* [Caching your GitHub password in Git](https://help.github.com/articles/caching-your-github-password-in-git/)

マルチアカウントのためにglobalの`.gitconfig`の`[user]`欄を空けているので、direnvでホームディレクトリに`.envrc`を作ってそこへメインアカウントの情報を入れる。

* [direnvを使って複数のgitコミッタ名を切り替える](http://blog.manaten.net/entry/direnv_git_account)

```
# 環境変数切り替えたいディレクトリに移動
$ cd ~

# .envrcを作成
$ direnv edit .
```

`.envrc`に以下のようにユーザー情報を書く

```
export GIT_COMMITTER_NAME="YOUR NAME"
export GIT_COMMITTER_EMAIL="mail@example.com"
export GIT_AUTHOR_NAME="YOUR NAME"
export GIT_AUTHOR_EMAIL="mail@example.com"
```

これでOSログインユーザーのメインアカウントの設定が完了

### サブアカウント設定

サブアカウント用のディレクトリを切って、そこ以下でのgitの環境変数をdirenvで制御することでサブアカウント実現をする。

例：

```
$ mkdir ~/dev_folder/sub_ccount
$ cd ~/dev_folder/sub_ccount
$ direnv edit .
```

メインアカウントと同じく`.envrc`に以下のようにユーザー情報を書く

```
export GIT_COMMITTER_NAME="YOUR NAME"
export GIT_COMMITTER_EMAIL="mail@example.com"
export GIT_AUTHOR_NAME="YOUR NAME"
export GIT_AUTHOR_EMAIL="mail@example.com"
```

これで`~/dev_folder/sub_ccount`以下での作業はサブアカウントでの作業になる

## 参考

* [Macの環境構築自動化 2016年10月版](http://jnst.hateblo.jp/entry/2016/09/30/051636)
