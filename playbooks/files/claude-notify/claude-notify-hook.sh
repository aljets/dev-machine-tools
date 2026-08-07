#!/usr/bin/env bash
# Claude Code hook: track which sessions are waiting on me.
#
# Reads a hook payload on stdin. On Notification it writes one JSON file per
# session into STATE_DIR summarising what is being asked for; on Stop /
# UserPromptSubmit / SessionEnd it clears that file. The summary is pulled
# straight out of the session transcript with jq, so there is no LLM cost.
#
# Wired up by playbooks/claude_notify.yml.
set -u

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

STATE_DIR="${CLAUDE_NOTIF_STATE_DIR:-$HOME/.claude/notif-state}"
DEBUG_LOG="$STATE_DIR/debug.log"
DEBUG_LINES=200

mkdir -p "$STATE_DIR"

# Nudge SwiftBar to redraw immediately rather than waiting for its poll.
# refreshallplugins is the only refresh action SwiftBar's URL scheme exposes;
# there is no refreshplugin?name=, and an unknown action fails silently.
refresh_menubar() {
  open -g "swiftbar://refreshallplugins" >/dev/null 2>&1 || true
}

payload=$(cat)
[ -n "$payload" ] || exit 0

event=$(jq -r '.hook_event_name // ""' <<<"$payload" 2>/dev/null)
session=$(jq -r '.session_id // ""' <<<"$payload" 2>/dev/null)
[ -n "$session" ] || exit 0

state_file="$STATE_DIR/$session.json"

# Ordering log. Which hook fires relative to the permission prompt decides how
# an entry can be cleared, so record every event with a millisecond stamp.
# BSD date has no %N, so seconds is the best resolution available here.
printf '%s %s %s\n' "$(date +%H:%M:%S)" "${session:0:8}" "$event" \
  >>"$STATE_DIR/events.log"

case "$event" in
  # PostToolUse is the one that clears on approval: PreToolUse runs BEFORE the
  # permission prompt is shown, so it can only ever clear a leftover from a
  # previous cycle, never the prompt you just answered. PostToolUse fires once
  # the tool actually runs, which is the first moment we know you said yes.
  # Stop / UserPromptSubmit / SessionEnd are backstops for denials, interrupts
  # and sessions that end while a prompt is still open.
  PostToolUse|PreToolUse|Stop|UserPromptSubmit|SessionEnd)
    [ -e "$state_file" ] || exit 0
    rm -f "$state_file"
    refresh_menubar
    exit 0
    ;;
  Notification) ;;
  *) exit 0 ;;
esac

transcript=$(jq -r '.transcript_path // ""' <<<"$payload")
message=$(jq -r '.message // ""' <<<"$payload")
cwd=$(jq -r '.cwd // ""' <<<"$payload")

# Keep a short tail of raw payloads around; the exact wording of `message`
# is what the permission/idle detection below keys off, so it is worth seeing.
printf '%s\n' "$payload" >>"$DEBUG_LOG"
if [ "$(wc -l <"$DEBUG_LOG")" -gt "$DEBUG_LINES" ]; then
  tail -n "$DEBUG_LINES" "$DEBUG_LOG" >"$DEBUG_LOG.tmp" && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
fi

# Two flavours of Notification: a permission request, or "Claude is waiting for
# your input". Only the former is actionable from the menu bar, and the latter
# is already obvious from the terminal, so it is dropped rather than recorded.
# To surface idle sessions too, delete the early exit below.
kind=other
expected_tool=""
case "$message" in
  *ermission*)
    kind=permission
    expected_tool=$(sed -E 's/.*[Pp]ermission to use ([A-Za-z0-9_]+).*/\1/' <<<"$message")
    [ "$expected_tool" = "$message" ] && expected_tool=""
    ;;
esac

# Leave any existing state alone: an idle ping while a permission prompt is
# still unanswered must not clear that prompt from the menu.
[ "$kind" = permission ] || exit 0

# Pull the pending tool call out of the transcript. Bounded read of the tail,
# reversed, so we stop at the most recent tool_use. -R + fromjson? so a partial
# or non-conforming line does not abort the whole filter.
tool_json=null
if [ "$kind" = permission ] && [ -r "$transcript" ]; then
  candidates=$(tail -n 400 "$transcript" 2>/dev/null | tail -r | jq -Rc '
    fromjson? // empty
    | select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use")
    | {name, input}
  ' 2>/dev/null | head -12)
  if [ -n "$candidates" ]; then
    picked=""
    if [ -n "$expected_tool" ]; then
      picked=$(jq -sc --arg want "$expected_tool" \
        'map(select(.name == $want)) | first // empty' <<<"$candidates" 2>/dev/null)
    fi
    [ -n "$picked" ] || picked=$(head -1 <<<"$candidates")
    [ -n "$picked" ] && tool_json="$picked"
  fi
fi

jq -n \
  --arg session "$session" \
  --arg cwd "$cwd" \
  --arg message "$message" \
  --arg kind "$kind" \
  --arg win "${KITTY_WINDOW_ID:-}" \
  --arg listen "${KITTY_LISTEN_ON:-}" \
  --arg pane "${TMUX_PANE:-}" \
  --arg ts "$(date +%s)" \
  --argjson tool "$tool_json" '
  def clean: (. // "") | tostring | gsub("[\\n\\r\\t]+"; " ") | gsub(" +"; " ") | gsub("\\|"; "¦");
  def trunc($n): if (. | length) > $n then (.[0:$n - 1] + "…") else . end;
  def host: sub("^[a-z]+://"; "") | split("/") | first;

  def summarize:
    (.name // "tool") as $name
    | (.input // {}) as $in
    | if $name == "Bash" then
        { h: "Bash · " + (($in.description | clean) | trunc(52)),
          d: (($in.command | clean) | trunc(160)) }
      elif $name | test("^(Edit|Write|Read|NotebookEdit)$") then
        { h: $name + " · " + (($in.file_path | clean) | split("/") | last),
          d: ($in.file_path | clean) }
      elif $name | test("^(Glob|Grep)$") then
        { h: $name + " · " + (($in.pattern | clean) | trunc(52)),
          d: (($in.path | clean) | trunc(120)) }
      elif $name == "WebFetch" then
        { h: "WebFetch · " + (($in.url | clean) | host),
          d: (($in.url | clean) | trunc(160)) }
      elif $name == "WebSearch" then
        { h: "WebSearch · " + (($in.query | clean) | trunc(52)), d: "" }
      elif $name == "Skill" then
        { h: "Skill · " + ($in.skill | clean), d: (($in.args | clean) | trunc(160)) }
      elif $name | test("^(Agent|Task)$") then
        { h: "Agent · " + (($in.description | clean) | trunc(52)),
          d: (($in.prompt | clean) | trunc(160)) }
      elif $name | startswith("mcp__") then
        { h: "MCP · " + ($name | sub("^mcp__"; "") | gsub("__"; " / ") | trunc(52)),
          d: (($in | tostring | clean) | trunc(160)) }
      else
        { h: ($name | clean), d: (($in | tostring | clean) | trunc(160)) }
      end;

  ($tool | if . == null then { h: ($message | clean), d: "" } else summarize end) as $s
  | { session: $session,
      dir: (if $cwd == "" then "?" else ($cwd | split("/") | last) end),
      cwd: $cwd,
      message: ($message | clean),
      kind: $kind,
      tool: ($tool.name // null),
      headline: $s.h,
      detail: $s.d,
      kitty_window_id: $win,
      kitty_listen_on: $listen,
      tmux_pane: $pane,
      ts: ($ts | tonumber) }
' >"$state_file.tmp" 2>/dev/null && mv "$state_file.tmp" "$state_file"

refresh_menubar
exit 0
