# Completions for gmergecheck command

function __gmergecheck_get_branches
    git branch --all --sort=-committerdate 2>/dev/null | string replace -r '^\s*[*+]?\s*' '' | string replace -r '^remotes/origin/' '' | string match -v 'HEAD*' | awk '!seen[$0]++'
end

# First argument: base branch (merge target)
complete -c gmergecheck -n __fish_use_subcommand -f -k -a "(__gmergecheck_get_branches)" -d "Base branch"

# Second argument: source branch (merge source)
complete -c gmergecheck -n "test (count (commandline -opc)) -eq 2" -f -k -a "(__gmergecheck_get_branches)" -d "Source branch"
