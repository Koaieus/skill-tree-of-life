---
id: 0055
title: Turnless hosts (blockers, dormant cores) tick on the world turn — one ends every N played turn ends, N = the living turn-takers; counted in turns, never ticks
status: accepted
date: 2026-10-11
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "a status wants a beat other than the world turn (#1554, the per-status beat)"
sources:
  - "#1551"
  - "#1552"
  - "docs/adr/0040-statuses-tick-at-the-end-of-the-afflicted-entitys-turn.md"
  - "systems/turn_manager.gd"
tags: [combat, status, dot, turn, multiplayer]
---

# ADR 0055 — Turnless hosts tick on the world turn

## Context

ADR 0040 ticks a status at the end of the afflicted entity's turn. A turnless host — a blocker, a dormant core — never takes one, so its statuses (and the `LINGER` rows on empty ground) need another clock. Initiative already gives every turn-taker a relative pace; the round (#1257) exists but its roster rules carry warts. ADR 0040 stands: for a turnless host its "afflicted entity's turn" simply never comes.

## Decision drivers

- **Relativity:** count turns, so a uniform speed change changes nothing an entity observes. **Stacking:** a status applied on your turn survives to your next.
- **No hostage:** a slow or dying member must not hold the world open.
- **One beat:** every turnless-host status ticks at once (ADR 0040). **Sync:** reproducible from the command stream, no new command.

## Decision

1. **A world turn ends every N played turn ends, N = the number of living turn-takers.** Owner, 2026-10-11: *"B sounds best here. Supersede ADR if needed"*. With equal speeds it is a round; with mixed speeds it runs at exactly the average pace; a death only shrinks N.
2. **It counts turns, never ticks.** Owner, 2026-10-11: the empty ticks *"might as well have never happened, from the experience of the entities, relatively speaking they only see how fast they go w.r.t one another"*.
3. **Every turn end is rejected.** Owner: *"you could never stack poison like that"*.
4. **One beat.** Owner, 2026-10-11, picked "one beat now" over a per-status beat: every turnless-host status ticks on the world turn.
5. Pass calls (no behaviour change): only a played turn end (`TurnManager.end_turn`) counts — never `abandon_turn` (death) nor `adopt_turn` (resync); a world turn only *ends* (no start, upkeep or regen); `>=` N closes it, so a death that shrinks N below the progress closes it at the next played turn end.

## Consequences

- Poison on a blocker stacks across your turns at the table's average pace; the world never waits on its slowest member.
- `TurnManager` owns `world_turn_progress` and `world_turn_ended`; the progress rides the turn cursor (resync and save), adopted outright like `rounds_completed`. Peers reproduce it because `EndTurnCommand` runs `end_turn` everywhere at the same point.
- The world turn does not replace the round, which still drives the turn-limit victory.
- `scouted` (the only `LINGER` def) fades N times slower than on every turn end.

## Alternatives considered

### Every turn end
**Rejected on stacking.** *"applying 3 poison on it then ending turn -> >3 enemies take a turn -> by the time you are at turn again the poison stacks have gone to 3->2->1->gone"*; the unallocated time warp *"feels a bit off"*.

### The round
**Rejected on no hostage.** Its pace is the slowest member's lap, a near-zero-speed member holds it open, and death pruning is fiddly: *"had to settle on what a round means from a bunch of icky options that each carried a wart"*. Identical to the pick at equal speeds.

### Lesser options, each rejected on a driver
- **A fixed world speed** — relativity: double everyone's speed and the world ages half as fast relative to them.
- **Initiative per blocker** — relativity and one beat: two mechanisms, and fake turns reach every turn listener.
- **The applier's clock** — sync and one beat: two poisoners double-tick a folded row.
- **"Dead matter ripens and bursts on hit"** — breaks ADR 0040's slow-killer identity.

### A per-status beat
**Parked, not dead (#1554)** — *the alternative most likely to be revived*, when a status wants warp speed; ADR 0040 already rejected per-family timing on "one beat".
