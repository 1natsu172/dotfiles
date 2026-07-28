. "$HOME/.cargo/env"
eval "$(/opt/homebrew/bin/brew shellenv bash)"
eval "$(mise activate bash)"

[ -r "$HOME/dotfiles/bin/fnox-wrappers.sh" ] && . "$HOME/dotfiles/bin/fnox-wrappers.sh"
