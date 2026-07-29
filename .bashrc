. "$HOME/.cargo/env"
eval "$(/opt/homebrew/bin/brew shellenv bash)"
eval "$(mise activate bash)"

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --bash)"

[ -r "$HOME/dotfiles/bin/fnox-wrappers.sh" ] && . "$HOME/dotfiles/bin/fnox-wrappers.sh"
