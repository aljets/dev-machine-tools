#!/usr/bin/env bash
# Act on a pending Claude Code session recorded by claude-notify-hook.sh.
#
#   claude-notify-action focus   <session_id>   bring its kitty window forward
#   claude-notify-action approve <session_id>   press Enter in that window
#   claude-notify-action dismiss <session_id>   drop it from the menu
#   claude-notify-action clear                  drop everything
#
# approve refuses to act unless the session is genuinely sitting on a
# permission prompt, so an idle-timeout notification can never turn into a
# stray Enter in the composer.
set -u

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

STATE_DIR="${CLAUDE_NOTIF_STATE_DIR:-$HOME/.claude/notif-state}"

action="${1:-}"
session="${2:-}"

refresh_menubar() {
  open -g "swiftbar://refreshallplugins" >/dev/null 2>&1 || true
}

if [ "$action" = clear ]; then
  rm -f "$STATE_DIR"/*.json
  refresh_menubar
  exit 0
fi

state_file="$STATE_DIR/$session.json"
[ -r "$state_file" ] || exit 0

win=$(jq -r '.kitty_window_id // ""' "$state_file")
listen=$(jq -r '.kitty_listen_on // ""' "$state_file")
pane=$(jq -r '.tmux_pane // ""' "$state_file")
kind=$(jq -r '.kind // ""' "$state_file")

kitty_rc() {
  if [ -n "$listen" ]; then
    kitten @ --to "$listen" "$@"
  else
    kitten @ "$@"
  fi
}

focus_session() {
  open -a kitty >/dev/null 2>&1
  [ -n "$win" ] && kitty_rc focus-window --match "id:$win" >/dev/null 2>&1
  if [ -n "$pane" ]; then
    tmux select-window -t "$pane" >/dev/null 2>&1
    tmux select-pane -t "$pane" >/dev/null 2>&1
  fi
}

case "$action" in
  focus)
    focus_session
    ;;
  approve)
    # Guard: only a real permission prompt has a safe default of "Yes".
    if [ "$kind" != permission ]; then
      focus_session
      exit 0
    fi
    if [ -n "$pane" ]; then
      tmux send-keys -t "$pane" Enter >/dev/null 2>&1
    elif [ -n "$win" ]; then
      kitty_rc send-key --match "id:$win" enter >/dev/null 2>&1
    else
      focus_session
      exit 0
    fi
    rm -f "$state_file"
    ;;
  dismiss)
    rm -f "$state_file"
    ;;
  *)
    echo "usage: claude-notify-action {focus|approve|dismiss} <session_id> | clear" >&2
    exit 64
    ;;
esac

refresh_menubar
exit 0
