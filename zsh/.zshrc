PROMPT='%F{cyan}%n@%m%f:%F{magenta}%~%f%# '

vf() {
    local file
    file=$(fzf) || return

    nvim "$file"
    cd -- "$(dirname -- "$file")"
}

export PATH="$HOME/.local/bin:$PATH"

# `help` is a bash builtin; zsh's equivalent is run-help, which ships aliased
# to `man`. Unalias it so it uses the per-builtin help files in $HELPDIR.
unalias run-help 2>/dev/null
autoload -Uz run-help
autoload -Uz run-help-git run-help-ip run-help-openssl run-help-sudo
alias help=run-help

# Host-specific settings (toolchain paths, machine-local env).
# Not tracked in the dotfiles repo.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
