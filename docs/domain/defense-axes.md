# Defense axes — the six ways a node survives

An entity's defence is a point in six dimensions, each blocking a different
shape of damage. [ADR 0022](../adr/0022-one-dot-per-defensive-axis-stacks-halve-uncapped.md)
names them — bulk, armour, floor, regen, aura, topology — and gives every
damage-over-time family the profile it answers. The DoT families themselves
are `effect-system.md` § "Status effects — the DoT model".

| Axis | Owner in code | What it answers | DoT that bypasses it (ADR 0022) |
|---|---|---|---|
| **Bulk** | `node_health` (scaled by the CON attribute through `node_health_scaling`); the entity's `health` pool, `core_health_scaling` | big single hits; many small ones | **Corruption** — % of max HP per stack |
| **Armour** | `armor`, subtracted once per `DamageInstance` in `attack/formulas/mitigation.gd` — per arrow landing and per blade contact alike | many small hits | **Poison** — flat, unmitigated; **Curse** raises the floor so every hit lands again |
| **Floor** | `min_damage_taken`, the post-armour floor in `mitigation.gd`; below `0` a hit heals | chip damage; sub-zero, any hit at all | **Poison** answers the sub-zero floor; **Curse** answers the bunker by raising the floor |
| **Regen** | `node_healing` + `regen_stacks × node_healing_ramp` at turn start, reset at full and closed by damage (`SkillNode`, `node-hp.md`) | damage spread over turns | **Wither** — multiplies `healing_received` down, below zero heals into damage |
| **Aura** | `AuraEffect` subclasses on `CoreClass.effects`, e.g. `HealAuraEffect` (heal scales with `constitution`) | attrition near the core | **Wither** — the aura heals through `healing_received` too |
| **Topology** | cut vertices and islanding (`EntityNavigator`, `allocation_system.md`); degree (`degree.md`) | losing what is behind a chokepoint | none — no DoT targets topology |

Each axis is one hit-shape away from irrelevant, which is the ground for one
DoT family per axis rather than one DoT that answers all of them (ADR 0022,
"Keep %-max poison with a cap", rejected).
