#!/bin/sh
# shellcheck disable=SC1111
set -e

# TODO Accept file as an argument -- either TSV or package.json
# TODO Use TASKS_TSV only if tasks.tsv is not present

print_help ()
{
    printf "Task runner with interactive selection.\n\n"
    printf "Run in directory with \`tasks.tsv\` or with \`TASKS_TSV\` environment variable set. Falls back to using npm scripts.\n"
    printf "Use \`tab\` to select multiple tasks. Type to search. \`Enter\` to select.\n"
    printf "Tasks TSV columns are:\n\n"
    {
        printf "Task name (e.g. Build)\n"
        printf "Task colour, used if running task in parallel outside tmux (e.g. green)\n"
        printf "Command to run (e.g. make)\n"
    } | nl -w1 -s'. '
    printf "\n"
    printf "You can specify “seq“ instead of colour, these tasks will run in sequence before all parallel tasks, in order chosen by the user.\n"
    printf "To specify task presents use:\n\n"
    {
        printf "Present name (e.g. Build & Run)\n"
        printf "A word “preset“\n"
        printf "Names of the tasks to run, separated by “+” (e.g. Install + Build + Run)\n"
    } | nl -w1 -s'. '
    printf "\n"
    printf "Use \`#\`, \`;\` or \`//\` for comments.\n"
}

if [ "$1" = '--help' ] || [ "$1" = '-h' ]
then
    print_help
    exit 0
fi

if ! command -v fzf >/dev/null
then
    echo "ERROR: 'fzf' not found in \$PATH." 1>&2
    exit 69
fi

TASKS_FILE="./tasks.tsv"

if [ -z "$TASKS_TSV" ]
then
    if [ -r "$TASKS_FILE" ]
    then
        TASKS_TSV="$( cat "$TASKS_FILE" )"
    else
        TASKS_TSV="$(
            # TODO Better preview
            npm run |
                grep -E '^  (  )?[^ ]' |
                awk -vRS='(^|\n)  \\<' -vORS='\n' -vFS='\n    \\<' '$1 { print $1 "\twhite\tnpm run " $1 " # " $2 }'
        )"
    fi
fi

TASKS_TSV="$( echo "$TASKS_TSV" | grep -Ev '^\s*(#|;|//|$)' )"

if [ -z "$TASKS_TSV" ]
then
    print_help
    echo
    echo "ERROR: No tasks found." 1>&2
    exit 69
fi

get_line ()
{
    lines="$1"
    id="$2"

    printf "%s\n" "$lines" | awk -F'\t' -v id="$id" '$1 == id'
}

get_id ()
{
    line="$1"

    printf "%s\n" "$line" | awk -F'\t' '{ print $1 }'
}

get_colour ()
{
    line="$1"

    printf "%s\n" "$line" | awk -F'\t' '{ print $2 }' # TODO "seq" → ""
}

get_cmd ()
{
    line="$1"

    printf "%s\n" "$line" | awk -F'\t' '{ print $3 }'
}

get_cmd_by_id ()
{
    lines="$1"
    id="$2"

    printf "%s\n" "$lines" | awk -F'\t' -vid="$id" '{ if ($1 == id) { print $3 } }'
}

exec_cmd ()
{
    line="$1"
    cmd="$( get_cmd "$line" )"

    "$SHELL" -$-xc "$cmd"
}


# TODO Match each arg separately $1, $2… fallback only if some don’t match
query="$1"
choice="$( get_line "$TASKS_TSV" "$query" )"
if [ -z "$choice" ]
then
    choice="$(
        cmds_len="$( echo "$TASKS_TSV" | wc -l )"
        cat="$( command -v pygmentize || : )"
        if [ -n "$cat" ]
        then
            cat="$cat -l sh"
        else
            cat="cat"
        fi
        printf "%s\n" "$TASKS_TSV" |
            fzf --multi --no-sort --cycle \
                --query="$*" --select-1 \
                --layout=reverse --no-info --height=$(( cmds_len + 2 )) \
                --with-nth=1 --delimiter="\t" \
                --preview="echo {} | cut -f3- | $cat" \
                --preview-window=:wrap
    )"
fi

preset_choice_ids="$(
    echo "$choice" |
        awk -F'\t' '$2 == "preset" { print $3 }' |
        sed 's/\s*+\s*/\n/g' |
        awk '$0 && !seen[$0]++'
)"
choice="$( echo "$choice" | awk -F'\t' '$2 != "preset"')"
if [ -n "$preset_choice_ids" ]
then
    # FIXME Error on unknown tags
    choice="$(
        {
            echo "$choice"
            echo "$preset_choice_ids" |
                while read -r id
                do
                    get_line "$TASKS_TSV" "$id"
                done
        } | awk '$0 && !seen[$0]++'
    )"
fi

seq_regexp='^[^	]*	seq	'
choice_seq="$( echo "$choice" | grep -E "$seq_regexp" || : )"
choice="$( echo "$choice" | grep -vE "$seq_regexp" || : )"

first_line="$( printf "%s\n" "$choice" | head -n1 )"
rest_lines="$( printf "%s\n" "$choice" | tail -n+2 )"

if [ -n "$rest_lines" ] && [ -n "$TMUX_PANE" ]
then
    tmux resize-pane -t "$TMUX_PANE" -y 5
    if [ -n "$rest_lines" ]
    then
        # Select next pane if there are any non–sequencial tasks
        tmux select-pane -t :.+
    fi

fi

if [ -n "$choice_seq" ]
then
    printf "%s\n" "$choice_seq" |
        while read -r line
        do
            id="$( get_id "$line" )"
            cmd="$( get_cmd "$line" )"
            printf "\n%s\n" "$id"
            if [ "$TMUX_PANE" ]
            then
                printf "\033]2;%s…\033\\" "$id"
            fi
            exec_cmd "$line"
        done
fi

if [ -n "$rest_lines" ] && [ -z "$TMUX_PANE" ]
then
    names="$( printf "%s\n" "$choice" | cut -f1 | paste -sd, )"
    colours="$( printf "%s\n" "$choice" | cut -f2 | paste -sd, )"
    set --
    for id in $( printf "%s\n" "$choice" | cut -f1 )
    do
        set -- "$@" "$( get_cmd_by_id "$choice" "$id" )"
    done

    # FIXME Install as a dependency
    npx concurrently \
        --kill-others \
        --names="$names" \
        --prefix-colors="$colours" \
        -- \
        "$@"
else
    if [ -n "$rest_lines" ]
    then
        printf "%s" "$rest_lines" |
            while read -r line
            do
                id="$( get_id "$line" )"
                cmd="$( get_cmd "$line" )"
                tmux split-window -d -t "$TMUX_PANE" -c "$PWD" -h \
                    "$SHELL" -$-xc "printf \"\033]2;%s\033\\\\\" '$id' ; $cmd || exec $SHELL -l"
            done
        tmux select-layout -t "$TMUX_PANE" -E || :
        tmux resize-pane -t "$TMUX_PANE" -y 5
    fi

    first_line_id="$( get_id "$first_line" )"
    printf "\033]2;%s\033\\" "$first_line_id"
    exec_cmd "$first_line"
fi
