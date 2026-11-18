#!/usr/bin/env bash
# vibe.sh: the unserious half of ~/.tmux.conf
#
#   vibe.sh new CLIENT   create/switch to a vibe session (name read from @vibe_name)
#   vibe.sh badge        print the rainbow VIBE badge + a rotating tagline (status bar)
#
# Vibe sessions live in ~/vibes/<name> so experiments stay out of real projects.
# VIBE_CMD overrides what starts in the first pane (default: claude); VIBE_DIR the parent dir.

rainbow=('#fb4934' '#fe8019' '#fabd2f' '#b8bb26' '#83a598' '#d3869b')

taglines=(
  "vibes: immaculate"
  "tests? never heard of her"
  "works on my machine"
  "LGTM 👍 (didn't read it)"
  "no thoughts, just tokens"
  "git push --force-of-nature"
  "the AI said it's fine"
  "compiles ⇒ correct"
  "TODO: understand this"
  "rubber duck on holiday"
  "ship it 🚀"
  "trust the process"
  "error handling is a mindset"
  "it's not a bug, it's lore"
  "refactor later (never)"
  "accept all ✅"
  "one more prompt…"
  "senior vibe engineer"
)

welcomes=(
  "🌈 vibe mode on. tests optional, vibes mandatory."
  "🌈 entering the vibe zone. leave your linter at the door."
  "🌈 no tickets, no standups, just vibes."
  "🌈 productivity has left the chat."
  "🌈 hold my coffee, Claude's driving."
)

surprise=(chaos-goblin side-quest yolo-lab spaghetti-factory big-brain
          gremlin-hours vibe-check hold-my-beer cursed-ideas skunkworks)

pick() { local a=("$@"); printf '%s' "${a[RANDOM % ${#a[@]}]}"; }

badge() {
  local s word="VIBE" out i c
  s=$(date +%s)
  out="#[bg=#282828,bold] ✨"
  for i in 0 1 2 3; do
    c=${rainbow[$(( (i - s) % 6 + 6 ))%6]}   # colours slide one step every second
    out+="#[fg=$c]${word:i:1}"
  done
  out+="✨ #[default]"
  out+=" #[fg=#d3869b,italics]${taglines[$(( s / 8 % ${#taglines[@]} ))]}#[default] "
  printf '%s' "$out"
}

new() {
  local client=$1 name dir
  name=$(tmux show -gv @vibe_name 2>/dev/null)
  name=${name//[^A-Za-z0-9_-]/-}                 # tmux-safe session name
  [ -z "$name" ] && name="$(pick "${surprise[@]}")-$((RANDOM % 100))"

  if tmux has-session -t "=$name" 2>/dev/null; then
    if [ -z "$(tmux show -t "=$name:" -qv @vibe)" ]; then
      tmux display-message -c "$client" -d 3000 "🚫 '$name' is a work session. vibes denied."
      return
    fi
  else
    dir=${VIBE_DIR:-$HOME/vibes}/$name
    mkdir -p "$dir"
    tmux new-session -d -s "$name" -c "$dir" -n vibing
    tmux set -t "=$name:" @vibe 1
    tmux set -t "=$name:" status-interval 1       # keeps the rainbow moving (this session only)
    tmux set -t "=$name:" status-right-length 100
    tmux set -t "=$name:" status-left "#[bg=#d3869b,fg=#282828,bold] 🌈 #S #[default] "
    [ -n "${VIBE_CMD-claude}" ] && tmux send-keys -t "=$name:" "${VIBE_CMD-claude}" Enter
  fi
  tmux switch-client -c "$client" -t "=$name"
  tmux display-message -c "$client" -d 4000 "$(pick "${welcomes[@]}")"
}

case $1 in
  badge) badge ;;
  new)   new "$2" ;;
  *)     echo "usage: vibe.sh new CLIENT | badge" >&2; exit 1 ;;
esac
