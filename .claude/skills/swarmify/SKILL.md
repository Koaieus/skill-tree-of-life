---
name: swarmify
description: Take one GitHub issue from "has open design forks" to Ready — remove blockers, surface every unresolved decision, research the code and think each fork through with the user from both the technical and gameplay side, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.
---

# Swarmify

Turn a forky issue into a drone-ready one. This is the **front-loaded design
pass** whose absence is why throughput stalls: when forks are discovered
mid-implementation, every issue crushed spawns five more and no agent can run
unattended. Swarmify moves that discovery *before* the code, where decisions are
the user's to make and cost minutes, not stalled worktrees.

## What this skill is actually for

**Removing blockers and answering design questions.** You research the code, you
think the problem through *with the user* from both the technical and the
gameplay side, and you come back with forks pinned. An issue often floats ideas —
your job is to test them against what the code actually does and what the game
actually needs, then help the user choose.

The single highest-value move is **arithmetic on already-pinned values**: after
pinning anything, compute what it implies at the bottom and the top of the range
(level 1 and level 100, one node and two hundred). Repeatedly, the fix that
surfaces is structural, not a tuning nudge — and it surfaces from the numbers,
not from discussion.

The second is **verifying claims against `master`.** An issue that says "X is
unbuilt" or "Y is broken" may be describing a world two commits stale. Check
before you spec work against it; a stale item closes with a doc correction, not
a new issue.

> **File ownership is a map, not a gate.** Record which paths a unit touches —
> the [`swarm`](../swarm/SKILL.md) orchestrator needs it to sequence work. But do
> **not** contort the design to keep files disjoint, and do not withhold
> `Ready` because two issues share a file or because one blocks another.
> Sequencing, rebasing, and clean merges are the *orchestrator's* job: drones
> commit inside their own worktrees, and the orchestrator rebases and
> fast-forwards. Two issues on the same file simply run in order — possibly in
> the same swarm. Design correctness beats partition tidiness every time.

## The one rule

**Decisions are the user's. You surface forks and propose; they choose.** An
agent that invents a design answer to reach `Ready` has defeated the purpose —
the whole reason early design-heavy sessions unlocked autonomous throughput is
that a *human* pinned the forks. If the user is absent, you may draft proposed
resolutions, but you do **not** apply the label until they've signed off.

## Read the issue yourself; delegate only the fact-checking

Two different jobs hide inside step 1, and they have opposite delegation answers.

**RTFC is yours.** A hub's comments are where the decisions live, and they argue
with each other — a later comment routinely *corrects* an earlier one in the same
thread. A subagent hands you a summary, and the summary is exactly where that
nuance dies. Never delegate reading the issue.

**Verification is not.** Once you have the issue's claims in hand — "`X` is
unbuilt", "`Y` has no caller", "placement carries `node_scene`", "that helper was
deleted in #N" — checking each against `master` is mechanical lookup with no
judgment in it, and it is most of the tool calls in a pass. Dispatch **one**
`Explore` agent (`model: "haiku"`) with the claim list and have it report
verified/false//stale per claim with a `file:line`. One call instead of ten.

This does not contradict "not a spawn" below — that rule is about the *thinking*.
Fact-checking isn't thinking, and skipping it is how a pass specs work against a
world two commits stale.

Worked example (2026-08-02, #332/#165): reading two hubs' comment threads was
irreducible and caught a comment retracting an earlier one's central claim. The
same pass burned ~8 calls on pure lookup — is #322 closed, is #339 already filed,
does `keystone_placement.gd` have a `node_scene` field — and that last one is what
exposed #330 sitting in `Ready` with an open fork in its body.

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
- **Unowned surfaces** — which files? Not to keep units disjoint, but because
  "which files does this touch" is often the question that reveals the design
  isn't settled: if two plausible implementations land on different modules, the
  *approach* is undecided, and that's the fork.
- **Cross-issue dependencies** — does this need another issue resolved first?
  Record the dependency; it does **not** disqualify `Ready`. A blocked issue
  and its blocker can run in the same swarm, in order — the orchestrator owns
  that DAG. Only an issue blocked on a *decision nobody has made* stays `design`.

List them back to the user plainly, numbered. Use `AskUserQuestion` when the
forks are clean multiple-choice; prose when they need discussion.

### 3. Settle each fork with the user

One at a time or in a batch — but every fork gets a *pinned* answer, written down
in the user's words, not paraphrased into ambiguity. If a fork can't be settled
now (needs a spike, needs another issue), the issue stays `blocked`/`design` and
swarmify stops for it — that's a valid outcome, not a failure.

### 4. Write the acceptance spec into the issue

> Issues written before 2026-08-02 head this section `## Swarmable spec`. Same
> thing — read it as the acceptance spec; don't retitle them on sight.

Post a comment (or edit the body) with an `## Acceptance spec` section containing:

- **Decisions** — each resolved fork, one line, stated as settled fact.
- **Files touched** — the paths the work lands on. This is *information for the
  orchestrator's DAG*, not a fence. Name any file you know a sibling issue also
  touches, and say which issue — that's what lets the orchestrator sequence
  rather than collide.
- **Acceptance** — the failing test to make green, or an exact behavioural spec.
- **NOTES** — descoped asides, parked for their own future issue. Never let one
  ride the Ready unit.

This comment is what the `swarm` orchestrator (or a `warp` run) pastes into the
worker prompt. Make it copy-paste complete.

### 5. If it's a hub, decompose into Ready children

An epic (sub-issues > 0, or too big for one worker) is not itself `Ready` — its
*children* are. Split it **along whatever seam the design actually has** — one
decision, one coherent unit of work. Where that seam also happens to be a file
boundary, say so; where it doesn't, split anyway and record the overlap. A child
that spans a shared file is still `Ready`; the orchestrator sequences it.

File each child under the parent:

```bash
gh issue create --parent <n> --title "…" --body "…"    # gh ≥ 2.9x
mise gh-project -- status <child> ready                # or needs-design if it still forks
```

Each child gets its own `## Acceptance spec`. Shared-file work (one `.tres` every
child touches, a registry append) is **not** parcelled out — flag it as the
orchestrator's pre-step, done in the main checkout before dispatch.

### 6. Promote to Ready

`Ready` **is** the admission ticket — there is no `swarmable` label (retired
2026-08-02). Moving the status is the whole act:

```bash
mise gh-project -- status <n> ready       # the pickup column = the swarm queue
mise gh-project -- label <n> rm design    # forks are resolved now
mise gh-project -- label <n> rm blocked   # if it was
mise gh-project -- milestone <n> <m>      # Ready with no milestone is a hygiene violation
```

Drop the `design`/`blocked` labels in the same breath as the status move. Leaving
one on a `Ready` issue is exactly the drift the label collapse was meant to end,
and `hygiene` will flag it.

Then update the **decisions queue** (the tracking meta-issue): tick the hub you
just cleared, add any new `blocked` children you discovered. `mise gh-project --
list ready` should now show what you produced, and `mise gh-project -- hygiene`
should stay clean.

## What swarmify is NOT

- **Not implementation.** You resolve design and write specs; you do not write the
  feature. Handing off to `swarm`/`warp` is the next, separate step.
- **Not a rubber stamp.** If after triage the forks aren't actually settleable, the
  honest output is "still `blocked`, here's why" — leave it in `needs-design`
  rather than promoting an issue a drone will stall on.
- **Not a spawn.** Don't `Agent`-dispatch to do the thinking. This runs in your
  session, with the user, by design.
