"""Global kitty watcher that saves the session whenever the layout changes.

Saves are debounced so bursts of events (focus changes, command start/stop)
write the file once. A save that would contain no windows is skipped, so
closing the last window keeps the previous session.
"""
from typing import Any

from kitty.boss import Boss
from kitty.fast_data_types import add_timer, remove_timer
from kitty.window import Window

SESSION = '~/.config/kitty/last_session.conf'
DEBOUNCE_SECONDS = 2.0

pending_timer: int | None = None
quitting = False


def save(boss: Boss) -> None:
    if any(True for _ in boss.all_windows):
        boss.save_as_session('--use-foreground-process', '--save-only', SESSION)


def schedule_save(boss: Boss) -> None:
    global pending_timer
    if quitting:
        return
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
