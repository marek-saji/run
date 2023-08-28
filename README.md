@saji/run
=========

📢 **No longer actively maintained.**

Task runner with interactive selection.

Run in directory with `tasks.tsv` or with `TASKS_TSV` environment variable set. Falls back to using npm scripts.
Use `tab` to select multiple tasks. Type to search. `Enter` to select.
Tasks TSV columns are:

1. Task name (e.g. Build)
2. Task colour, used if running task in parallel outside tmux (e.g. green)
3. Command to run (e.g. make)

You can specify “seq“ instead of colour, these tasks will run in sequence before all parallel tasks, in order chosen by the user.
To specify task presents use:

1. Present name (e.g. Build & Run)
2. A word “preset“
3. Names of the tasks to run, separated by “+” (e.g. Install + Build + Run)

Use `#`, `;` or `//` for comments.

<!-- above is an output of `run --help` -->

Code of conduct
---------------

We have adapted [Contributor Covenant](./CODE_OF_CONDUCT.md).


License
-------

Licensed under [ISC](./LICENSE).
