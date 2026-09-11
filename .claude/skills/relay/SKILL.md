---
name: relay
description: Orchestrate a chain of Ready issues as one Sonnet `warp` drone each, with you as advisor and sole merge gate — read almost nothing yourself, front-load each brief with discovered context, gate every merge, and run the full suite once at the end. Use when the user names several issues to land in sequence ("#A → #B → #C as Sonnet warps"), says "relay these", or asks you to orchestrate warps without doing the implementation. Prefer this over `swarm` when the issues are already Ready and merges must serialise.
---

# Relay — a swarm at wave size 1

Folded into [`swarm`](../swarm/SKILL.md) on 2026-09-11 (#857). A relay **is**
a swarm with one drone in flight: read `swarm` and run it with a wave size of
one — the serial merge token, the bare-number brief, the tier tag, `mise run
land`, the once-per-train suite and the push are all the same protocol, and
this file no longer restates any of it. What differs at wave size 1:

- **The Sage seat is optional.** With one drone in flight you are the
  cheaper reviewer and lander (`swarm` §5's verdict) — read `--stat`, then
  the diff, and run `mise run land -- <branch> --closes <n>` yourself. Spawn
  a Sage only when the chain is long enough or design-heavy enough that the
  drones' questions would otherwise land on you.
- **Ordering is the DAG.** One Haiku `Explore` answers which issues touch
  the same files; that ordering is the whole plan.
- **Each issue closes as it lands** — `land --closes` per branch, since every
  branch is the last for its issue.

What the 2026-09-03 chain (#737 → #727 → #746 → #736 → #743, five landed in
~5h; lead 218k, drones 111k–222k) taught now lives where it binds: the
drone-side rules in `drone`, the merge token in `mise run land`, review
proportionality and the final-suite baseline in `swarm` §5–§6, retirement
economics in `swarm`'s stop-compliance section. Do not re-grow this file.
