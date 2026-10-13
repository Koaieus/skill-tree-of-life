# Defense axes — the six ways a node survives

An entity's defence is a point in six dimensions, each blocking a different
shape of damage: bulk, armour, floor, regen, aura, topology. The table names
the shipped damage-over-time row that bypasses each. The axes are a vocabulary
for what a row answers, not slots: two rows may answer one axis when they
differ in character ([ADR 0048](../adr/0048-status-decay-is-authored-per-def-rows-differ-in-character-not-numbers.md)).
The status rows themselves are [status-effects.md](status-effects.md) § "The DoT model".

| Axis | Owner in code | What it answers | DoT that bypasses it |
|---|---|---|---|
| **Bulk** | `node_health` (scaled by the CON attribute through `node_health_scaling`); the entity's `health` pool, `core_health_scaling` | big single hits; many small ones | **Corruption** — % of max HP per stack |
| **Armour** | `armor`, subtracted once per `DamageInstance` in `attack/formulas/mitigation.gd` — per arrow landing and per blade contact alike | many small hits | **Poison** — flat, unmitigated; **Curse** raises the floor so every hit lands again |
| **Floor** | `min_damage_taken`, the post-armour floor in `mitigation.gd`; below `0` a hit heals | chip damage; sub-zero, any hit at all | **Poison** answers the sub-zero floor; **Curse** answers the bunker by raising the floor |
| **Regen** | `node_healing` + `regen_stacks × node_healing_ramp` at turn start, reset at full and closed by damage (`SkillNode`, `node-hp.md`) | damage spread over turns | **Wither** — multiplies `healing_received` down, below zero heals into damage |
| **Aura** | `AuraEffect` subclasses on `CoreClass.effects`, e.g. `HealAuraEffect` (heal scales with `constitution`) | attrition near the core | **Wither** — the aura heals through `healing_received` too |
| **Topology** | cut vertices and islanding (`EntityNavigator`, `allocation_system.md`); degree (`degree.md`) | losing what is behind a chokepoint | none — no DoT targets topology |

Each axis is one hit-shape away from irrelevant, so a build that stacks one
axis leaves the others open to a row that bypasses it.

## Every axis is a live stat: the board base is only where a fresh entity starts

A `base_value` on `entity/default_entity_board.tres` (or a Dormant Core board)
is what a **fresh lv1 entity with no nodes** reads. It is never "the" value a
hit, a tooltip or a balance argument sees. Each axis is folded live from every
bin the entity and node carry, and during a run those bins pile up:

- **level**: per-level class bonuses ride `level_scaling.tres` (`level - 1`, so
  lv1 adds nothing); CON climbs this way and drags both HP pools with it.
- **procgen node rolls**: the CON pool rolls CON (flat, %, ×), `armor +` and
  `min_damage_taken -`; `universal` rolls `node_health +%`; INT carries a
  `min_damage_taken +` bane. One allocated node can move a defence axis.
- **core class, addons, auras**: Sanctuary's +CON, the Bunker's +armor and
  −floor, the Fortification's +node_health.
- **statuses**: each curse stack raises the floor by 1, armor break lowers
  armor, wither scales healing.

The floor shows why no single number is the answer. `taken = max(floor, raw −
armor)` (`attack/formulas/mitigation.gd`). Getting from the board base to a
floor below zero means collecting several "−floor" rolls, which are rare;
below zero a hit heals, but only once armor pushes `raw − armor` under the
floor too. A floor of −10000 with no armor never comes into play. A curse
stack pushes a sub-zero floor straight back up. Each lever needs the others,
so none is all-powerful alone.

**How to apply:** read the stat where it is used (`get_value` on the entity,
`get_local_value` on a node) and reason in ranges: the board base, then what a
run adds to it. Never write "the floor is N" or "a core has N HP" in a
description, doc or comment as if it were fixed. Say "starts at N (board
base)", or better, name the stat. A test asserts relations between knobs,
never a board literal (`tunables.md`). Retuning a base is an inspector edit on
the board; the house rules for where a value lives are in
`stat-knobs-and-bins.md`.
