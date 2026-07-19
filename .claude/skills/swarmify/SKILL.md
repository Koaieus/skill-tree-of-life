---
name: swarmify
description: Take one GitHub issue from "has open design forks" to swarmable — surface every unresolved decision, get the user to settle each, write a crisp acceptance spec, split a hub into file-disjoint children if needed, and apply the `swarmable` label. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "make #<n> swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.
---

# Swarmify

Turn a forky issue into a drone-ready one. This is the **front-loaded design
pass** whose absence is why throughput stalls: when forks are discovered
mid-implementation, every issue crushed spawns five more and no agent can run
unattended. Swarmify moves that discovery *before* the code, where decisions are
the user's to make and cost minutes, not stalled worktrees.

> The output of this skill is exactly the **input** the [`swarm`](../swarm/SKILL.md)
> Gate demands. Read swarm's "Gate — do not swarm the wrong work" first: the four
> conditions (pre-decided, file-disjoint, mechanical-enough, no mid-flight input)
> are the definition of `swarmable`. Swarmify is the ritual that makes them true.

## The one rule

**Decisions are the user's. You surface forks and propose; they choose.** An
agent that invents a design answer to hit `swarmable` has defeated the purpose —
the whole reason early design-heavy sessions unlocked autonomous throughput is
that a *human* pinned the forks. If the user is absent, you may draft proposed
resolutions, but you do **not** apply the label until they've signed off.

## The cycle

### 1. Read the whole issue — RTFC

```bash
gh issue view <n> --comments
```

Comments hold the actual decisions and course-corrections (repo rule). Read them,
not just the body. Note the current labels: `design` / `blocked` mean forks are
known-open; their presence is the signal there's work here.

### 2. Enumerate every open fork

A fork is anything a drone would have to *decide*. Hunt for:

- **Floated alternatives** — "…or some other way to show it", "maybe X, maybe Y".
- **Speculative asides riding along** — "and maybe we drop the trimming too?" A
  second decision must never ride a first; split it out.
- **Unstated acceptance** — no definition of done. "Done" must be a failing test
  or an exact spec, per swarm Gate #3.
- **Unowned surfaces** — which files? If two plausible implementations touch
  different files, the file set is itself undecided.
- **Cross-issue dependencies** — does this need another issue resolved first? If
  so it's `blocked`, not swarmable.

List them back to the user plainly, numbered. Use `AskUserQuestion` when the
forks are clean multiple-choice; prose when they need discussion.

### 3. Settle each fork with the user

One at a time or in a batch — but every fork gets a *pinned* answer, written down
in the user's words, not paraphrased into ambiguity. If a fork can't be settled
now (needs a spike, needs another issue), the issue stays `blocked`/`design` and
swarmify stops for it — that's a valid outcome, not a failure.

### 4. Write the swarmable spec into the issue

Post a comment (or edit the body) with a `## Swarmable spec` section containing:

- **Decisions** — each resolved fork, one line, stated as settled fact.
- **Files owned** — the exact paths the work may touch (the disjoint boundary).
- **Acceptance** — the failing test to make green, or an exact behavioural spec.
- **NOTES** — descoped asides, parked for their own future issue. Never let one
  ride the swarmable unit.

This comment is what the `swarm` orchestrator (or a `warp` run) pastes into the
worker prompt. Make it copy-paste complete.

### 5. If it's a hub, decompose into swarmable children

An epic (sub-issues > 0, or too big for one worker) is not itself swarmable — its
*children* are. Partition **by file, not by feature** (swarm's hard rule: two
workers never touch one file). File each child under the parent:

```bash
gh issue create --parent <n> --title "…" --label swarmable --body "…"   # gh ≥ 2.9x
```

Each child gets its own `## Swarmable spec`. Shared-file work (one `.tres` every
child touches, a registry append) is **not** parcelled out — flag it as the
orchestrator's pre-step, done in the main checkout before dispatch.

### 6. Label and queue

```bash
mise gh-project -- label <n> add swarmable     # the admission ticket
mise gh-project -- label <n> rm design         # forks are resolved now
mise gh-project -- label <n> rm blocked         # if it was
mise gh-project -- status <n> ready            # into the pickup column
```

Then update the **decisions queue** (the tracking meta-issue): tick the hub you
just cleared, add any new `blocked` children you discovered. `mise gh-project --
swarmq` should now list what you produced.

## What swarmify is NOT

- **Not implementation.** You resolve design and write specs; you do not write the
  feature. Handing off to `swarm`/`warp` is the next, separate step.
- **Not a rubber stamp.** If after triage the forks aren't actually settleable, the
  honest output is "still `blocked`, here's why" — not a `swarmable` label on an
  issue a drone will stall on.
- **Not a spawn.** Don't `Agent`-dispatch to do the thinking. This runs in your
  session, with the user, by design.
