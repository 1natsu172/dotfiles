#--------------------------------------
# ref: fish-add-path
#   https://zenn.dev/estra/articles/zenn-fish-add-path-final-answer
#--------------------------------------

# Theme colors (Dracula-like)
#-----------------------------------------------------------------------------
set -g fish_color_autosuggestion 6272A4
set -g fish_color_cancel -r
set -g fish_color_command cyan
set -g fish_color_comment 6272A4
set -g fish_color_cwd green
set -g fish_color_cwd_root red
set -g fish_color_end 50FA7B
set -g fish_color_error FFB86C
set -g fish_color_escape bryellow --bold
set -g fish_color_history_current --bold
set -g fish_color_host normal
set -g fish_color_host_remote yellow
set -g fish_color_match --background=brblue
set -g fish_color_normal normal
set -g fish_color_operator bryellow
set -g fish_color_param FF79C6
set -g fish_color_quote F1FA8C
set -g fish_color_redirection 8BE9FD
set -g fish_color_search_match bryellow --background=brblack
set -g fish_color_selection white --bold --background=brblack
set -g fish_color_status red
set -g fish_color_user brgreen
set -g fish_color_valid_path --underline

# Pager colors
set -g fish_pager_color_completion
set -g fish_pager_color_description B3A06D yellow
set -g fish_pager_color_prefix white --bold --underline
set -g fish_pager_color_progress brwhite --background=cyan
set -g fish_pager_color_selected_background -r

# Key bindings
set -g fish_key_bindings fish_default_key_bindings

# Other settings
set -gx LSCOLORS gxfxcxdxbxegedabagacad

# sbin path (Homebrew's warning countermeasure)
#-----------------------------------------------------------------------------
fish_add_path /opt/homebrew/sbin

# dotfiles bin utilities
#-----------------------------------------------------------------------------
fish_add_path $HOME/dotfiles/bin

# mise-en-place
#-----------------------------------------------------------------------------
# IDE integration: https://mise.jdx.dev/ide-integration.html
if test "$VSCODE_RESOLVING_ENVIRONMENT" = 1
    mise activate fish --shims | source
else if status is-interactive
    mise activate fish | source
else
    mise activate fish --shims | source
end

# Workaround for simple-git-hooks :\ https://github.com/toplenboren/simple-git-hooks/blob/0433a0485ea8f2c83e37b7cf7f2ec11e26921887/README.md#i-am-getting-npx-command-not-found-error-in-a-gui-git-client
set -gx SIMPLE_GIT_HOOKS_RC "$HOME/.config/fish/functions/__my_scripts/.simple-git-hook.rc"

# goose
#-----------------------------------------------------------------------------
fish_add_path $HOME/.local/bin

# aqua
#-----------------------------------------------------------------------------
fish_add_path (aqua root-dir)/bin

# GnuPG2 env
#-----------------------------------------------------------------------------
set -gx GPG_TTY (tty)

# fisher jethrokuan/fzf
#-----------------------------------------------------------------------------
set -gx FZF_LEGACY_KEYBINDINGS 0

# alias
#-----------------------------------------------------------------------------
alias g='git'
alias gst='g status'
alias gsts='g status -sb'
alias gbr='g branch'
alias gbrv='g branch -vv'
alias gbrvc='g branch --list (git branch --show-current) -vv'
alias gbrd='g branch -d'
alias gbrdf='g branch -D'
alias gbrdmerged='git_delete_merged_local_branch'
alias gcom='g checkout (git symbolic-ref refs/remotes/origin/HEAD --short | xargs basename) && g pull'
alias gcod='g checkout develop'
alias gpush='g push'
alias gpuu='g push -u origin (git rev-parse --abbrev-ref HEAD)'
alias gstash='g stash -u'
alias gpop='g stash pop'
alias gpull='g pull'
alias gremov='g remote -v'
alias glog='g log'
alias glogo='g log --oneline'
alias glogoo='g log --oneline HEAD --not origin/(git symbolic-ref refs/remotes/origin/HEAD --short | xargs basename)'
alias glogor='g log @{upstream} --oneline'
alias gdiffo='g diff origin/(git symbolic-ref refs/remotes/origin/HEAD --short | xargs basename)...HEAD'
alias grepow='gh repo view --web --branch=(git rev-parse --short HEAD)'
alias gwt='g worktree'

## eza
#-----------------------------------------------------------------------------
if type -q eza
    alias e='eza --icons --git'
    alias ls=e
    alias ea='eza -a --icons --git'
    alias la=ea
    alias ee='eza -aahl --icons --git'
    alias ll=ee
    alias et='eza -T -L 3 -a -I "node_modules|.git|.cache" --icons'
    alias lt=et
    alias eta='eza -T -a -I "node_modules|.git|.cache" --color=always --icons | less -r'
    alias lta=eta
end

## corepack
#-----------------------------------------------------------------------------
## Util aliases. This is to treat it as if it were a global installation while passing through corepack.
### Managemant via corepack through the meta-command. - https://github.com/nodejs/corepack/tree/cae770694e62f15fed33dd8023649d77d96023c1#corepack-binary-nameversion--args
## After node 25, need switch to global instralled corepack via mise. (https://mise.jdx.dev/dev-tools/backends/npm.html)
alias yarn="corepack yarn"
alias yarnpkg="corepack yarnpkg"
alias pnpm="corepack pnpm"
alias pnpx="corepack pnpx"
alias npm="corepack npm"
alias npx="corepack npx"

## bun global
#-----------------------------------------------------------------------------
fish_add_path $HOME/.bun/bin

# set $BROWSER
#-----------------------------------------------------------------------------
set -gx BROWSER open

# VSCode or Cursor
#-----------------------------------------------------------------------------
if set -q CURSOR_TRACE_ID
    alias code="cursor"
end

# set $EDITOR
#-----------------------------------------------------------------------------
set -gx EDITOR code
set -gx VISUAL code

# Android
#-----------------------------------------------------------------------------
set -gx ANDROID_HOME $HOME/Library/Android/sdk
fish_add_path $ANDROID_HOME/emulator
fish_add_path $ANDROID_HOME/tools
fish_add_path $ANDROID_HOME/tools/bin
fish_add_path $ANDROID_HOME/platform-tools

# jdk
#-----------------------------------------------------------------------------
set -gx JAVA_HOME (/usr/libexec/java_home)

# cargo
#-----------------------------------------------------------------------------
# NOTE: rustup.fish で設定している

# go lang
#-----------------------------------------------------------------------------
set -gx GOPATH $HOME/go
fish_add_path $GOPATH/bin

# starship prompt
#-----------------------------------------------------------------------------
starship init fish | source
# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :

# 1password CLI
#-----------------------------------------------------------------------------
op completion fish | source

# zoxide
#-----------------------------------------------------------------------------
zoxide init fish --cmd j | source
