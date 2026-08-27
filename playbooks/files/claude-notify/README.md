# Claude Code menu bar notifications

A SwiftBar menu bar item showing which Claude Code sessions are waiting on you,
what each one is asking to run, and a way to approve it without leaving the
mouse.

## Pieces

| file | role |
| --- | --- |
| `claude-notify-hook.sh` | Claude Code hook. Writes/clears `~/.claude/notif-state/<session>.json` |
| `claude-notify.30s.sh` | SwiftBar plugin. Renders the menu from that directory |
| `claude-notify-action.sh` | Menu actions: focus, approve, dismiss, clear |

Installed by `playbooks/claude_notify.yml`, which symlinks the scripts into
`~/bin` and `~/tools/swiftbar-plugins` and registers the hooks in
`~/.claude/settings.json`.

The plugin directory is visible rather than `~/.swiftbar/plugins` because
SwiftBar's first-run picker is an NSOpenPanel, which hides dotfolders and
prompts even when the default is pre-seeded.

## How the summary is built

The `Notification` hook payload carries `transcript_path`. The pending tool call
is already in that JSONL as a `tool_use` block, so the hook reads the tail of the
transcript with `jq` and formats it. No model call, no added latency.

- `Bash` shows its `description` (Claude writes a 5-10 word summary per call)
  with the raw command underneath
- `Edit` / `Write` / `Read` show the file basename
- `WebFetch` shows the host, `Grep` / `Glob` the pattern
- `mcp__server__tool` shows `server / tool`

## What gets shown

Only permission requests. Claude also fires `Notification` when the prompt has
been idle 60s, but that is visible from the terminal anyway and cannot be acted
on, so the hook drops it (see the early exit in `claude-notify-hook.sh`). An idle
ping never clears a permission entry that is still outstanding.

## Approving from the menu

The menu is flat, so approving is one click. Each session is three rows:

    <dir> · <headline>            click to focus the kitty window
       <age> · <command>          dimmed
       ✓  Approve                 sends Enter, taking the default "Yes"

`Dismiss` is an option-key alternate on the `Approve` row: hold ⌥ and it swaps
in, costing no extra row.

The action script re-checks `kind == permission` before sending anything, so a
stale menu falls back to focusing the window instead of typing into it.

Targeting uses `KITTY_WINDOW_ID` + `KITTY_LISTEN_ON`, captured from the hook's
environment, via `kitten @`. Requires `allow_remote_control yes` and a
`listen_on` in `kitty.conf`. If the session is inside tmux, `TMUX_PANE` is
recorded too and `tmux send-keys` is used instead.

## Launch at login

SwiftBar 2.x drives its own "Launch at Login" through `SMAppService`, which has
no defaults key and no CLI, so the playbook installs
`~/Library/LaunchAgents/local.swiftbar.plist` instead. It runs `open -a
SwiftBar`, which is a no-op when the app is already up, so it cannot collide with
SwiftBar's own toggle.

    launchctl print gui/$(id -u)/local.swiftbar

If the menu bar item is missing while SwiftBar is running, check that
`defaults read com.ameba.SwiftBar` has `NSStatusItem VisibleCC
claude-notify.30s.sh = 1` — macOS records a hidden item there and SwiftBar
looks otherwise identical to a plugin that never ran.

## Debugging

`~/.claude/notif-state/debug.log` keeps the last 200 raw hook payloads. The
permission-vs-idle detection matches on `message` containing `ermission`; check
the log if the wording changes.

Render the menu by hand:

    ~/tools/swiftbar-plugins/claude-notify.30s.sh

Force a redraw:

    open -g "swiftbar://refreshallplugins"

`refreshallplugins` is the only refresh action SwiftBar's URL scheme supports.
There is no `refreshplugin?name=`, and an unrecognised action fails silently, so
a typo there looks exactly like the menu bar simply not updating.
