# dotfiles

# Memo

*ルートにシンボリックリンク張りたくないファイル*は`install.sh`で除外指定します。

*git で管理したくないファイル*は`.gitignore`で指定します。

# Usage

## シンボリックリンクをルートに張る

`dotfiles`の中にある`.hoge`類のファイルをもとにルートにシンボリックリンクを張る。

```
cd ~/
git clone https://github.com/1natsu172/dotfiles.git
cd dotfiles
sh install.sh
```

## Homebrew

1. まずインストールする

- [https://brew.sh/index_ja.html](https://brew.sh/index_ja.html)

2. masを使うときにログイン状態でないといけないのでMac App Storeに手動でログインしておく

3. Homebrew bundle で Brewfile から dependencies のインストール

- [Homebrew-bundle](https://github.com/Homebrew/homebrew-bundle)

`cask`も`Homebrew bundle`も今はデフォルトで Homebrew に含まれてるはず

`Brewfile`がある場所で以下コマンド(大抵ルートディレクトリなはず)

```
brew bundle
```

なお Brewfile 再生成は以下でできる

```
brew bundle dump --force
```

## MacOSXの設定

1. 設定 > セキュリティとプライバシー > プライバシー > フルディスクアクセス > ターミナルを許可する
2. `sh ./.setup_osx_defaults` スクリプトを走らせる
3. 再起動する

## 手動でやるリスト

* デスクトップとDock > デフォルトのWebブラウザ
* 壁紙 => 変える
* デスクトップとDock > Mission Control > ショートカット（最下部）> キーボードショートカットとマウスショートカット => `Mission Control`を割り当てを "なし" にする
* ロック画面
  * 使用していない場合はディスプレイをオフにする => 任意の時間に設定する（推奨は5分後）
  * スクリーンセーバの開始後またはディスプレイがオフになったあとにパスワードを要求 => 任意の時間に設定する（推奨は5秒後）
* プライバシーとセキュリティ => FileVault有効化
* ネットワーク => ファイアウォール有効化
* SiriとSpotlight > Spotlightのプライバシー => 除外項目に外付けHDDとTimeMachine指定
* ディスプレイ => 解像度を`スペースを拡大`
* キーボード
  * キーボードショートカット…
    * 修飾キー => `Caps Lock` を `^Control` に
    * Spotlight => Spotlight検索を表示をオフ
    * 入力ソース => 前の入力ソースを表示をオフ
  * テキスト入力 > 入力ソース > 編集… => google-imeの`ひらがな`・`英数`を追加
* ~電源アダプタ > ディスプレイがオフのときにコンピュータを自動でスリープさせない > checked~
* アクセシビリティ
  * ズーム機能
    * スクロールジェスチャと修飾キーを使ってズーム => checked
    * スクロースジェスチャの修飾キー => `⌥ Option` キーにする
* Google-Japanese-IME
  * 環境設定 > 一般 > 基本設定 > スペースの入力 > `半角`

## シェルのデフォルトを変更する

### zsh にするなら

- [[MacOSX]ターミナルのデフォルト Shell を zsh に変更する方法 &middot; DQNEO 起業日記](http://dqn.sakusakutto.jp/2014/05/macosx_shell_chsh_zsh.html)

```
# /etc/shells の末尾に /usr/local/bin/zsh を追記します。
sudo sh -c 'echo $(which zsh) >> /etc/shells'

# ユーザのデフォルトシェルを変更します。
chsh -s /usr/local/bin/zsh
```

### fish にするなら

```
# /etc/shells の末尾に /usr/local/bin/fish を追記します。
sudo sh -c 'echo $(which fish) >> /etc/shells'

# ユーザのデフォルトシェルをfishに変更
sudo sh -c 'echo $(which fish)' | chsh -s

# fish-ssh-agentに`.ssh/environment`を求められるがないのでつくる
cd ~; mkdir .ssh; touch .ssh/environment; ssh-agent > .ssh/environment;
```

#### fisher のセットアップ

ref: https://github.com/jorgebucaran/fisher#using-your-fish_plugins-file

```
# .config/fish/fish_plugins を利用して fisher install を回してくれる
fisher update
```

## Homebrew の対象ディレクトリが Path 優先順位負けするので最優先にする

[Homebrew コマンドが優先的に実行されるようにデフォルトパスを追加する](https://qiita.com/n-oshiro/items/3c571a4fcdb023b1fe77)

- `/etc/paths`の内容を変える
  - `$(brew --prefix)/bin` して出るパスが Homebrew のアプリケーションディレクトリ、なのでこれを一番上へ追記

```
sudo vi /etc/paths
```

```/etc/paths
# $(brew --prefix)/binの出力結果を書く
/usr/local/bin
/usr/bin
/bin
/usr/sbin
/sbin
```

```
# 反映(シェル再起動)
exec $SHELL
``` 

## asdf で NodeJS 環境構築したりする

[しましょう](https://asdf-vm.com/#/core-manage-asdf-vm)

```
asdf plugin add nodejs
asdf install nodejs latest
asdf list nodejs
asdf global nodejs latest
```

## Git アカウントの設定

### メインアカウント設定

リポジトリは https 形式で clone するようにして、認証キーは`credential-osxkeychain`で管理するようにする。

- [Caching your GitHub password in Git](https://help.github.com/articles/caching-your-github-password-in-git/)

マルチアカウントのために global の`.gitconfig`の`[user]`欄を空けているので、direnv でホームディレクトリに`.envrc`を作ってそこへメインアカウントの情報を入れる。

- [direnv を使って複数の git コミッタ名を切り替える](http://blog.manaten.net/entry/direnv_git_account)

```
# 環境変数切り替えたいディレクトリに移動
cd ~

# .envrcを作成
direnv edit .
```

`.envrc`に以下のようにユーザー情報を書く

```
export GIT_COMMITTER_NAME="YOUR NAME"
export GIT_COMMITTER_EMAIL="mail@example.com"
export GIT_AUTHOR_NAME="YOUR NAME"
export GIT_AUTHOR_EMAIL="mail@example.com"
```

これで OS ログインユーザーのメインアカウントの設定が完了

### サブアカウント設定

サブアカウント用のディレクトリを切って、そこ以下での git の環境変数を direnv で制御することでサブアカウント実現をする。

例：

```
mkdir ~/dev_folder/sub_account
cd ~/dev_folder/sub_account
direnv edit .
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

- [Mac の環境構築自動化 2016 年 10 月版](http://jnst.hateblo.jp/entry/2016/09/30/051636)
