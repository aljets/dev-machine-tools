# Next meeting in the menu bar

A SwiftBar plugin that shows `<title> in 12m` for the next meeting (or
`<title> · 20m left` during one) as a colored pill: yellow from 15 minutes out,
orange inside 5, red once the meeting starts. About a minute before each
meeting it puts up a floating panel with a Join button on every display. It
replaces Notion Calendar's menu bar item without installing it.

## Pieces

| file | role |
| --- | --- |
| `MeetingBarHelper.swift` | EventKit reader (`events`), join panel (`alert`), menu bar pill image (`pill`), Docs/Sheets/Slides row icons (`icon`) |
| `Info.plist` | Bundle metadata, including the Calendar usage strings |
| `meeting-bar.1m.sh` | SwiftBar plugin. Fetches, fires alerts, renders the menu |
| `meeting-bar-open.sh` | Opens a URL in the Google Calendar web app (`~/bin/meeting-bar-open`) |

`playbooks/meeting_bar.yml` compiles the Swift into
`~/Applications/MeetingBarHelper.app`, ad-hoc signs it, and symlinks the plugin
into `~/tools/swiftbar-plugins`. SwiftBar itself is set up by
`claude_notify.yml`.

## Calendar source

macOS Calendar, so the work Google account must be added under System Settings ›
Internet Accounts with Calendars on. All-day, cancelled and declined events are
skipped.

Google accounts get no push in macOS, so edits made on the web only arrive on
Calendar's refresh schedule. The helper calls `refreshSourcesIfNecessary()` on
every run to nudge a sync; the result shows up on the following run. Setting
Calendar › Settings › Accounts › Refresh Calendars to "Every minute" also helps.

## Why a separate app bundle

Since macOS 14, EventKit only grants access to a process whose responsible app
has `NSCalendarsFullAccessUsageDescription` in its Info.plist. SwiftBar ships
only the older `NSCalendarsUsageDescription`, so a binary exec'd from the plugin
is denied without a prompt. The helper is its own bundle and is started with
`open -n`, which makes it the responsible process. `-n` matters: without it a
second `open` hands its arguments to an already running instance (an alert
still on screen) and they are dropped.

Each rebuild changes the ad-hoc signature, so macOS asks for access again. The
playbook only rebuilds when the Swift source or plist is newer than the binary.

## Join links

The first Zoom URL in the event's URL, location or notes is rewritten to
`zoommtg://<host>/join?confno=…&pwd=…`, which opens the Zoom app directly
instead of leaving a browser tab behind. Google Meet links are passed through
as-is.

## Doc links

The current and next meetings list each Google Docs/Drive link on its own row
under the meeting. Links come from Google Calendar attachments (read through
EventKit's private `attachments` property, using the file name as the label)
and from any `docs.google.com` or `drive.google.com` URL in the event's URL,
location or notes, deduped by Drive file id. A description link is labeled
with its link text, or, when the link text is the bare URL, with the label in
front of it ("Agenda: <url>" shows as "Agenda"). With neither it falls back to
"Google Doc", "Google Sheet" and so on. Each row gets a Docs, Sheets or Slides
style icon drawn by the helper and cached in `~/.cache/meeting-bar`. Menus pin
icons to the left edge and SwiftBar strips leading spaces, so the Join and doc
icons carry a "└" connector on their left, which both indents the row and ties
it to the meeting above.

## Opening events

Clicking a meeting opens it in Google Calendar. Google's event page takes
`eid = base64("<event id> <calendar id>")`; over CalDAV the iCal UID is
`<event id>@google.com`, and an occurrence of a recurring series appends
`_<UTC start>`. An occurrence edited on its own arrives as
`<event id>@google.com/RID=<original start>`, with the start in seconds since
2001. A series split with "this and following" adds `_R<split start>` to the
UID, which Google's event id does not have, so it is stripped. Any other UID
opens the day view instead. `uid` in `events.json` shows
what macOS reported.

`meeting-bar-open` targets the installed web app (a Brave/Chrome "app
shortcut" under `~/Applications/*Apps.localized/Google Calendar.app`). Opening
the shim bundle drops the URL, so it calls the browser binary with
`--app-id=<id> --app-launch-url-for-shortcuts-menu-item=<url>`; a running
browser forwards that to the app window. Without the web app it uses the
default browser.

## Alerts

The plugin runs every minute and alerts for any meeting starting within 90s,
or one that started under 3 minutes ago (e.g. after waking from sleep). Each
occurrence is recorded in `~/.cache/meeting-bar/alerted` as `<id>@<start>`, so
a recurring series alerts once per instance. Snooze re-shows the dialog after a
minute and is offered until the meeting is 5 minutes in, when the dialog closes
itself.

## Debugging

    ~/tools/swiftbar-plugins/meeting-bar.1m.sh
    jq . ~/.cache/meeting-bar/events.json
    open -n -a ~/Applications/MeetingBarHelper.app --args alert "Test" "$(($(date +%s)+60))" https://example.com

`{"error":"denied"}` in `events.json` means Calendar access was refused; the
menu links to the Privacy pane. `tccutil reset Calendar local.meeting-bar-helper`
makes macOS ask again.
