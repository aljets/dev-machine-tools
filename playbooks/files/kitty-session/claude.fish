function claude --wraps claude
    if test (count $argv) -eq 0; and set -q KITTY_WINDOW_ID
        set -l id (kitty @ ls --match id:$KITTY_WINDOW_ID 2>/dev/null | jq -r '.[].tabs[].windows[].user_vars.claude_session // empty')
        if test -n "$id"; and test -n "$(path filter ~/.claude/projects/*/$id.jsonl)"
            command claude --resume $id
            return
        end
    end
    command claude $argv
end
