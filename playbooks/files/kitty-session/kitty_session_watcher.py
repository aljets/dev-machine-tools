"""Global kitty watcher that saves the session whenever the layout changes.

Saves are throttled so bursts of events (focus changes, command start/stop)
write the file once. The first event arms a single timer and later events
ride on it; re-arming on every event churned kitty's Cocoa timers, which
lined up with kitty crashing inside its timer code on macOS. A save that would contain no windows is skipped, so
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
import time
from collections import Counter
from functools import wraps
from typing import TYPE_CHECKING, Any, Callable

if TYPE_CHECKING:
    from kitty.boss import Boss
    from kitty.window import Window

SESSION = '~/.config/kitty/last_session.conf'
DEBOUNCE_SECONDS = 2.0
UNSERIALIZE_PREFIX = 'kitty-unserialize-data='
EVENT_LOG = os.path.expanduser('~/.cache/kitty-session-watcher.log')


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
events: Counter[str] = Counter()


def counted(handler: Callable[..., None]) -> Callable[..., None]:
    @wraps(handler)
    def wrapper(*args: Any) -> None:
        events[handler.__name__] += 1
        handler(*args)
    return wrapper


def flush_event_counts() -> None:
    if not events:
        return
    counts = ' '.join(f'{name}={n}' for name, n in events.most_common())
    with open(EVENT_LOG, 'a') as f:
        f.write(f'{time.strftime("%Y-%m-%d %H:%M:%S")} {counts}\n')
    events.clear()


def save(boss: Boss) -> None:
    flush_event_counts()
    if any(True for _ in boss.all_windows):
        boss.save_as_session('--use-foreground-process', '--save-only', SESSION)
        rewrite_claude_windows(SESSION)


def schedule_save(boss: Boss) -> None:
    global pending_timer
    if quitting or pending_timer is not None:
        return
    from kitty.fast_data_types import add_timer

    def fire(timer_id: int | None) -> None:
        global pending_timer
        pending_timer = None
        save(boss)

    events['timer_added'] += 1
    pending_timer = add_timer(fire, DEBOUNCE_SECONDS, False)


@counted
def on_quit(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    global quitting
    if data.get('confirmed'):
        quitting = True
        save(boss)


last_tab_layout: tuple[Any, ...] = ()


@counted
def on_tab_bar_dirty(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    # Fires on every title change too, and claude retitles constantly while
    # working. Only tab creation, removal, moves and switches matter here.
    global last_tab_layout
    layout = tuple((tm.os_window_id, tuple(t.id for t in tm.tabs), tm.active_tab_idx)
                   for tm in boss.all_tab_managers)
    if layout != last_tab_layout:
        last_tab_layout = layout
        schedule_save(boss)


@counted
def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


@counted
def on_close(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


@counted
def on_resize(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


@counted
def on_cmd_startstop(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


@counted
def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    schedule_save(boss)


if __name__ == '__main__':
    rewrite_claude_windows(sys.argv[1] if len(sys.argv) > 1 else SESSION)
