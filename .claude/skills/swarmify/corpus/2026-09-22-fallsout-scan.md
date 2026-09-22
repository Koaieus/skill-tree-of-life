# Scan: "X falls out for free" — 2026-09-22

Rows: `2026-09-22-fallsout-labelled.jsonl` (75 genuine hits).
Source: 318 session transcripts, assistant-side text and `AskUserQuestion`
option descriptions. Regex over `falls out (for free)`, `for free`, `comes
for free`, `collapses to/into`, `disappears`, `drops out`, `is just`,
`becomes a no-op`: 227 hits after dedup, all read in full; 75 genuinely
mean "this pick makes something else come along at no cost" (33% regex
precision — `is_just`, `disappears`, `collapses` were mostly restatements,
UI description or sysadmin chatter). ~10 of the 75 are borderline, kept and
marked `other`.

## Totals

What fell out: feature-for-free 21 · consumer-simplifies 19 ·
special-case-removed 12 · other 13 (incl. claim didn't hold / "free" as a
smell) · mp-sync 4 · perf 3 · sibling-issue-closes 2 · test-writes-itself 1.

Enabler: **single-owner-of-fact 31** · **shared-shape-reuse 17** ·
composition-array 8 · data-driven 4 · resource+subclasses 1 · new system 1 ·
other 13.

Context: swarmify 58, swarm/drone 17 (file-content heuristic, approximate).
Owner reaction in-file: endorsed 8, pushed back 3, redirected 1, none 63.

Timeline: steady 1–6/day from 2026-08-23 to 2026-09-22, bursts on 08-24
(frontmatter camera + StatModifier design) and 09-18 (ranged-combat
cross-fire). No upward trend — a background rate of this reasoning.

## The pattern

Free-riding almost never comes from adding abstraction. It comes from
**deleting a duplicate representation** (a status derived not set, a delta
stored instead of an absolute, a gate read once, a snapshot reused) or
**routing through something that already exists** (the same builder, the
same material, the same command channel). Composition arrays produce it as
emergent behaviour (parity detection, dumbbell shapes, entity-wide ailments).
A new system or resource hierarchy scored one each.

## Best examples

1. 2026-08-24 — "one persistent graph, nodes never move, the Camera2D
   moves... Three things then fall out for free" (back-nav symmetry,
   edge-pop elimination). Endorsed, shipped.
2. 2026-08-24 — "The relic falls out for free: allocating the freed node is
   what opens the loot chain, and NPCs auto-pick each round."
3. 2026-08-27 — "store `missing` (damage taken) instead of absolute
   `current`... full nodes stay full for free" — a class of cache
   invalidation deleted.
4. 2026-08-31 Cyclone — "the mechanic turned out to be a parity detector,
   and nothing in it was authored to be one. It falls out of the veto being
   a union." Shipped; later cut at #703 as nobody's intent.
5. 2026-09-01 — Cyclone via next-edge permutations: "no cycle detection, no
   trail bookkeeping... minimum-length-3 property still falls out for free."
6. 2026-09-07/08 blade physics — "the 'secondary battle economy' you named
   falls out of it rather than being built"; the bladesmithing gradient from
   reusing `eccentricity()`.
7. 2026-09-08 — interleaved model: "`BladeFreeFlight`, `is_unpinned`, the
   velocity seeding, fragment-of-a-fragment — all of it is scaffolding."
   Four mechanisms retired by one sequencing fix. Endorsed.
8. 2026-09-09 — "Replay makes them equal by construction — acceptance 3 and
   4 fall out rather than being chased."
9. 2026-09-10 — "Velocity is already derivable for free" from stored
   trajectory samples; no new field, no wire change.
10. 2026-09-15 — "a hub's status is just a summary of its children... I
    retired `parked_child`". Endorsed.
11. 2026-09-18 ranged combat — "R›B›G›R falls out structurally"; "a whole
    system falls out of one rule: 'a leaf covers a cone and shoots what's in
    it.'"
12. 2026-09-20 — "The core is just a `SkillNode`... poison already works on
    cores, no issue needed." Issue closed. Endorsed.

## Where "free" was false or a smell

- 2026-08-25 SPLASH_ZOOM — "It doesn't fall out... That'd need a
  per-camera-pose concept nobody asked for." Said so instead of forcing it.
- 2026-08-31 — "'self-loop-blind for free' is false" — asserted in four
  places including shipped flavour text; caught by the owner's observation.
- 2026-09-14 mitigation doc — "bulk grows for free with level, mitigation
  does not": "for free" as the defect.
