# Handoff — charter

The design behind `.claude/skills/handoff/SKILL.md`. The file is derived from
this; change the wish here, then re-derive. See [README](README.md) for the
protocol.

## What handoff is for

Closing a session durably. A long session accumulates decisions that exist
only in the transcript; when the context turns over they are gone, and the
next session re-litigates them or silently decides differently. Handoff's
job is the **sweep** — every such item routed to a durable home — and only
then, maybe, a continuation file. It is the exit half; `relief` and
[`pickup`](pickup.md) are entry halves.

## The cost model

A decision lost at turnover costs a whole re-litigation, or a wrong turn
nobody notices; the sweep costs a few writes and one commit. A handoff file
costs something too: every later agent that opens a stale one is misled, so
the file is the exception, earned only by context the issues cannot carry,
and it is deleted the moment it is spent. When the session is retiring
because a budget is already blown, the sweep's own cost is the danger, so a
three-turn path replaces it.

## Laws

1. **The sweep is the work; the file is a maybe.** A continuation file
   exists only to carry *unfinished* context forward. Concluded work gets
   the sweep and no file — the common case at EOD or an issue's end.
   *Why:* a file written by habit is a second, staler copy of what the repo
   already says.
2. **Retiring mid-flight is three turns, no more.** Under a stop or a blown
   context, turn or time budget: commit what exists (explicit paths, a
   `wip(...)` commit stating what is missing), write the terse report
   (`BRANCH:`/`FILES:`/`TESTS:`/`DID:`/`NOTES:`, `NOTES:` saying what is
   unfinished; at most one load-bearing line on the issue), send it to
   whoever is waiting and stop. No sweep, no routing, no file, no test run,
   no re-read. *Why:* loading the full sweep and then not following it
   burns exactly the turns the session no longer has while looking like
   compliance (corpus: `loot-offer`). Relies on
   [drone](drone.md) law 12.
3. **Sweep what exists only in the transcript.** Hunt: forks the owner
   settled (the most valuable, most often lost), claims that turned out
   false (corrections are as durable-worthy as decisions), rejected
   branches *with the reason*, gotchas that cost a debugging loop, numbers
   derived mid-session. Skip anything a commit, issue, design doc or rule
   already holds. *Why:* a rejected option whose reasoning is lost is
   re-proposed next session; a restated fact is a mirror that rots.
4. **Route each item to its home.** Settled game-design fork →
   `docs/design/` or the owning issue; open fork → the issue, written as a
   fork; engineering gotcha under ~200 tokens → inline in
   `.claude/rules/<module>.md`; larger engineering context →
   `docs/domain/<topic>.md` (+ a breadcrule if always-on); work state and
   next steps → the issue; code → a commit (said, because it gets
   skipped); an un-actioned discovery with no owner → fixed, by the session
   or one subagent briefed from the hot context — only a real fork or a
   multi-unit job is filed, to `Intake` (`docs/domain/session-report.md` →
   *The follow-up rule*). A change to a skill or agent file goes through
   `/charter` ([charter](charter.md) law 1). *Why:* an orphan thread in a
   doc dies.
5. **A decision never lives only in a handoff file.** If deleting the file
   would lose information, the sweep is not finished. *Why:* the file is a
   pointer and a task ledger, not a home.
6. **A rule the sweep invalidates is updated in the same pass.** *Why:* a
   stale rule is worse than none.
7. **Commit the sweep before anything else**, by the repo's conventions
   (`Closes #<n>` where an issue is resolved). *Why:* if the session dies
   mid-handoff, the durable writes are already safe.
8. **Ask explicitly whether a file is warranted.** "Is there unfinished
   work whose context a fresh session would need and cannot reconstruct
   from the issues alone?" No → stop and report what was swept where. Yes →
   exactly one file at `docs/handoffs/<topic>.md`. *Why:* a file earns its
   place when the work spans several issues and their relationship — a
   dispatch order, a coupling between forks, live numbers — is what would
   be lost; a single-issue continuation goes on the issue.
9. **The file's shape: State, Open forks, Ready to dispatch, Live numbers.**
   State is the commit it is written against and what is authoritative
   (usually a design doc and the issues). Open forks are ordered by what to
   take first, each with its issue number, couplings named ("settling A
   forces reversing B" is the most valuable line). It points, it does not
   hold; it ends with its delete condition. Never at the repo root. *Why:*
   two root-level handoffs went stale and one carried two unfiled open
   questions for months.
10. **What it is not.** Not a substitute for issue hygiene; not a
    transcript summary (outcomes, not the path); not automatic — a sweep
    that finds nothing says so and stops, a good result; not the entry
    half — a swarm still running is `relief`'s, read from the live
    `docs/handoffs/swarm-<date>-<HHMM>.md` ledger (`mise run ledger --
    show`), a different, gitignored lifecycle.
11. **A file meant to be resumed carries its own resume instruction, and
    the prompt handed to the owner is one line.** When the work continues
    in a fresh session, the file names the skill the work runs under (a
    `swarmify` design talk, a `warp`) and tells the next session to scour
    the open issues it names and the codebase before acting, since the file
    may be stale or wrong; the closing report's last line is the resume
    prompt, exactly `/pickup docs/handoffs/<topic>.md`. Owner, 2026-10-19:
    *"Handoff so i can resume this tomorrow with 1 good prompt. Also the
    prompt should include instructing to scour open issues and codebase
    etc"*. *Why:* the owner was re-typing the resume context by hand; one
    line in, the instructions travel with the file. This is the resume half
    of [swarmify](swarmify.md) law 39's close; [pickup](pickup.md) law 7
    reads it.
12. **`docs/handoffs/` holds files, not working directories; a spent file
    is deleted.** Tracked: `docs/handoffs/<topic>.md` continuation files
    and the swarm-train `whip-report-<date>.md` morning reports. Ignored
    (`.gitignore`): `swarm-*.md` ledgers and `swarm-*.inbox/`, `whip-2*`,
    `archive/`, `.whip.lock`. A handoff never commits scratch — scripts,
    work directories of non-`.md` files — those go to the session's
    scratchpad; one file per topic is the pass's tentative call
    (2026-11-10), since `.md` digest directories (audit, cleanup review)
    were committed on purpose. The file is deleted (`git rm`, in the commit) by whichever
    session meets its delete condition, normally the one that picked it up
    ([pickup](pickup.md) law 8), and a sweep that finds a spent file in
    `docs/handoffs/` deletes it. *Why:* handoff clutter reached git twice —
    owner, 2026-10-17: *"do something about the handoffs in git. update
    gitignore?"* and *"docs/handoffs/board-sweep-2026-10-16.pending/ is
    there something in there?"* (a tracked directory of work files and a
    shell script); a spent file still in the tree is a trap.

## Foreign laws

- [drone](drone.md) law 12 — law 2 is how a drone told to stop retires.
- [charter](charter.md) law 1 — law 4 routes a skill or agent change
  through `/charter`.
- [charter](charter.md) law 17 — the *Frontmatter* description is stated
  plain; the builder writes it single-quoted.
- [swarmify](swarmify.md) law 39 — a design pass's close hands its resume
  half to law 11.
- [pickup](pickup.md) law 7 — law 11 writes the file and instruction it
  reads.
- [pickup](pickup.md) law 8 — law 12's deletion on consume is executed
  there.

## Frontmatter

`name: handoff`. `description:`, verbatim (the builder quotes it, [charter](charter.md) law 17):

> Close out a session durably — sweep every decision made in conversation into its permanent home (issue, design doc, rule file, code), commit, and only then decide whether a continuation file is warranted; a continued session gets a one-line `/pickup <file>` resume prompt. Use when the user says "handoff", "wrap this up", "EOD", "persist this", "so i can resume this tomorrow", "this session is getting heavy", or when a long session is about to be continued in a fresh context.

## What the skill file must not contain

Dates, issue numbers, owner quotes, the incidents (`loot-offer`, the
root-level files, the pending directory), the reasoning behind each law.
It carries the steps, the routing table, the file shape and the resume
line.

## Revisit when

- A charter or skill file is edited by a `/handoff` sweep without
  `/charter` — law 4 is not being followed, or the sweep should spawn
  `/charter`'s steps.
- Spent files keep surviving in `docs/handoffs/` — law 12's "whoever meets
  the condition" is too diffuse; a `mise` hygiene check that lists files
  whose stated condition names only closed issues would make it mechanical.
- The owner still pastes context into fresh sessions after law 11 lands —
  the resume line is not reaching them (pickup's trigger, or the report's
  last line).

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-09-14 | `loot-offer` (drone corpus) | loaded `handoff` after three stop requests, then ran `check`, `rebase --continue` and the full suite instead of handing off | 2 |
| 2026-10-14 → 10-19 | scans `docs/corpus/2026-11-09-skill-candidates-{a,b}.md` | design-talk closing ritual typed by hand in 14 sessions across two windows ("Start filing what we settled. And handoff for the remaining discussion, I'm off to bed"; "Handoff so i can resume this tomorrow with 1 good prompt…") | 11 |
| 2026-10-17 | 57fc7fd0, 89d7138a (scan b) | owner asked twice about handoff files in git; `board-sweep-2026-10-16.pending/` (work dirs + a `.sh`) is tracked; `swarmify-charter.md` still in the tree with its delete condition (#903–#905) met | 12 |
