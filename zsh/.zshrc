PROMPT='%F{cyan}%n@%m%f:%F{magenta}%~%f%# '

vf() {
    local file
    file=$(fzf) || return

    nvim "$file"
    cd -- "$(dirname -- "$file")"
}

export PATH="$HOME/.local/bin:$PATH"

# Host-specific settings (toolchain paths, machine-local env).
# Not tracked in the dotfiles repo.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
