# The rule-path-hook

A `PostToolUse` hook (`.mise/tasks/rule-path-hook`) that makes `paths:`-scoped
rules fire when the matching file is touched through **Bash, Write or Edit**,
not only through the Read tool. Wired in `.claude/settings.json` with matcher
`Bash|Write|Edit|MultiEdit`; selftest `mise run rule-path-hook-selftest`.

## Why it exists (measured 2026-10-09)

Claude Code injects a scoped rule only when the **Read tool** opens a matching
file. A sweep of every transcript on this machine (366 main + 986 subagent,
2026-09-01 → 10-09, structured tool-call fields only) found:

| cut | rule-matching touches via Read/Edit/Write | via Bash | Bash share |
|---|---|---|---|
| main sessions | 210 | 3,744 | **95%** |
| subagents | 4,355 | 9,582 | 69% |
| auto-mode sessions | 708 | 2,747 | 80% |
| first half (to 09-19) | 2,456 | 4,282 | 64% |
| second half | 2,109 | 9,044 | **81%** |

- Bash fired a scoped rule **0 times in ~5,000 first touches**. Edit and Write
  with no adjacent Read: 0 of 7 isolated cases. Only Read fires.
- Overall 38,809 Bash calls vs 3,893 Read calls; the Grep and Glob tools were
  used 0 times. Edit calls fell from 1,095 to 411 between the two halves.
- Per rule, the miss rate (sessions that touched a guarded file and never got
  the rule) is 67–98%: `tunables` 90%, `testing` 76%, `graph` 73%,
  `gdscript-pitfalls` 67%, `design-doc-lifecycle` 97%, `arrow-looks` 98%.
- Main sessions are Bash-first with or without auto mode (94% non-auto, 98%
  auto); auto mode mainly moves subagents (67% → 74%).
- Subagents in worktrees DO receive scoped rules (139 of 182 with a native
  touch), so `claudeMdExcludes` is not suppressing them; a worktree Read fires
  less reliably than a root Read (51% vs 80% isolated).
- The native mechanism injects once per session per rule (2% of pairs repeat,
  after compaction).

So the scoped tier — 38 rules, 243KB of curated gotchas — was reaching roughly
a quarter of the sessions it was written for, and the share was falling.
Script and full per-rule table: the sweep lived in the session scratchpad; the
method is reproducible from the description in `docs/domain/breadcrules.md`.

## What the hook does

1. Reads the `PostToolUse` payload. For Bash, strips heredoc bodies (briefs and
   issue bodies quote paths constantly — the 5–10× overcount breadcrules.md
   warns about), splits on shell operators, tracks a leading `cd X`, and keeps
   every token that resolves to an **existing file inside the project** or is
   an output-redirect target (a from-scratch heredoc author). For Write/Edit it
   takes `file_path`.
2. Matches the repo-relative paths against every scoped rule's `paths:` globs
   (`**` spans directories, `*`/`?` stay in a segment, `{a,b}` alternates — the
   same reading `rules-hygiene` uses, so a glob that passes hygiene fires here).
3. Prints each not-yet-fired rule's body as `additionalContext`, framed
   `Contents of <rule path> (project rule, path-scoped; loaded because this
   call touched <file>)`, and latches it in
   `<transcript dir>/rule-hook-state/<session>__<agent|main>.json` — once per
   rule per session, per subagent, exactly like the native mechanism.
4. Fail-closed: any exception is a silent exit 0 (same contract as
   `context-size-hook`; a broken JSON line on stdout breaks the next turn).

The project root is the nearest ancestor of the payload's `cwd` holding
`.claude/rules`, so a worktree uses its own rules copy.

## Costs and consequences

- A rule now costs what it says it costs. One `sed -n 1,40p
  systems/turn_manager.gd && head -3 test/unit/test_smoke.gd` injects five
  rules, **48KB**. That is the native price a Read would have paid, but it is
  now paid in the 95% of sessions that never paid it. The `expensive-scope` and
  `doc-in-a-rule` hygiene violations stopped being theoretical on the day this
  hook went live: shrink `testing.md`, `stats-system.md`,
  `skill-node-visuals.md`, `gdscript-pitfalls.md` first.
- A path that merely appears in a command (`echo systems/x.gd`, `git log --
  path`) counts as a touch if the file exists. Deliberate: cheaper than a
  per-command grammar, and the latch makes a false positive cost one injection.
- Native Read injection still happens on its own; a file both `cat`-ed and
  then Read pays twice at most, once. The hook does not read the transcript.
- Reading a rule file itself (a `cat` of the rule) does not inject it —
  only files a glob names.

## When it misbehaves

- A rule injects on every call → the latch dir is unwritable; the hook should
  have stayed silent (it persists before printing). Run the selftest.
- A rule never injects through Bash → the glob needs `**/` for a nested path
  (`*.gdextension` matches only at the root; hygiene reports it as dead-glob),
  or the command used a variable (`$F`) or `python3 -c` the parser skips.
- Changed the hook → `mise run rule-path-hook-selftest` (15 checks, ~1s).
