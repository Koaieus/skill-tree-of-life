# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the tiebreaker**: if something isn't in a lane below, it isn't scheduled,
regardless of what its priority field says.

Set 2026-08-02.

## The rule that was missing

Priority fields and column drags don't cause work to happen — sequence and WIP do.

1. **WIP limit: 3.** No more than three issues in `In progress` across the whole board.
   Nine at once (the state on 2026-08-02, with zero in review) is why things sat for weeks.
2. **One lane at a time.** Lanes below are ordered. Don't open lane N+1 while lane N has
   unfinished scheduled work.
3. **A fork is a Backlog issue, never an immediate start.** When implementing X reveals Y:
   file Y in `Backlog`, finish X, then re-read this file. "It's a small thing" is the
   phrase that has cost the most.
4. **Legibility ships, fidelity defers.** The visuals test: *does it change what the player
   can read and decide, or how it looks while reading the same thing?* Stat slabs, glass
   contrast, tooltip content → ship. Carved icon geometry, emblem substrates, rune art → defer.
5. **Crappy-now beats correct-later for anything not on the critical path.** A flat
   placeholder icon that ships this week outranks a carved one that ships never.

## Lanes, in order

### A — Balance: the game plays fairly

The hard ordering: **node HP scaling settles before damage is tuned.** Tuning damage
against wrong node HP means tuning it twice.

- #298 CON→node_health coefficient as a CoreClass genesis param — **first, blocks the rest**
- (new) ratchet-heal bug: nodes observed sitting at ~1/10 max HP, never damaged
- #274 INT → spell damage: board stat × per-spell coefficient — *blocked on #298*
- #278 spell balance pass: mana × degree × reach — *blocked on #298*
- #268 balance harness: scenario fixtures + ratio invariants
- #248 balancing hub (tracking)

### B — Spells come from the map, not from birth

- #206 add spell grants to procgen pools
- #198 spellbook maintenance: grant-vs-learn, add/remove plumbing
- #207 visualize spell-grant presence on a node — **flat placeholder emblem, not a carve**

### C — Auras work and are readable

- #316 heal aura falls off per hop
- #340 node-local modifiers: bind() + cycle gate at the node seam
- #332 node-local formula modifiers, scaled off allocation
- #333 StatFormula can only read a pool cap, not `current`
- "which auras affect this node, with what local effect" → tooltip content, lane D

### D — Legibility

- #159 tooltip V2 (hub) + its three unfiled defects: stat slab visual spec, HoloPanel
  layout inversion, glass contrast + corner AA
- #238 prune stacked encoders
- #341 RimRing: allocation dial into the shader + archetype legibility
- #318 CARVE bake decode bug (carves currently render blank — a bug, not fidelity work)

### E — Performance

- #53 performance budget + procgen scaling profile

### Enablers (pull in only when a lane needs them)

- #249 sandbox host live-tab scaffolding, + the skill node lab entry point / knobs
- procgen authoring DX: top-down inspector instead of six levels deep
- #324–#329 procgen v4 draw model (already decomposed, self-contained)

## Deliberately parked

Nothing here is closed. The design survives; the *scheduling* does not.

| Parked | Why |
|---|---|
| #165 pre-authored **clusters** in procgen | planarity + stitching research. Single-node splice (#180/#327/#330/#336) is kept — that one is cheap. |
| #245, #167, #342, #142 emblem/carve substrate + rune art | the Real Attempt. Fidelity, not legibility. Revisit after lane D ships flat versions. |
| addon **placement** UX (currency? inventory? which surface? balance?) | wholly undesigned. #337 staking mechanic ships without it. |
| procgen "stamping" | detour; milestone 6 is already 8/10 closed. Don't reopen. |
| #313 ArchetypePolicy clustering dials | overlaps stamping and cluster work. Revisit after procgen v4 lands. |

## When this file is wrong

It will go stale, like ROADMAP.md did. That's fine — it's short enough to rewrite in
ten minutes. Rewrite it rather than patching around it.
