"""Global kitty watcher that saves the session whenever the layout changes.

Saves are debounced so bursts of events (focus changes, command start/stop)
write the file once. A save that would contain no windows is skipped, so
closing the last window keeps the previous session.

Claude windows are saved as plain `claude` so the fish wrapper resumes them
by their claude_session user var. Saving the foreground process verbatim
would replay whatever started it, e.g. `claude --resume` with no id, which
opens the picker. Run this file directly to apply that rewrite to the saved
session outside kitty.
"""
from __future__ import annotations

import json
import os
import shlex
import sys
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from kitty.boss import Boss
    from kitty.window import Window

SESSION = '~/.config/kitty/last_session.conf'
DEBOUNCE_SECONDS = 2.0
UNSERIALIZE_PREFIX = 'kitty-unserialize-data='


def is_claude(cmd: str | list[str]) -> bool:
    argv = shlex.split(cmd) if isinstance(cmd, str) else cmd
    return bool(argv) and (os.path.basename(argv[0]) == 'claude' or '/claude/versions/' in argv[0])


def resume_claude_by_session_var(line: str) -> str:
    if not line.startswith('launch ') or '--var=claude_session=' not in line:
        return line
    args = shlex.split(line)
    for i, arg in enumerate(args):
        if arg.startswith(UNSERIALIZE_PREFIX):
            data = json.loads(arg[len(UNSERIALIZE_PREFIX):])
            cmd = data.get('cmd_at_shell_startup')
            if cmd and is_claude(cmd):
                data['cmd_at_shell_startup'] = 'claude'
                args[i] = UNSERIALIZE_PREFIX + json.dumps(data)
                return shlex.join(args)
    return line


def rewrite_claude_windows(path: str) -> None:
    path = os.path.expanduser(path)
    with open(path) as f:
        lines = f.read().split('\n')
    rewritten = [resume_claude_by_session_var(line) for line in lines]
    if rewritten != lines:
        with open(path, 'w') as f:
            f.write('\n'.join(rewritten))

pending_timer: int | None = None
quitting = False


def save(boss: Boss) -> None:
    if any(True for _ in boss.all_windows):
        boss.save_as_session('--use-foreground-process', '--save-only', SESSION)
        rewrite_claude_windows(SESSION)


def schedule_save(boss: Boss) -> None:
    global pending_timer
    if quitting:
        return
    from kitty.fast_data_types import add_timer, remove_timer

    if pending_timer is not None:
        remove_timer(pending_timer)

    def fire(timer_id: int | None) -> None:
        global pending_timer
        pending_timer = None
        save(boss)

    pending_timer = add_timer(fire, DEBOUNCE_SECONDS, False)


def on_quit(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    global quitting
    if data.get('confirmed'):
        quitting = True
        save(boss)


def on_tab_bar_dirty(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


def on_close(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


def on_resize(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


def on_cmd_startstop(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


if __name__ == '__main__':
    rewrite_claude_windows(sys.argv[1] if len(sys.argv) > 1 else SESSION)
