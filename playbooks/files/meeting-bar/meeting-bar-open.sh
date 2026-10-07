#!/usr/bin/env bash
# Open a Google Calendar URL in the installed Google Calendar web app (a
# Chromium "app shortcut" in ~/Applications), falling back to the default
# browser. Launching the shim bundle drops the URL, so the browser binary is
# called with the app id instead; a running browser forwards it to the app
# window.
set -u

url="${1:?usage: meeting-bar-open <url>}"

for shim in "$HOME"/Applications/*Apps.localized/"Google Calendar.app"; do
  [ -r "$shim/Contents/Info.plist" ] || continue
  app_id=$(defaults read "$shim/Contents/Info" CrAppModeShortcutID 2>/dev/null) || continue
  browser_id=$(defaults read "$shim/Contents/Info" CrBundleIdentifier 2>/dev/null) || continue
  browser=$(mdfind "kMDItemCFBundleIdentifier == '$browser_id'" | head -1)
  [ -n "$browser" ] || continue
  exe="$browser/Contents/MacOS/$(defaults read "$browser/Contents/Info" CFBundleExecutable)"
  "$exe" --app-id="$app_id" --app-launch-url-for-shortcuts-menu-item="$url" >/dev/null 2>&1 &
  exit 0
done

open "$url"
