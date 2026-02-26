# Completions for gwta command

# Function to get clean branch names
function __gwta_get_branches
    git branch --all --sort=-committerdate 2>/dev/null | string replace -r '^\s*[*+]?\s*' '' | string replace -r '^remotes/origin/' '' | string match -v 'HEAD*' | awk '!seen[$0]++'
end

# Complete branch names for the first argument
complete -c gwta -n __fish_use_subcommand -f -k -a "(__gwta_get_branches)" -d "Git branch"

# Complete directory paths for the second argument
complete -c gwta -n "test (count (commandline -opc)) -eq 2" -xa "(__fish_complete_directories)" -d "Worktree path"
