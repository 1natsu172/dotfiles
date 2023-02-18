# Change fish colors
set fish_color_command cyan
set -x LSCOLORS gxfxcxdxbxegedabagacad

# sbin path (Homebrew's warning countermeasure)
set -g fish_user_paths "/usr/local/sbin" $fish_user_paths

# rbenv
#set -x PATH $HOME/.rbenv/bin $PATH
#status --is-interactive; and source (rbenv init -|psub)

# yarn
set -x PATH $HOME/.config/yarn/global/node_modules/.bin $PATH

# direnv hook
eval (direnv hook fish)

# hub
eval (hub alias -s)

# GnuPG2 env
set -x GPG_TTY (tty)

# fisher jethrokuan/fzf
set -x FZF_LEGACY_KEYBINDINGS 0

# alias
alias g='git'
alias gst='g status'
alias gsts='g status -sb'
alias gbr='g branch'
alias gbrv='g branch -vv'
alias gbrd='g branch -d'
alias gbrdmerged='git_delete_merged_local_branch'
alias gco='g checkout'
alias gcob='g checkout -b'
alias gcom='g checkout (git symbolic-ref refs/remotes/origin/HEAD --short | xargs basename)'
alias gcod='g checkout develop'
alias gpush='g push'
alias gpuu='g push -u origin HEAD'
alias gstash='g stash -u'
alias gpop='g stash pop'
alias gpull='g pull'
alias gremov='g remote -v'
alias glog='g log'
alias glogo='g log --oneline'
alias gpr='git push origin HEAD && hub compare (git symbolic-ref --short HEAD)'

# ## exa
if type -q exa
  alias e='exa --icons --git'
  alias ls=e
  alias ea='exa -a --icons --git'
  alias la=ea
  alias ee='exa -aahl --icons --git'
  alias ll=ee
  alias et='exa -T -L 3 -a -I "node_modules|.git|.cache" --icons'
  alias lt=et
  alias eta='exa -T -a -I "node_modules|.git|.cache" --color=always --icons | less -r'
  alias lta=eta
end

# set $BROWSER
set -x BROWSER open

# Android
set -x ANDROID_HOME $HOME/Library/Android/sdk
set -x PATH $ANDROID_HOME/emulator $PATH
set -x PATH $ANDROID_HOME/tools $PATH
set -x PATH $ANDROID_HOME/tools/bin $PATH
set -x PATH $ANDROID_HOME/platform-tools $PATH

# thefuck
thefuck --alias ask | source

# asdf
source (brew --prefix asdf)/libexec/asdf.fish

# jdk
set -x JAVA_HOME (/usr/libexec/java_home)

# cargo
set -g fish_user_paths $HOME/.cargo/bin $fish_user_paths

# corepack
## Util aliases. This is to treat it as if it were a global installation while passing through corepack.
### Managemant via corepack through the meta-command. - https://github.com/nodejs/corepack/tree/cae770694e62f15fed33dd8023649d77d96023c1#corepack-binary-nameversion--args
alias pnpm='corepack pnpm'
alias yarn='corepack yarn'
alias cleancache:corepack='rm -rf ~/.cache/node/corepack/' # Temp patch. reason doesn't exist such command currently…… - https://github.com/nodejs/corepack/issues/114

# starship prompt
starship init fish | source