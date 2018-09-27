# Change fish colors
set fish_color_command cyan

# sbin path (Homebrew's warning countermeasure)
set -x fish_user_paths "/usr/local/sbin" $fish_user_paths

# nodebrew
set -x PATH $HOME/.nodebrew/current/bin $PATH

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

# balias
balias g 'git'
