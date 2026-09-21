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
