---
name: handoff
description: Close out a session durably — sweep every decision made in conversation into its permanent home (issue, design doc, rule file, code), commit, and only then decide whether a continuation file is warranted. Use when the user says "handoff", "wrap this up", "EOD", "persist this", "this session is getting heavy", or when a long session is about to be continued in a fresh context.
---

# Handoff

A long session accumulates decisions that exist **only in the transcript**.
When the context window turns over, they are gone — and the next session
re-litigates them, or worse, silently decides differently.

This skill's job is the **sweep**: every decision made in conversation gets
routed to a durable home. Writing a handoff file is the *optional* second step,
not the point.

> **The sweep is the work. The file is a maybe.**
> A handoff file exists for exactly one reason: to carry *unfinished* context
> forward. If the work is concluded, there is nothing to carry — the sweep is
> the whole job and no file gets written. That is the common case at EOD or when
> an issue wraps up.

## 0. Emergency path — retiring mid-flight under a stop or a blown budget

The sections below (1–5) are the **leisurely EOD sweep** — thorough, patient,
and assumes you have room to do it right. If you are being retired *because*
you blew a stop, a context budget, or a turn/time budget (see `drone`'s
context-budget section), that sweep is the wrong tool. Loading it and then
not following it — the `loot-offer` failure: `git status` twice, a file read,
a grep, a `rebase --continue`, a second `mise run check` — is worse than
skipping it, because it looks like compliance while burning exactly the
turns you no longer have.

**The emergency path is three turns, no more:**

1. **Commit what exists.** `git add <owned paths>` (explicit paths, never
   `-A`) and commit, even if the unit is incomplete. A `wip(...)` commit that
   states plainly what's missing beats an uncommitted worktree, which is
   lost work outright.
2. **Write the report** — the same terse format `drone` always uses
   (`BRANCH:`/`FILES:`/`TESTS:`/`DID:`/`NOTES:`), with `NOTES:` stating
   exactly what's unfinished. Skip the sweep, skip routing decisions (§2),
   skip writing a handoff file. If one fact is genuinely load-bearing for
   whoever picks this up, one line on the issue (`gh issue comment`) is
   allowed — one line, not a sweep.
3. **Send it and stop.** `SendMessage` (Claude Code) or your final report
   (opencode) to whoever is waiting — the orchestrator, or `relief` if you
   were redirected there. Do not keep working after it's sent.

That's the whole budget. If you find yourself running a test, editing a doc,
or re-reading a file after deciding to retire, that is the `loot-offer`
failure recurring — stop, go back to step 2, send what you have.

## 1. Sweep — find what only exists in the transcript

Walk the session and list every item that is (a) a decision, a discovered
constraint, or a correction, and (b) **not yet written anywhere durable.**

Hunt specifically for:

- **Forks the user settled in conversation.** The highest-value and
  most-frequently-lost category.
- **Claims that turned out false.** "X is unbuilt" that was actually built two
  commits ago; a previous agent's report of work it did not do. Corrections are
  as durable-worthy as decisions.
- **Rejected branches, with the reason.** A rejected option whose *reasoning* is
  lost gets re-proposed next session. Record the why, not just the no.
- **Gotchas hit while working.** Anything that cost you a debugging loop.
- **Numbers derived mid-session** — arithmetic on pinned values, measured
  timings, counts read off the code.

If the item is already in a commit, an issue, a design doc, or a rule file:
skip it. Do not restate what the repo already records.

## 2. Route each item to its home

| Item | Home |
|---|---|
| Game-design decision, settled fork | `docs/design/` — or a comment on the owning issue |
| Design fork still *open* | Issue body/comment, with the fork written down as a fork |
| Engineering gotcha, < ~200 tokens | Inline in the relevant `.claude/rules/<module>.md` |
| Larger engineering context | `docs/domain/<topic>.md` (+ a breadcrule if it must be always-on) |
| Work state, next steps, sequencing | The issue — that is what issues are for |
| Anything that is code | A commit. Obviously — but say it, because it gets skipped |
| Un-actioned discovery with no owner | **File an issue.** An orphan thread in a doc is a thread that dies |

**Never let a decision live only in a handoff file.** A handoff file is a
pointer and a task ledger; it is not a home. If deleting it would lose
information, the sweep is not finished.

Update `.claude/rules/*` in the same pass when the change invalidates one. A
stale rule is worse than no rule.

## 3. Commit

Commit the sweep before anything else. If the session dies mid-handoff, the
durable writes must already be safe.

Use the repo's normal conventions — `Closes #<n>` where an issue is actually
resolved.

## 4. Decide: continuation file, or done?

Ask the question explicitly:

**Is there unfinished work whose context a fresh session would need and cannot
reconstruct from the issues alone?**

- **No** → stop. Report what was swept and where it went. No file.
- **Yes** → write exactly one file at **`docs/handoffs/<topic>.md`**.

A continuation file earns its existence when the work spans several issues and
the *relationship between them* is the thing that would be lost — a dispatch
order, a coupling between two forks, a set of live numbers the next session
needs in hand. A single-issue continuation almost never needs one; put it in
the issue.

## 5. Handoff file shape

Location is `docs/handoffs/<topic>.md`, committed. Not the repo root — the two
files that prompted this skill (`HANDOFF_spell_tests.md`,
`SKILLNODE_EMBLEM_HANDOFF.md`) sat at the root, went stale, and one of them
carried two open questions that were never filed for months.

Keep it to:

- **State** — the commit it is written against, and what is authoritative
  (usually: a design doc and the issues, not this file).
- **Open forks, ordered by what is worth taking first**, each with its issue
  number. Note couplings — "settling A forces reversing B" is the single most
  valuable line in a handoff.
- **Ready to dispatch** — what is already in `Ready`, and any sequencing facts.
- **Live numbers** the next session needs in hand.

And the two rules that keep the file honest:

- **It points, it does not hold.** Every decision in it must also exist in its
  real home. The file is an index.
- **It says when to delete it.** End with the condition — "delete once #X and
  #Y land". Then actually delete it when that is true; a spent handoff still in
  the tree is a trap for the next agent.

## What this is not

- **Not a substitute for issue hygiene.** If a fork belongs on an issue, it goes
  on the issue, and the handoff merely points at it.
- **Not a transcript summary.** Nobody reads a narrative of the session. Record
  outcomes, not the path to them.
- **Not automatic.** If the sweep finds nothing un-persisted, say so and stop.
  That is a good result, not a failed run.
- **Not the entry half.** This skill is how a session closes out — including
  a one-shot continuation file per §5. Picking up a swarm that is still
  *running* — drones in flight, worktrees open, merges pending — is
  `relief`'s job (`.claude/skills/relief/SKILL.md`). Relief reads a
  *continuous* briefing kept live at `docs/handoffs/swarm-<date>.md`,
  updated by `swarm` on every dispatch/report/merge — not a one-shot file
  written at the end. Same directory and lifecycle rules as §5
  (`.claude/rules/handoffs.md`), a different cadence.
