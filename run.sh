#!/bin/sh
# shellcheck disable=SC1111
set -e

print_help ()
{
    printf "Task runner with interactive selection.\n\n"
    printf "Run in directory with tasks.tsv or with TASKS_TSV environment variable set. Falls back to using npm scripts.\n"
    printf "Run [tab] to select multiple tasks. Type to search. Enter to select.\n"
    printf "Tasks TSV columns are:\n"
    {
        printf "Task name (e.g. Build)\n"
        printf "Task colour, or “seq“ if it’s ment to run sequentially, before all parallel tasks. (e.g. green)\n"
        printf "Command to run, or if starts with “+“, a “+“–separated list of task names to run. (e.g. +Test+Build)\n"
    } | nl
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
            npm run |
                grep -E '^  (  )?[^ ]' |
                awk -vRS='(^|\n)  \\<' -vORS='\n' -vFS='\n    \\<' '$1 { print $1 "\twhite\tnpm run " $1 " # " $2 }'
        )"
    fi
fi

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



cmds_len="$( echo "$TASKS_TSV" | wc -l )"
choice="$(
    printf "%s\n" "$TASKS_TSV" |
        fzf --multi --no-sort --cycle \
            --layout=reverse --no-info --height=$(( cmds_len + 2 )) \
            --with-nth=1 --delimiter="\t" \
            --preview="echo {} | cut -f3-" \
            --preview-window=:wrap
)"

supertasks_choice_ids="$(
    echo "$choice" |
        awk -F'\t' '{ if (substr($3, 1, 1) == "+") print $3 }' |
        sed 's/\s*+\s*/\n/g' |
        awk '$0 && !seen[$0]++'
)"
choice="$( echo "$choice" | awk -F'\t' 'substr($3, 1, 1) != "+"' )"
if [ -n "$supertasks_choice_ids" ]
then
    choice="$(
        {
            echo "$choice"
            echo "$supertasks_choice_ids" |
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
fi

if [ -n "$choice_seq" ]
then
    printf "%s\n" "$choice_seq" |
        while read -r line
        do
            id="$( get_id "$line" )"
            cmd="$( get_cmd "$line" )"
            printf "\n%s\n" "$id"
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
        get_cmd "$rest_lines" |
            while read -r cmd
            do
                tmux split-window -d -t "$TMUX_PANE" -h \
                    "$SHELL" -$-xc "$cmd || exec $SHELL -l"
            done
        tmux select-layout -t "$TMUX_PANE" -E
        tmux resize-pane -t "$TMUX_PANE" -y 5
    fi

    exec_cmd "$first_line"
fi
