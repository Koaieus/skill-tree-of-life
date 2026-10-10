---
id: 0052
title: A node's addon cap reads its stake level (1 when unallocated), never its fill; procgen draws addon nodes with replacement at a per-100-node density and stakes repeats (up to 4); an extract that would overflow the cap is denied — supersedes legacy D-3
status: accepted
date: 2026-10-10
deciders: owner (all four calls); agent (drafting, the separate formula file)
supersedes: []              # legacy D-3 is not an ADR; superseded in legacy-mvp-decisions.md
superseded-by: null
revisit-when: "an addon inventory (#1533, with #348) lets an extract pop an addon instead of being denied"
sources:
  - "#1528"
  - "#1530"
  - "#1533"
  - "stats_system/formulas/stake_scaling.tres"
  - "skill_node/default_node_board.tres"
  - "docs/adr/legacy-mvp-decisions.md (D-3)"
tags: [addons, procgen, stats, staking]
---

# ADR 0052 — The addon cap reads stake level; procgen draws addons with replacement and stakes repeats

## Context

`addon_slots` was `base(0) + allocation_level` (the stake pool's fill M), so an unallocated node had 0 slots and the cap was advisory. Procgen applied addons per node via `AddonPolicy.slot_count_weights` (legacy D-3). The extract gate and the procgen placement pass (#1528's children) both need one honest cap, and the stake pool (cap N = stake level, fill M = allocation level) already models "how much this node can hold".

## Decision drivers

- One cap that procgen placement, the attach check and the extract gate all read.
- Addon density tunable by one knob that scales with map size.
- Rules read stake/allocation as variables, not hard numbers.

## Decision

- **The cap reads stake level.** Owner, 2026-10-10: *"it should always have been local stake level, which is 1 even if unallocated (like if staking didn't exist, unallocated node would read as "0 allocation points held, out of a maximum of 1 held" and staking just raises that maximum, so a plain skill node has a maximum == stake level == 1)"*.
- **Procgen draws with replacement and stakes repeats; density is per 100 nodes.** Owner, 2026-10-10: *"maybe we should switch to adding addons at random (draw-then-put-back) and stake it as we happen to draw one we already rolled an addon on. easy? then density is just 1 knob: how many addons (per 100 nodes? or in total? idk)"*. Per 100 nodes was the pass's answer, so 120- and 800-node maps scale together.
- **Procgen may stake to 4, past the player ceiling of 3.** Owner, 2026-10-10: *"stakes have a maximum of 3, but a truly rare 4-addon procgen roll staking it to 4 would be a fun ultra-rare occurrence. most if not all mechanics dont depend on hard staking numbers (alloc lv or stake lv) but just the variables"*.
- **An extract that would leave more addons than the new cap is denied.** The owner picked deny as "cleanest" (2026-10-10, #1528).

Shape: the formula is a new file-backed `stake_scaling.tres` (`stake_level`, the bare PoolStat cap) bound only to the `addon_slots` intrinsic. `allocation_scaling.tres` (`stake_level__current`) is left as it was, because it also drives `arrows_per_reload` and `max_shots_per_leaf`, which still follow fill. ADR 0004 stays accepted. Its driver bullet quoting `addon_slots = base(0) + allocation_level` (0004 lines 74-79) is stale on the formula only.

## Consequences

- A plain node holds 1 addon and a stake-3 node holds 3 at any fill. Allocating no longer opens slots, only staking does.
- The cap is enforced, so the placement pass and the extract gate read the same number as `can_attach_addon`.
- The share of multi-addon nodes follows the overall density. It can no longer be tuned on its own.
- A multi-addon node can be extracted only once it sheds addons.

## Alternatives considered

### Keep the cap on fill (old `base(0) + allocation_level`)
Lost on the one-cap driver. An unallocated procgen node could not hold the addon it was generated with. Dead: the owner called it a mistake ("should always have been").

### Per-node application via `slot_count_weights` (legacy D-3)
Lost on the one-knob driver. Weights per slot count do not scale with map size. **Most likely to be revived** if multi-addon rarity needs tuning on its own.

### Pop an addon into an inventory on an overflowing extract
Not rejected but parked as a design sibling (#1533, with #348). It is this record's `revisit-when`.

### Flip `allocation_scaling.tres` in place
Rejected: that file also feeds two ranged stats that must keep following fill.
