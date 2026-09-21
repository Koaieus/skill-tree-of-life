# Git and shell gotchas in a shared checkout

Small, each learned the hard way, none derivable from the code.

## `git push origin master` publishes everyone's landings

Every session fast-forwards the one local `master` as its merge gate, so local
`master` is the union of all landings and the ref you push is that union — a
held-back commit escapes under someone else's push (three instances in one
evening, 2026-09-08). Push an explicit sha (`git push origin <sha>:master`) when
it matters, and never cite an `origin/` ref you did not just fetch.

## `--amend` in the main checkout is fine — and how to repair the rare collision

Owner, 2026-08-21: *"usually amending is fine, it's rare it collides."* When it
does (a parallel session committed between your commit and your amend, so the
amend rewrote *theirs*): `git log --oneline -1` shows their subject; `git reset
--soft <their-sha>` from `git reflog` restores their exact sha and touches no
working file, then re-commit your own paths on top. Never `--hard`.

## `pkill -f <pattern>` kills the tool's own shell

The pattern is in your own command line, so the shell dies (exit 144) and
nothing after the `pkill` runs — a revert once never ran. Kill by PID captured
at spawn (`$!`), use `mise run godot-reap`, or make the `pkill` the last
command with nothing after it.

## Always `git -C <path>`, never the shell cwd

A reverted cwd once turned a `git checkout --` into a discard of a peer's
unstaged WIP in the main checkout; unstaged is unrecoverable. Explicit-path
`git add`, never `-A`.
