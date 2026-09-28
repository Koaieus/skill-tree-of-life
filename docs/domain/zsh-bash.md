# The Bash tool runs zsh — quote globs, never lead a word with `=`

**The two trips**, measured over 317 session transcripts (2026-08-23 → 09-21,
16,791 Bash calls): 393 failures, 216 transcripts affected, ~1 in every 42
calls — every one of them a round-trip bought for nothing.

| Signature | Count | Cause | Fix |
|---|---|---|---|
| `no matches found: --include=*.gd` | 367 (93%) | zsh `NOMATCH`: an unquoted glob that matches nothing in cwd aborts the *whole* command | `--include='*.gd'` — quote every glob you mean literally |
| `===== not found` | 26 | zsh expands a word starting with `=` as `=cmd` (path lookup) | never start a word with `=`; `echo "----"` for separators |

Both fail loud and early, so they never corrupt anything — they only cost a
turn. `grep -r … --include='*.gd'`, `find . -name '*.tscn'`, `ls '*.uid'`.

## The shell carries the owner's interactive aliases

The Bash tool's zsh is a snapshot of the owner's interactive shell, aliases
included: `ls` → `eza`, `cat` → `bat --paging=never --style=plain`. Two
consequences seen in transcripts:

- **Bare `ls` hung forever** (a live session, 2026-09-28, and likely a 23.8 h
  orphan earlier): with no path argument and a non-tty stdin, `eza` reads paths
  from stdin until EOF, and the tool's stdin is a socket that never closes.
  Fixed in the owner's dotfiles (the aliases now close stdin), but a session
  whose snapshot predates the fix still carries the old alias.
- **`ls` flags are eza's, not GNU's**: `ls -t <dir>` fails with
  `invalid value … for '--time <FIELD>'`.

When you mean the real tool, say so: `command ls -1t <dir>`, `command cat`.
