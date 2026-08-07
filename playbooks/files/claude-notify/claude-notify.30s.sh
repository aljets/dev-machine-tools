#!/usr/bin/env bash
#
# <xbar.title>Claude Code pending</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>aljets</xbar.author>
# <xbar.desc>Menu bar indicator for Claude Code sessions waiting on approval. Click to focus the kitty window; the submenu shows the tool call and can approve it.</xbar.desc>
# <xbar.dependencies>bash,jq,kitty</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# refreshOnOpen is deliberately NOT set: it re-runs this script synchronously
# when the menu is clicked, which shows up as a visible pause before the menu
# draws. The hooks push a refresh on every state change anyway, so the cached
# render is already current.
#
# State is written by claude-notify-hook.sh. The 30s interval is only a safety
# net: the hook pushes swiftbar://refreshallplugins on every change, so the menu
# bar updates as soon as Claude asks for something. refreshallplugins is the
# only refresh action SwiftBar's URL scheme exposes; there is no
# refreshplugin?name=, and an unknown action fails silently.
set -u

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

STATE_DIR="${CLAUDE_NOTIF_STATE_DIR:-$HOME/.claude/notif-state}"
ACTION="$HOME/bin/claude-notify-action"
MAX_AGE=21600 # 6h; anything older is a session that died without a Stop hook

shopt -s nullglob

# Drop entries whose kitty window has gone away. This is a cheap existence
# check, not a read of the screen contents: scraping the terminal for prompt
# text is unreliable, not least because a session discussing permission prompts
# has that very text in its own scrollback.
for f in "$STATE_DIR"/*.json; do
  win=$(jq -r '.kitty_window_id // ""' "$f" 2>/dev/null)
  [ -n "$win" ] || continue
  listen=$(jq -r '.kitty_listen_on // ""' "$f" 2>/dev/null)
  kitten @ ${listen:+--to "$listen"} ls --match "id:$win" >/dev/null 2>&1 || rm -f "$f"
done

files=("$STATE_DIR"/*.json)

if [ ${#files[@]} -eq 0 ]; then
  entries='[]'
else
  entries=$(jq -sc '.' "${files[@]}" 2>/dev/null) || entries='[]'
fi

jq -nr \
  --argjson entries "$entries" \
  --argjson now "$(date +%s)" \
  --argjson maxage "$MAX_AGE" \
  --arg action "$ACTION" '
  def age($now):
    (($now - (.ts // 0)) | floor) as $d
    | if $d < 60 then "\($d)s ago"
      elif $d < 3600 then "\(($d / 60) | floor)m ago"
      else "\(($d / 3600) | floor)h ago"
      end;

  def act($verb): "bash=\($action) param1=\($verb) param2=\(.session) terminal=false refresh=true";

  ($entries
   | map(select(($now - (.ts // 0)) < $maxage))
   | sort_by(-(.ts // 0))) as $pending

  # Everything recorded is a permission request, so the badged bell always means
  # "there is a decision to make". color/sfcolor take a light,dark pair: the
  # menu bar draws dark glyphs in Light Mode, where one bright orange washes out.
  | (if ($pending | length) == 0 then
      [" | sfimage=terminal color=#8e8e93,#8e8e93 sfcolor=#8e8e93,#8e8e93"]
     else
      # Deliberately a text glyph rather than sfimage: SwiftBar draws the SF
      # Symbol in the menu bar title as a template image and ignores sfcolor,
      # so the bell always came out black. Text honours color, including a
      # light,dark pair, so the dot is actually red in both appearances.
      # NB: no apostrophes anywhere in this jq program, it is single-quoted.
      ["● \($pending | length) | color=#e30016,#ff453a size=14"]
     end)

  + ["---"]

  # Flat, no submenus: opening the menu already shows every command, so
  # approving is a single click. Dismiss rides along as an option-key
  # alternate on the line above it rather than costing its own row.
  + (if ($pending | length) == 0 then
      ["No sessions waiting | color=#6b6b70,#a1a1a6", "---"]
     else
      ($pending | map(
        [ "\(.dir) · \(.headline) | \(act("focus"))",
          "   \(age($now)) · \(if (.detail // "") == "" then .message else .detail end) | font=Menlo size=11 color=#6b6b70,#a1a1a6"
        ]
        + [ "   ✓  Approve | \(act("approve"))",
            "   ✕  Dismiss | \(act("dismiss")) alternate=true",
            "---" ]
      ) | add)
     end)

  + ["Clear all | bash=\($action) param1=clear terminal=false refresh=true color=#6b6b70,#a1a1a6"]

  | .[]
'
