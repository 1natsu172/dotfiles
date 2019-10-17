# Change fish colors
set fish_color_command cyan

# sbin path (Homebrew's warning countermeasure)
set -g fish_user_paths "/usr/local/sbin" $fish_user_paths

# rbenv
#set -x PATH $HOME/.rbenv/bin $PATH
status --is-interactive; and source (rbenv init -|psub)

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
alias gbv='g branch -vv'
alias gco='g checkout'
alias gcob='g checkout -b'
alias gcom='g checkout master'
alias gcod='g checkout develop'
alias gpuu='g push -u origin HEAD'
alias gbdmerged='git branch --merged $1  grep -vE "^*master$1"  xargs -I % git branch -d %'
alias gpr='git push origin HEAD && hub compare (git symbolic-ref --short HEAD)'

# set $BROWSER
set -x BROWSER open

# Android
set -x ANDROID_HOME $HOME/Library/Android/sdk
set -x PATH $ANDROID_HOME/emulator $PATH
set -x PATH $ANDROID_HOME/tools $PATH
set -x PATH $ANDROID_HOME/tools/bin $PATH
set -x PATH $ANDROID_HOME/platform-tools $PATH