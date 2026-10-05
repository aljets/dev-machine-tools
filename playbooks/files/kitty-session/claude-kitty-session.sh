#!/bin/sh
# Tags the kitty window with its Claude session id so a restored session can
# resume it (see claude.fish). The kitty watcher saves the session on the change.
[ -n "$KITTY_WINDOW_ID" ] || exit 0
input=$(cat)
case $(printf %s "$input" | jq -r .hook_event_name) in
SessionStart)
  kitty @ set-user-vars --match "id:$KITTY_WINDOW_ID" "claude_session=$(printf %s "$input" | jq -r .session_id)"
  ;;
SessionEnd)
  kitty @ set-user-vars --match "id:$KITTY_WINDOW_ID" claude_session
  ;;
esac
exit 0
