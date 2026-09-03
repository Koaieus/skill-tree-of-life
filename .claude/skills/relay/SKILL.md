---
name: relay
description: Orchestrate a chain of Ready issues as one Sonnet `warp` drone each, with you as advisor and sole merge gate — read almost nothing yourself, front-load each brief with discovered context, gate every merge, and run the full suite once at the end. Use when the user names several issues to land in sequence ("#A → #B → #C as Sonnet warps"), says "relay these", or asks you to orchestrate warps without doing the implementation. Prefer this over `swarm` when the issues are already Ready and merges must serialise.
---

# Relay

One `warp` drone per issue. You never implement, rarely read source, and
exist to do three things a drone cannot: **decide design forks**, **gate
merges**, and **hold the serial merge token**.

Distinct from its neighbours: `swarm` splits ONE body of work across parallel
drones sharing context; `warp` is the single-issue cycle a drone runs; `relay`
chains several independent issues with you as the only long-lived context.

Measured on a real run (2026-09-03, #737 → #727 → #746 → #736 → #743, five
landed in ~5h): orchestrator ended at **218k**, drones at 111k–222k each,
Sonnet reviewers at 69k/83k, one Haiku sweep at 33k.

## The loop

1. Read issue **titles** only, up front. Nothing else.
2. Resolve ordering: which issues touch the same files? One Haiku `Explore`
   answers that for the whole chain (see *Front-load the brief*).
3. Dispatch a Sonnet `general-purpose` drone per issue, backgrounded.
4. Answer its design forks. Approve or redirect.
5. Gate its merge. Review proportionally (below). Approve with conditions.
6. Close the issue **by hand**, with a landing comment carrying what was learned.
7. Full suite **once**, after the last merge — and baseline it first.

## The drone brief

Every brief carries these, verbatim. They are not boilerplate; each one was
earned by something going wrong.

- **`advisor` is forbidden.** It re-sends the drone's whole transcript to a
  second Opus. You are its advisor, via `SendMessage`.
- **You are not the merge gate.** Stop when green, report, wait.
- **Never poll a background task.** The harness wakes you. If a command seems
  to hang, *bisect it* — never retry with a longer timeout.
- **Never run the full suite** (you run it once, at the end). Cheap ladder:
  `check` → `test:one` → `test:dir`.
- **Never write to the main checkout.** Isolated worktree only.
- **Retire at 250k** — commit WIP, post a state comment on the issue, send
  three lines, stop.
- **Flag design forks BEFORE building**, with the fork stated and a recommendation.

That last rule earned its place four times in one run: a drone found that
GUT's JUnit export excludes `before_all`, so the obvious fix would not have
failed the suite; another found only one `VictoryCondition` existed, making
its issue's acceptance unsatisfiable as filed; another found Godot's
`ButtonGroup` commits its toggle *synchronously during native click
processing*, before any handler runs, so handler-level gating cannot work.
Each would have been a wasted implementation.

## Front-load the brief

**This is the highest-leverage thing you do.** A brief that costs you 60
seconds to write saves a drone a discovery sweep. Put in every brief:

- The **current master sha**, and the sha it will be based on.
- **Known pre-existing failures**, named, with "NOT yours, do not fix".
- The **file map** for its surface, if you already know it or can get it from
  one Haiku `Explore`.
- **Which house rules apply** (`.claude/rules/*`), named specifically.
- **What another drone is touching**, so it stays out of those files.
- **Recent commits worth `git show`-ing** that changed its surface.
- A **house-shape precedent** to copy — e.g. "deny-with-reason looks like
  `start_blocked_reason()`, and `can_start()` is literally
  `start_blocked_reason().is_empty()`; one seam, never two predicates."

## Review proportionally

- **Under ~200 lines:** read it yourself. Cheaper than briefing a reviewer.
- **Over that, or touching a global bus / shader / autoload:** spawn a
  **Sonnet read-only reviewer** with **5–6 pointed, adversarial questions** —
  never "review this branch". Tell it not to summarise the diff back.

The single best reviewer question format is *"find a case where this breaks"*,
not *"is this correct"*. Asking one to **construct** an event ordering that
violates a claimed invariant, and having it report that it could not, is worth
more than any number of confirmations. Always include one question on **house
rules** (transcendentals, hdr-color tiers, no pinned tuning values) and one on
**leftover callers** after a split or rename — that is where the silent
breakage lives.

## Verify the drone, cheaply

Drones are honest but occasionally wrong about the world.

- A drone said "issue closes via the commit trailer". **It did not** — master
  was ahead of `origin`, so GitHub never saw the commit. Always check
  `gh issue view <n> --json state`.
- A drone diagnosed a hang as "GUT deadlocks on its own paused tree", then
  retracted it: the real cause was a parse error. **Endorse a diagnosis only
  after it survives one more piece of evidence.**
- Read the suite log yourself out of the drone's worktree
  (`.worktrees/<slug>/.godot/gut-last.log`) rather than waking a 200k drone to
  report it back.

## The merge token is serial

`warp` ends in a **fast-forward**. Only one drone can merge at a time; the
moment one lands, every other branch stops being a descendant. Approving is
therefore handing over a **token**, not issuing a verdict. Tell the next drone
to `git rebase master`, re-run `check` **and** its targeted tests, then merge —
a rebased tree is a tree nobody tested.

## The final suite, done right

1. **Baseline first.** If the main checkout has uncommitted WIP, create a
   throwaway worktree at the merge sha and run the failing areas there. That
   turns "12 failures, probably the user's" into *proof*.
2. **Never pipe a backgrounded suite through `tail`** — it buffers until exit,
   so a hang looks identical to a slow run. Redirect to a file. One run spun on
   `Project FPS:` for **26 minutes** and this hid it.
3. Read `Scripts` / `Passing` / `Failing` from the log, and compare the failing
   **set**, not the count.

## What actually bit

- **An over-strict rule cost more than the risk it removed.** "Never run the
  full suite" was wrong for an issue *about* the full suite; correcting it
  mid-flight replayed the drone's whole context. Scope prohibitions to the
  reason behind them.
- **`gh issue close -c "..."` on an already-closed issue silently drops the
  comment.** Comment first, then close.
- **Do not instruct a drone about a rule file you have not read.** Telling one
  to add a "**Why:** / **How to apply:**" section to a *breadcrule* (a one-line
  always-on crumb) was wrong, and the drone correctly pushed back. Read the
  rule before ruling on it.
- **A guard you land can be a landmine.** A `pre_run_script` hook made *any*
  load failure abort GUT before `quit()` — an unbounded hang, and a fresh
  worktree could not run tests at all until refreshed. When approving
  infrastructure, ask: *what does this do when it fails?*

## On retiring fat drones — the honest answer

**The 250k rule almost never fired.** Observed end-contexts: 111k, 130k, 163k,
208k, 222k. Only one drone was ever parked, and by the *session's* limit, not
the rule.

**When it does fire, it is not free.** The parked drone had ~185k in it; its
successor spent ~163k finishing roughly the last 40%. Call it **+80–100k of
overhead** for the split — real, and worth paying only under a hard stop.

So:

- **Do not retire a drone within sight of its gate.** A successor spends
  ~50–60k just re-orienting; that exceeds most tails. Let it finish.
- **Retirement is only as cheap as its handoff.** The successor was cheap
  because the parked drone wrote **decisions, next steps, and dead ends as a
  comment on the issue**. Brief the successor with *"that comment is your
  brief — do not re-explore, do not re-derive its decisions."* It worked: the
  successor never re-swept.
- **Write the handoff to the ISSUE, never to the orchestrator.** Your context
  is the scarce one, and the issue outlives the session.
- **Prefer scoping so one drone finishes.** A 222k single-drone issue landed
  clean. The real ceiling signal is *your* session, not the drone's.

## Keep your own context small

Reading source yourself is the failure mode. Over five issues, reading was:
five issue titles, two source files, and a handful of targeted greps.

But **under-reading has a specific cost**: every time a bad instruction went
out, it was because I had not read the rule or task I was ruling on. The trade
is not "read less" — it is **read narrowly, but read the thing you are about to
give an order about.**

## Housekeeping the chain earns

- Close each issue by hand with a landing comment carrying the **non-obvious
  finding**, not a summary of the diff.
- File the residue as new issues *while the shape is fresh* — a rescoped design
  question, an infrastructure fragility you found the expensive way.
- Delete the handoff doc when the chain lands. It is scaffolding.
