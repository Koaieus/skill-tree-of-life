# Defense axes — the six ways a node survives

An entity's defence is a point in six dimensions, each blocking a different
shape of damage: bulk, armour, floor, regen, aura, topology. The table names
the shipped damage-over-time row that bypasses each. The axes are a vocabulary
for what a row answers, not slots: two rows may answer one axis when they
differ in character ([ADR 0048](../adr/0048-status-decay-is-authored-per-def-rows-differ-in-character-not-numbers.md)).
The status rows themselves are `effect-system.md` § "Status effects — the DoT model".

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
