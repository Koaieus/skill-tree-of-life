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
  `min_damage_taken +` bane; DEX rolls `armor_pierce` (flat and %), which
  lowers the *enemy's* armor rather than raising yours. One allocated node can move a defence axis.
- **core class, addons, auras**: Sanctuary's +CON, the Bunker's +armor and
  −floor.
- **statuses**: each curse stack raises the floor by 1, sunder lowers
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

## The attacker side of armor: pierce

`sunder` works **inside** the defender's armor bins (a −1 per stack, can go negative). `armor_pierce` works **on its output** (ADR 0065): the hit carries the attacker's pierce as `FoldTerms` (`DamageInstance.armor_pierce`, stamped by its producer via `Mitigation.pierce_terms` off the attacking node), and `Mitigation.effective_armor` folds it over the defender's *final* armor only when that is > 0, clamped at 0 and floored to whole; the `min_damage_taken` floor still applies last. Fixture: defender 4 / +50% / +2 = 8 → −3 ADD_BASE lands 5, −50% INC 4, ×0.5 4, SET 0 0. Producers opt out (`uses_board_pierce`) or add their own (`armor_pierce_modifiers`): `DamageEffect`, `PairedDamageEffect`, `AmmoType`, and the blade via `SwingContext`.


## Mitigation: the formula and the negative floor

`Mitigation.apply` (`attack/formulas/mitigation.gd`) runs inside
`SkillNode.take_damage` and turns "5 PHYSICAL" into the effective post-armor
number that subtracts HP.

- `final = max(min_damage_taken, raw - effective_armor)`, only when `raw > 0`
  (zero incoming damage stays zero; the floor triggers on a real hit). TRUE
  damage bypasses everything.
- **Armor pierce** is the attacker's pipeline over the defender's final armor
  (`DamageInstance.armor_pierce`, stamped by `pierce_terms`): folded only when
  armor > 0, clamped at 0 (pierce never makes a hit bigger; breaking armor below
  0 is `sunder`'s job), floored to whole once, never merged into the defender's
  armor bins.
- **Both stats are read node-locally** via `SkillNode.get_local_value`, which
  merges the node's `node_board` bins with the owner's board through one
  `ModifierBins.compute`, so a node-scoped `armor` modifier (a `bunker_addon`, a
  core-class aura) reaches the formula. Reading the entity board directly would
  silently discard every node-local defensive modifier while the HUD displayed
  them.
- **The floor is a floor, not a cap:** negative `armor` pushes damage above raw,
  but only becomes visible once `raw - armor > min_damage_taken` (raw 1 / armor
  -1 / floor 3 still takes 3).
- **A negative net `min_damage_taken` makes a glancing hit heal the defender, on
  purpose.** `compute` returns the negative number as-is and
  `NodeCombat.take_damage` reclassifies the landing to `HitInstance.Kind.HEAL`.
  `bunker_addon.tscn` authors `-5`, affirmed by the owner 2026-09-04: "the whole
  design of sprinkling `-min_damage_taken` modifiers on the board is to allow to
  go <0 and actually heal from having sufficient armor / tanking low hits
  heals". Anything that clamps this at zero deletes a mechanic; anything that
  drops such a landing from a render pass is the bug fixed in
  `ArrowVolleyCoordinator`.
