# Dotfiles migration to GNU Stow

## Context

`~/dotfiles` exists but is empty, and no config on this machine is version-controlled (except `~/.config/nvim`, which is an upstream clone with uncommitted edits). All hand-written config currently lives loose in `$HOME` with no backup and no history — a reinstall loses it.

Goal: move the genuinely hand-written config into `~/dotfiles` as GNU Stow packages, symlink it back into place, and put it under git. The audit found roughly **75 KB** of real config buried in ~944 MB of `.config` (Brave + Firefox profiles alone are 938 MB), so the work is mostly deciding what *not* to take.

Key facts established during exploration:
- Fedora 44, login shell **zsh**, live session is **sway/wayland** (`XDG_CURRENT_DESKTOP=sway;wlroots`). Plasma is installed but its configs were last touched Jun 11–24 and are stale.
- `stow` is **not installed**. Available as `stow 2.4.1-4.fc44`. User is in `wheel`, but sudo needs a password — the install must be run interactively.
- `git 2.55.0` present and configured. `gh` is not installed.
- `~/.config/nvim` is a clone of `nvim-lua/kickstart.nvim` @ `cfdc17b` with 22 insertions / 8 deletions in `init.lua` (gruvbox, `relativenumber`, 4-space tabs, `clangd` enabled) and no local commits.

Decisions made: scope = core + sway desktop; nvim = vendor files and drop `.git`; machine-specific values = split into gitignored local files; remote = local git only for now.

---

## SECURITY — do this first, before any `git add`

Real credentials found on disk. None of these may enter the repo.

**`~/imp.txt` contains a live plaintext Cloudflare API token** (`cfut_...`, 51 chars). It is not a dotfile and is not part of this migration, but it sits in `$HOME` in the clear. **Recommend rotating it** at the Cloudflare dashboard and storing the replacement in a secret manager rather than a text file. Flagging only — no action taken.

Other secrets confirmed, all excluded from every package below:

| Path | What it is |
|---|---|
| `~/.ssh/id_ed25519` | private SSH key |
| `~/.claude/.credentials.json` | OAuth credentials (0600) |
| `~/.claude/daemon/control.key` | daemon key |
| `~/.claude.json` | 42 KB project/MCP state |
| `~/.config/kdeconnect/privateKey.pem` + `certificate.pem` | device identity keypair |
| `~/.Wolfram/Licensing/mathpass` | Wolfram activation key |
| `~/.altera.quartus/quartus2.ini` | Monash floating-license server + token file |
| `~/.config/BraveSoftware/` (882M), `~/.config/mozilla/` (56M) | browser cookies, logins, sessions |
| `~/.config/pulse/cookie`, `~/.config/libaccounts-glib/accounts.db` | auth cookie, online-accounts DB |
| `~/.GlobalProtect/` | enterprise VPN client state |

The `.gitignore` in Step 4 is a backstop, not the primary defence — the primary defence is that no package ever references these paths.

---

## Target layout

Stow package = directory whose contents mirror `$HOME`. Run `stow` from `~/dotfiles` with target `~` (the default: stow targets the parent of the stow dir).

```
~/dotfiles/
├── .gitignore
├── PLAN.md              <- this document, copied here (user asked for it)
├── README.md
├── zsh/        .zshrc  .zshenv
├── bash/       .bashrc  .bash_profile  .profile
├── git/        .gitconfig
├── clangd/     .clangd
├── nvim/       .config/nvim/{init.lua,nvim-pack-lock.json,lua/}
├── sway/       .config/sway/{config,scripts/}
├── waybar/     .config/waybar/{config.jsonc,style.css}
├── mako/       .config/mako/config
├── fuzzel/     .config/fuzzel/fuzzel.ini
├── alacritty/  .config/alacritty/alacritty.toml
├── fastfetch/  .config/fastfetch/config.jsonc
└── xdg/        .config/mimeapps.list
```

### What goes in — and its current size

| Package | Source | Size | Why |
|---|---|---|---|
| zsh | `~/.zshrc`, `~/.zshenv` | 237 B | Hand-written `PROMPT`, `vf()` fzf+nvim function, PATH. No framework (no oh-my-zsh/starship). |
| bash | `~/.bashrc`, `~/.bash_profile`, `~/.profile` | 969 B | Fedora skel + cargo env + `QSYS_ROOTDIR`. Kept for non-login/TTY use. |
| git | `~/.gitconfig` | 71 B | name / email / `editor = nvim`. No credential helper, no tokens. |
| clangd | `~/.clangd` | 38 B | `-std=c++23`. |
| nvim | `~/.config/nvim` | ~46 KB after pruning | `init.lua` (41 KB), `lua/`, `nvim-pack-lock.json`. |
| sway | `~/.config/sway` | 7.9 KB | 360-line diff vs `/etc/sway/config`; alacritty/fuzzel/waybar/mako wiring, touchpad, media keys, screenshots. Plus 2 executable scripts. |
| waybar | `~/.config/waybar` | 10.7 KB | `config.jsonc` + `style.css`, actively edited Jul 27. |
| mako | `~/.config/mako/config` | 172 B | Catppuccin Mocha. |
| fuzzel | `~/.config/fuzzel/fuzzel.ini` | 333 B | Colors, JetBrains Mono 14. |
| alacritty | `~/.config/alacritty/alacritty.toml` | 386 B | JetBrainsMono Nerd Font 13, Shift+Return binding. |
| fastfetch | `~/.config/fastfetch/config.jsonc` | 511 B | 28-module list. |
| xdg | `~/.config/mimeapps.list` | 297 B | Brave as default handler + `claude-cli` scheme. Fully portable. |

### What stays out — and why

- **All KDE Plasma state** — `kwinoutputconfig.json` (EDID hashes, panel serial `SDC 16799`), `plasma-org.kde.plasma.desktop-appletsrc` (activity UUID `ff03d254-…`, resolution-keyed geometry), `kwinrc` (desktop UUIDs), `kconf_updaterc` (migration markers — stowing it *suppresses* future migrations), `kglobalshortcutsrc` (15 KB carrying exactly two non-default bindings). Stale since June; sway is the live compositor.
- **Auto-generated theming** — `~/.config/gtk-3.0/{colors.css,window_decorations.css,assets/}`, `gtk-4.0/` equivalents, `gtkrc`, `gtkrc-2.0`, `xsettingsd/`. Written by `kde-gtk-config`; `gtk-xft-dpi=157286` is display-specific. Stowing `~/.gtkrc-2.0` would also mean Plasma clobbers the symlink on the next theme change.
- **Stale backups** — `~/.config/waybar-backup/` (superseded Jul 14 snapshot), `alacritty.toml.afd21a95.bak`.
- **Empty / contentless** — `~/.config/btop/` (empty `themes/`), `~/.vim/` (only `.netrwhist`), `kwinrulesrc`, `plasmaparc`, `goa-1.0`, `procps`, `abrt`, `imsettings`, `qtvirtualkeyboard`.
- **Package-manager artifacts** — `~/.cargo` (171M), `~/.rustup` (1.4G), `~/.npm` (338M), `~/.local/share/nvim` (392M of installed plugins), `~/.local/bin` (only a `claude` symlink + numpy shims; zero hand-written scripts). No `~/.npmrc` exists.
- **`~/.claude/`** — 25M, essentially all runtime state (`projects/` 16M, `plugins/` 6.3M, `history.jsonl`). Only `settings.json` is user config and it is 41 bytes (`{"theme":"dark","model":"Opus"}`) — not worth a package.
- **`~/.bash_logout`** — byte-identical to `/etc/skel/.bash_logout`.
- **`~/.config/systemd/user/.../warp-desktop-svc.service`** — a symlink into `/usr/lib`; stowing a symlink-to-symlink is a footgun. Recreate with `systemctl --user enable`.
- **KiCad / Quartus / Wolfram** — license servers and absolute paths; out of scope per the chosen scope.

---

## Steps

### Step 1 — Install stow (interactive, needs your password)

```bash
sudo dnf install stow
```
Run this yourself in the session with `! sudo dnf install stow` — sudo requires a password and cannot be automated. Everything after this is non-interactive.

### Step 2 — Back up, then build packages

Take a safety copy first so nothing is unrecoverable:
```bash
tar czf ~/dotfiles-backup-$(date +%F).tar.gz \
  ~/.zshrc ~/.zshenv ~/.bashrc ~/.bash_profile ~/.profile \
  ~/.gitconfig ~/.clangd ~/.config/nvim ~/.config/sway \
  ~/.config/waybar ~/.config/mako ~/.config/fuzzel \
  ~/.config/alacritty ~/.config/fastfetch ~/.config/mimeapps.list
```

Then, for each package: `mkdir -p` the mirrored path and **`mv`** the real file in (move, not copy — stow needs the original gone before it can symlink). Example for two packages:

```bash
mkdir -p ~/dotfiles/zsh ~/dotfiles/sway/.config/sway
mv ~/.zshrc ~/.zshenv          ~/dotfiles/zsh/
mv ~/.config/sway/config       ~/dotfiles/sway/.config/sway/
mv ~/.config/sway/scripts      ~/dotfiles/sway/.config/sway/
```

Same pattern for `bash`, `git`, `clangd`, `waybar`, `mako`, `fuzzel`, `alacritty`, `fastfetch`, `xdg`.

**nvim is the exception** — copy the wanted files, then remove the original tree:
```bash
mkdir -p ~/dotfiles/nvim/.config/nvim
cp -r ~/.config/nvim/init.lua ~/.config/nvim/lua \
      ~/.config/nvim/nvim-pack-lock.json ~/dotfiles/nvim/.config/nvim/
rm -rf ~/.config/nvim
```
This drops `.git/`, `README.md`, `LICENSE.md`, `doc/`, `.github/`, `.stylua.toml`, `.gitignore`. `nvim-pack-lock.json` is upstream-gitignored but **must be tracked here** — it pins plugin versions. Plugins themselves stay in `~/.local/share/nvim/` and are never stowed.

Preserve the `+x` bit on `sway/scripts/brightness-notify` and `volume-notify` (`mv` does; verify after).

### Step 3 — Split out machine-specific values

Three values are specific to this laptop and must not be tracked.

**Sway** — `~/dotfiles/sway/.config/sway/config`: remove the two `output` lines and add near the top:
```
include ~/.config/sway/config.d/*
```
Then create the untracked local file (note: real dir, *not* inside the package):
```bash
mkdir -p ~/.config/sway/config.d
cat > ~/.config/sway/config.d/local <<'EOF'
output DP-3   resolution 3840x2160@60Hz position 2880,0
output eDP-1  resolution 2880x1800@60Hz position 0,0
EOF
```

**Zsh** — append to `~/dotfiles/zsh/.zshrc`:
```zsh
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
```
and put the Quartus path in `~/.zshrc.local` (untracked):
```zsh
export QSYS_ROOTDIR="$HOME/intelFPGA_lite/18.1/quartus/sopc_builder/bin"
```
Worth knowing: `QSYS_ROOTDIR` was appended to `.bashrc`/`.bash_profile`/`.profile` by the Quartus installer on Jul 27, but **never to your zsh files** — so your actual interactive shell has never had it set. This step fixes that as a side effect.

**Bash** — replace the hardcoded `/home/yannf/...` in the three bash files with `$HOME/...` so they survive a different username.

Optional cleanup while here: `.zshrc` has trailing whitespace after the `PROMPT` line, and `~/.zshrc` sets `PATH` while `~/.zshenv` sources cargo env — leaving the two shells inconsistent. Consolidating is a judgement call, not required.

### Step 4 — `.gitignore` and docs

`~/dotfiles/.gitignore`:
```gitignore
# never track secrets or host-local overrides
*.local
.config/sway/config.d/
*.bak
*.swp
.credentials.json
id_*
*.pem
*.key
```

Write `README.md` (what each package is, how to bootstrap) and copy this plan to `~/dotfiles/PLAN.md` as requested.

### Step 5 — Stow it

Dry run first — this is the step that catches conflicts:
```bash
cd ~/dotfiles
stow -n -v zsh bash git clangd nvim sway waybar mako fuzzel alacritty fastfetch xdg
```
Expect zero `WARNING: existing target` lines. If any appear, the original file was not moved in Step 2 — fix that rather than reaching for `--adopt` (`--adopt` overwrites *package* content with whatever is in `$HOME`, which is backwards here and can silently discard your edits).

Then for real:
```bash
stow zsh bash git clangd nvim sway waybar mako fuzzel alacritty fastfetch xdg
```

### Step 6 — git init

```bash
cd ~/dotfiles
git init -b main
git add -A
git status          # <- read this before committing; confirm no secrets, no .git from nvim
git commit -m "Initial dotfiles: shell, git, nvim, sway desktop"
```
No remote for now, per your choice. Adding one later: create a **private** repo in the browser, then `git remote add origin git@github.com:<you>/dotfiles.git` using the existing ed25519 key.

---

## Verification

1. **Symlinks resolve** — `ls -l ~/.zshrc ~/.gitconfig ~/.config/sway/config ~/.config/waybar/config.jsonc` should each show `-> ../dotfiles/...`.
2. **Nothing was lost** — `ls -la ~ | grep -c '^l'` and confirm every moved file is now a link; compare against the Step 2 tarball if in doubt.
3. **Scripts still executable** — `test -x ~/.config/sway/scripts/volume-notify && echo ok`.
4. **Sway config parses before you reload** — `sway --validate` (or `swaymsg -t get_version` after). Then `swaymsg reload` and check: both monitors keep their positions, waybar and mako restart, `Super+Return` opens alacritty, `Super+d` opens fuzzel, volume/brightness keys still produce notifications.
5. **Shell** — open a new terminal: prompt renders in cyan/magenta, `vf` works, `echo $QSYS_ROOTDIR` is now non-empty, `echo $PATH` contains `~/.local/bin` exactly once.
6. **Neovim** — `nvim` starts clean with gruvbox, relative numbers, 4-space tabs, and `:checkhealth` shows plugins still loading from `~/.local/share/nvim`.
7. **Unstow round-trip** — `cd ~/dotfiles && stow -D alacritty && stow alacritty` should leave the symlink exactly as before. This proves the repo is genuinely re-deployable.
8. **Secret sweep before any push** — `git -C ~/dotfiles grep -iE 'token|password|secret|BEGIN .*PRIVATE KEY'` should return nothing.

## Rollback

`cd ~/dotfiles && stow -D <package>` removes the symlinks; then `mv` the files back from the package, or extract the Step 2 tarball. Nothing in this plan deletes an original before it exists somewhere else — except the `rm -rf ~/.config/nvim` in Step 2, which is why the tarball is taken first.
