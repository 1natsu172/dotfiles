# Created by newuser for 5.2

export GPG_TTY=$(tty)
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
eval "$(mise activate zsh)"

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)

[ -r "$HOME/dotfiles/bin/fnox-wrappers.sh" ] && . "$HOME/dotfiles/bin/fnox-wrappers.sh"
