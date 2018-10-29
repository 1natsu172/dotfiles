function fish_user_key_bindings
    fzf_key_bindings
    ### Bash Style Command ###
    # https://github.com/fish-shell/fish-shell/wiki/Bash-Style-Command-Substitution-and-Chaining-(!!-!%24-&&-%7C%7C)
    bind ! bind_bang
    bind '$' bind_dollar
    ### Bash Style Command ###

    ### fish-ghqのctrl+gのショートカットがfisherman3.0からfzfとコンフリクトするようになったので応急処置(conf.d/fish-ghq_key_bindings.fishの中身をコピペ) ###
    bind \cg '__ghq_crtl_g'
    if bind -M insert >/dev/null ^/dev/null
        bind -M insert \cg '__ghq_crtl_g'
    end
    ### fish-ghq ###
end
