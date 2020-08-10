# Change fish colors
set fish_color_command cyan

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
alias gbr='g branch'
alias gbrv='g branch -vv'
alias gbrd='g branch -d'
alias gbrdmerged='git_delete_merged_local_branch'
alias gco='g checkout'
alias gcob='g checkout -b'
alias gcom='g checkout master'
alias gcod='g checkout develop'
alias gpush='g push'
alias gpuu='g push -u origin HEAD'
alias gstash='g stash -u'
alias gpop='g stash pop'
alias gpull='g pull'
alias gremov='g remote -v'
alias gpr='git push origin HEAD && hub compare (git symbolic-ref --short HEAD)'

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
source (brew --prefix asdf)/asdf.fish