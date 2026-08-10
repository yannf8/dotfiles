# dotfiles

Personal config for a Fedora 44 + **sway/Wayland** setup, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a *stow package* whose contents mirror `$HOME`. Stowing a
package symlinks its files into place.

## Packages

| Package | Installs to | What it is |
|---|---|---|
| `zsh` | `~/.zshrc`, `~/.zshenv` | Login shell. Custom prompt, `vf()` fzf→nvim helper. |
| `bash` | `~/.bashrc`, `~/.bash_profile`, `~/.profile` | Kept for TTY / non-login shells. |
| `git` | `~/.gitconfig` | Identity + `editor = nvim`. |
| `clangd` | `~/.clangd` | `-std=c++23`. |
| `nvim` | `~/.config/nvim/` | kickstart.nvim-derived config (gruvbox, relative numbers, 4-space tabs, clangd LSP). |
| `sway` | `~/.config/sway/` | Compositor config + `brightness-notify` / `volume-notify` scripts. |
| `waybar` | `~/.config/waybar/` | Status bar config + stylesheet. |
| `mako` | `~/.config/mako/config` | Notification daemon (Catppuccin Mocha). |
| `fuzzel` | `~/.config/fuzzel/fuzzel.ini` | Application launcher. |
| `alacritty` | `~/.config/alacritty/alacritty.toml` | Terminal. |
| `fastfetch` | `~/.config/fastfetch/config.jsonc` | System info readout. |
| `xdg` | `~/.config/mimeapps.list` | Default application handlers. |

## Bootstrap on a new machine

```bash
sudo dnf install stow git
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
stow -n -v */          # dry run first — check for conflicts
stow */                # then commit to it
```

If stow reports `WARNING: existing target`, the file already exists in `$HOME`.
Move or delete the original, then re-run. Avoid `--adopt` unless you know what it
does: it overwrites the *repo's* copy with whatever is in `$HOME`.

To remove a package: `stow -D <package>`. To re-link after editing: `stow -R <package>`.

## Host-specific values

Anything tied to one machine is kept **out** of this repo and sourced at runtime:

| File | Holds |
|---|---|
| `~/.config/sway/config.d/local` | Monitor layout (`output` lines) |
| `~/.zshrc.local` | Toolchain paths, e.g. `QSYS_ROOTDIR` |

`sway/config` ends with `include ~/.config/sway/config.d/*`, and `.zshrc` ends with
`[ -f ~/.zshrc.local ] && source ~/.zshrc.local`. Both are gitignored. On a new
machine, create them by hand — everything else works without them.

## Neovim

Derived from [nvim-lua/kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
(upstream `cfdc17b`), vendored as plain files rather than a submodule. Plugins are
managed by the built-in `vim.pack` and install to `~/.local/share/nvim/` — that
directory is *not* tracked. `nvim-pack-lock.json` **is** tracked (upstream gitignores
it; a personal fork should not) because it pins plugin versions.

To pull in upstream kickstart changes later, diff against the upstream `init.lua` by
hand — there is no merge path from here.

### Markdown / LaTeX PDF preview

`<leader>mp` in a markdown buffer (`lua/custom/plugins/markdown-pdf.lua`) renders the
file with pandoc + xelatex and opens it in a viewer that reloads on every `:w`. That
pipeline needs system packages Stow cannot provide:

```bash
sudo dnf install pandoc-cli texlive-xetex zathura zathura-pdf-mupdf \
  liberation-sans-fonts adwaita-mono-fonts
sudo dnf install texlive-framed texlive-upquote texlive-ulem texlive-soul \
  texlive-multirow texlive-wrapfig texlive-titling texlive-needspace \
  texlive-adjustbox texlive-csquotes texlive-threeparttable texlive-selnolig
```

The second line is not optional padding. `texlive-scheme-basic` omits `framed` and
`upquote`, which pandoc's *default* template requires, so **every** markdown file
fails with `LaTeX Error: File 'framed.sty' not found` until they are installed. The
rest cover features that only some documents use — `ulem` for `~~strikethrough~~`,
`multirow`/`threeparttable` for wide tables — and are listed here so a new machine
fails once rather than once per feature.

Fonts are set in the plugin rather than here, and are constrained by what XeTeX can
actually embed, not by taste:

- A **variable** font (e.g. Adwaita Sans) aborts the build with `xdvipdfmx:fatal:
  Invalid font: -1`. The body font must ship static files.
- A font with **no italic** (e.g. Cantarell) silently degrades markdown emphasis.
- Most monospace fonts here — Liberation Mono, Noto Sans Mono, JetBrains Mono Nerd —
  **lack arrows** such as `⇄` and drop them without failing the build, leaving a gap
  in the PDF. Adwaita Mono covers them and has all four regular/italic/bold faces.

Override per-machine with `vim.g.markdown_pdf_mainfont` / `markdown_pdf_monofont`.

## What is deliberately not here

KDE Plasma config (stale — sway is the live compositor, and those files carry EDID
hashes, panel serials, and activity UUIDs), auto-generated GTK/Qt theming, browser
profiles, `~/.cargo` / `~/.rustup` / `~/.npm` caches, and everything under
`~/.claude/` except a 41-byte settings file.

The common thread: those files carry machine identity (display EDIDs, MAC addresses,
UUIDs) or are regenerated by their own tooling, so tracking them creates conflicts
rather than preventing them.

**No secrets live in this repo.** SSH keys, API tokens, license files, and browser
credentials are all excluded by construction, with `.gitignore` as a backstop.
