function vim --wraps vim --description 'vim, reopening the kitty-restored session for this window'
    if set -q KITTY_WINDOW_ID
        set -l session (kitty @ ls --match id:$KITTY_WINDOW_ID 2>/dev/null | jq -r '.[].tabs[].windows[].user_vars.vim_session // empty')
        if test -n "$session" -a -f "$session"
            command vim -S $session
            return
        end
    end
    command vim $argv
end
