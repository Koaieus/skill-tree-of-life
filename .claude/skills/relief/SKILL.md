---
name: relief
description: Continue a `swarm` as a fresh orchestrator session — the outgoing lead is dead (ran out of tokens, taking its subagents with it) or past its ceiling and alive, with worktrees open and branches pending. Orients from disk (ledger, board, worktrees — never the issues), reconciles and classifies every unit, then runs `swarm`. Use when the user says "relief", "take over the swarm", "relieve <session>", or a ledger for a run already exists on disk.
---

# Relief — re-entry protocol, then swarm

Design and laws: `docs/charters/relief.md`. `handoff` is the exit half;
this is the entry half. Nothing below restates `swarm` — once oriented, you
*are* the swarm lead and that skill applies unchanged.

## 1. Orient from disk — never the issues

```bash
cat docs/handoffs/swarm-<date>.md          # the ledger: roster, states, queue order
mise gh-project -- list in-progress         # the board's view of the same run
git worktree list
for wt in .worktrees/*/; do echo "== $wt"; git -C "$wt" log master.. --oneline; git -C "$wt" status --short; done
```

A gap between the ledger and git is a stale ledger. Fix the ledger from git
if the outgoing is dead; ask the outgoing **one** question if it is alive.
Never open an issue to compensate — the worktree is the state.

## 2. Classify every unit, rewrite the ledger, then dispatch

| Class | Evidence | What it dispatches as |
|---|---|---|
| **landed** | sha on `master` | nothing |
| **branch-ready** | reported, not landed | you review `--stat` + diff, then `mise run land -- <branch> --closes <n>` |
| **partial** | commits or WIP in a worktree, no report | a resume-brief naming the worktree, the branch, and "read `git diff master...` first" |
| **unstarted** | no worktree | a fresh brief per `swarm` |
| **in flight, outgoing alive** | ledger row `dispatched`, outgoing responsive | wait for the outgoing's ping, then treat as branch-ready |

Uncommitted WIP in a dead drone's worktree is state: commit it there as
`wip(<scope>): <what works>; missing <what>` before any resume-drone sees it.

## 3. A live outgoing — the contract

Your first message to the outgoing states your name. From then on it owes
you **exactly one wake per in-flight drone** and nothing else:

> On each drone's report: update that drone's ledger row, then
> `SendMessage` me one line — `#<n> reported @<sha>, row updated` — and
> stop. No dispatch, no merge, no test, no review, no redirecting drones.

Drones are never redirected to you; their reports reach the outgoing and its
ping is the relay. Its Sage stays its own and answers its drones until they
drain; spawn your own per `swarm` if the run calls for one. `APPROVED <sha>`
lines already in the ledger stand.

## 4. Now run `swarm`

From the reconciled ledger, `swarm` §3 onward: briefs, tiers, review,
`land`, the train, teardown. Thresholds, ceilings and when *you* request
relief are `swarm`'s — this file quotes none.
