#!/usr/bin/env bash
#
# <xbar.title>Next meeting</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>aljets</xbar.author>
# <xbar.desc>Minutes until the next meeting, a join link, and an alert with a Join button just before it starts.</xbar.desc>
# <xbar.dependencies>bash,jq</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Events come from MeetingBarHelper.app (EventKit), which writes them to
# EVENTS. It is launched with `open -n` rather than exec'd so the Calendar
# permission belongs to the helper bundle instead of SwiftBar.
set -u

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

APP="$HOME/Applications/MeetingBarHelper.app"
CACHE="$HOME/.cache/meeting-bar"
EVENTS="$CACHE/events.json"
ALERTED="$CACHE/alerted"
ALERT_LEAD=90      # seconds before start; one refresh interval plus slack
ALERT_LATE=180     # still alert this long after start, e.g. after waking from sleep
SOON_MINUTES=15    # yellow pill from here down to WARN_MINUTES
WARN_MINUTES=5     # orange pill until start; red once the meeting is on
STALE=600

mkdir -p "$CACHE"
touch "$ALERTED"

open -n -g -W -a "$APP" --args events "$EVENTS" >/dev/null 2>&1

now=$(date +%s)

if [ ! -r "$EVENTS" ]; then
  echo "⚠︎ | color=#8e8e93,#8e8e93"
  echo "---"
  echo "No calendar data yet. Is MeetingBarHelper.app installed?"
  exit 0
fi

if jq -e 'type == "object" and .error == "denied"' "$EVENTS" >/dev/null 2>&1; then
  echo " | sfimage=calendar.badge.exclamationmark"
  echo "---"
  echo "Calendar access denied"
  echo "Open Privacy settings | href=x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
  exit 0
fi

stale=false
[ $((now - $(stat -f %m "$EVENTS"))) -gt "$STALE" ] && stale=true

# Fire the join dialog once per occurrence. id alone repeats across a recurring
# series, so the key includes the start time. Fields are split on \x1f because
# read collapses runs of tabs, which would shift fields after an empty join.
jq -r --argjson now "$now" --argjson lead "$ALERT_LEAD" --argjson late "$ALERT_LATE" '
  .[] | select((.start - $now) <= $lead and ($now - .start) <= $late)
  | [.id + "@" + (.start | tostring), .title, (.start | tostring), (.join // ""),
     (.docs // [] | tojson | @base64)]
  | map(gsub("[\n\r\u001f]"; " ")) | join("\u001f")
' "$EVENTS" | while IFS=$'\x1f' read -r key title start join docs; do
  grep -qxF "$key" "$ALERTED" && continue
  echo "$key" >>"$ALERTED"
  open -n -a "$APP" --args alert "$title" "$start" "$join" "$docs" >/dev/null 2>&1
done
tail -n 200 "$ALERTED" >"$ALERTED.tmp" && mv "$ALERTED.tmp" "$ALERTED"

# Join and file icons are drawn by the helper once per build and cached.
icons=$(for kind in doc sheet slides drive join; do
  f="$CACHE/icon-$kind.b64"
  if [ ! -s "$f" ] || [ "$APP/Contents/MacOS/MeetingBarHelper" -nt "$f" ]; then
    "$APP/Contents/MacOS/MeetingBarHelper" icon "$kind" >"$f" 2>/dev/null
  fi
  jq -nc --arg k "$kind" --rawfile v "$f" '{($k): ($v | rtrimstr("\n"))}'
done | jq -sc 'add')

menu=$(jq -r \
  --argjson now "$now" \
  --argjson soon "$((SOON_MINUTES * 60))" \
  --argjson warn "$((WARN_MINUTES * 60))" \
  --argjson stale "$stale" \
  --arg opener "$HOME/bin/meeting-bar-open" \
  --argjson icons "$icons" '
  def clean: gsub("\\|"; "¦") | gsub("[\\n\\r\\t]+"; " ");
  def trunc($n): if length > $n then .[0:$n - 1] + "…" else . end;
  def minutes($s): (((($s - $now) | fabs) + 59) / 60 | floor);
  def short($s):
    minutes($s) as $m
    | if $m < 60 then "\($m)m"
      elif $m % 60 == 0 then "\($m / 60 | floor)h"
      else "\($m / 60 | floor)h \($m % 60)m"
      end;
  def long($s):
    minutes($s) as $m
    | if $m < 60 then "\($m) min"
      elif $m % 60 == 0 then "\($m / 60 | floor) hr"
      else "\($m / 60 | floor) hr \($m % 60) min"
      end;
  def day: strflocaltime("%Y-%m-%d");
  def header: "\(.) | size=12 color=#48484a,#c7c7cc";
  # Notion-style calendar color bar on each row. Clicking opens the event in
  # Google Calendar; joining is the separate Join row.
  def row: "\(.time) · \(.title | trunc(50)) | sfimage=capsule.portrait.fill sfcolor=\(.color // "#8e8e93")"
           + " bash=\($opener) param1=\(.link) terminal=false";
  def joinrow:
    if .join then
      [ "Join \(if (.join | test("zoom")) then "Zoom" else "Meet" end) | templateImage=\($icons.join) width=28 height=16 href=\(.join)" ]
    else [] end;
  def docrows:
    .docs // [] | map("\(.title | clean | trunc(50)) | image=\($icons[.kind] // $icons.drive) width=28 height=16 href=\(.url)");

  map(.title |= clean) as $events
  | ($events | map(select(.start <= $now)) | last) as $current
  | ($events | map(select(.start > $now)) | first) as $next
  | ($now | day) as $today
  | ($next != null and ($next.start - $now) <= $soon) as $nextsoon

  # An ongoing meeting wins the menu bar until the next one is 15 min out.
  # A "PILL<tab>bg<tab>fg<tab>text" title is drawn as a colored image below.
  | def pill($bg; $fg): "PILL\t\($bg)\t\($fg)\t\(.)";
    (if $current and ($nextsoon | not) then
       "\($current.title | trunc(28)) · \(short($current.end)) left" | pill("#ff3b30"; "#ffffff")
     elif $next and ($next.start - $now) <= 12 * 3600 then
       "\($next.title | trunc(28)) in \(short($next.start))"
       | (($next.start - $now) as $left
          | if $left <= $warn then pill("#ff9f0a"; "#000000")
            elif $left <= $soon then pill("#ffd60a"; "#000000")
            else . end)
     else
       " | sfimage=calendar"
     end)
    as $title

  | ($events | map(select(. != $current and . != $next))) as $rest
  | ($rest | map(select((.start | day) <= $today))) as $todays
  | ($rest | map(select((.start | day) > $today))) as $later

  | [$title, "---"]
  + (if $stale then ["Calendar data is stale | color=#e30016,#ff453a"] else [] end)
  + (if $current then
       ["Now · \(long($current.end)) left" | header] + [$current | row] + ($current | joinrow) + ($current | docrows)
     else [] end)
  + (if $next then
       ["Upcoming in \(long($next.start))" | header] + [$next | row]
       + (if $nextsoon then $next | joinrow else [] end)
       + ($next | docrows)
     else ["No upcoming meetings" | header] end)
  + (if ($todays | length) > 0 then ["Today" | header] + ($todays | map(row)) else [] end)
  + (if ($later | length) > 0 then ["Tomorrow" | header] + ($later | map(row)) else [] end)
  + ["---",
     "Open Google Calendar | bash=\($opener) param1=https://calendar.google.com/calendar/r terminal=false",
     "Refresh | refresh=true"]
  | .[]
' "$EVENTS")

title=${menu%%$'\n'*}
if [[ $title == PILL$'\t'* ]]; then
  IFS=$'\t' read -r _ bg fg text <<<"$title"
  if img=$("$APP/Contents/MacOS/MeetingBarHelper" pill "$text" "$bg" "$fg" 2>/dev/null) && [ -n "$img" ]; then
    title="| image=$img"
  else
    title="$text"
  fi
fi
printf '%s\n%s\n' "$title" "${menu#*$'\n'}"
