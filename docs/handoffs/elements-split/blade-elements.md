Shared blade base for the three element units under the #1716 split (design home `docs/design/elements.md`): the rider-only element addon and its budget, the generic vertex copy-on-fill with spend-the-copy and its hand-off to the gather, the one-shot vertex flag seat, and the per-contact sweep-speed factor on signed `t` with its cue. Element-specific vertex behaviour stays in each element's unit.
Blocked by: #{refresh}
Blocks: #{fire}, #{lightning}, #{ice}

## Acceptance spec

**Decisions**
- *"an addon per element"* (owner, 2026-11-09; `docs/design/elements.md:418-424`) — the addon grants the rider and nothing else (*"what stats? e.g. +1 fire_element sounds *too strong*"*): no stat modifier on it; how many a build affords is budgeted by the element count (`fire_element` / `ice_element` / `lightning_element`, owner 2026-11-10, built in #{defs}).
- *"copy a burning node and you get a burning blade node (booms). copy frozen node -> frozen blade node (detrimental so far, makes blade node fragile, but maybe we do add a damage increase to even it out?). copy shocked node -> get shocked blade node (zaps/arcs)"* (owner, 2026-11-09; l.425-433) — `BladeVertexFill` reads the state at fill as it reads stats.
- *"so far there is *no* gameplay connection back to the source node after a blade node copy is made from it. not starting now"* (owner, 2026-11-09; l.434-440) — the fill is a read; the source keeps its stacks; the excess at fill is the vertex's power.
- *"maybe cold stacks slowing blade nodes sweeping over them (and heat stacks... should speed them up a lil?)"* (owner, 2026-11-08; l.45-49). It acts per contact: *"option 1 seems best"* (owner, 2026-11-10). The factor `clamp(1 + c·t/T, 1−c, 1+c)` scales the speed that the existing speed→damage curve reads for a contact on that node. No swing-clock warp and no sim change.
- A vertex's copied state reaches the gather as a "go-off source" argument (pass pick, tentative; kept 2026-11-10).
- The brittle vertex is a new per-vertex flag on `BladeState` beside `vertex_charges` (handoff § 1, seam facts) — reviewed, taken as settled. The Frozen vertex's concentrate snap is "one contact hit, then the vertex pops" (owner, 2026-11-09; l.441-455). This unit ships only the seat; #{ice} sets it.
- The blade-shared pieces go here, not "the first of 6/7/8 to land" (pass ruling, 2026-11-10).

**Knobs** (tentative defaults)
- `EntityStatBoard.blade_temperature_speed` (`c`) = 0.5: a board `ScalarStat` beside `blade_speed_half` (`stats_system/entity_stat_board.gd:204-208`, authored in `entity/default_entity_board.tres`; pass pick, tentative). Its def is bounded `[0, 0.95]` so `1 − c > 0`. It tunes how much terrain scales a contact's effective speed. Editor feedback: the melee sandbox's damage floaters on a swing across warm or cold nodes.
- Each element addon's authored innate load = the `ApplyStatusEffect.power` on its rider (authored per scene in #{fire} / #{lightning} / #{ice}; this unit's fixture uses 1).
- Tests assert direction and bounds (Cold lowers, Heat raises, never past `1 ± c`, `t = 0` bit-identical), never the literal 0.5.

**Composition**
- **The addon** is data on the existing `SkillNodeAddon` (template `skill_node/addons/defs/toxin_addon.tscn`). `on_hit_effects` is one `ApplyStatusEffect` whose `def` is the element's terrain StatusDef (#{defs}). It has no `entity_modifiers` and no `local_modifiers`, and `temp_cost_aspects = {<element>_element: 1}`. The budget already works: `MeleeAttackPlan.currency_cap` → `AspectCurrency.cap_of` by stat id. This unit ships the shape and a guard; the three `.tscn` and their looks land in #{fire} / #{lightning} / #{ice}.
- **The copy**: `BladeVertexFill.fill` copies each source node's two terrain ints (signed `t`, Charge; #{terrain}) and its T into per-vertex packed arrays on `BladeState`, zeroed in `build()`. A vertex's band and excess come from the same pure band function #{defs} owns, applied to the copy. No band enum is stored (a state remembers nothing). One spend method on `BladeState` decrements a vertex's copy; nothing writes `NodeState` from it. The old `vertex_charges` path is gone by now (#{catalyst-blade}).
- **The go-off source**: the blade landing site passes the gather (#{resolver}) an optional go-off source, which is the contacting vertex's copy (BladeState + `particle_idx`) plus its spend callable. The gather reads its bands beside the target node's and spends through it. `HitInstance` gains no blade field. What a Burning or Shocked vertex's go-off reads and reaches is #{fire} / #{lightning}'s (l.457-458); this unit proves the seat with a fixture `GoOff`.
- **The one-shot seat**: a per-vertex `PackedByteArray` beside the copies. `BladePopResolver.LiveGate.admit` admits a flagged vertex's first contact (the hit lands), then records the vertex dead at `ev.t` through `_kill`, so later contacts are refused. The spike pop (`:294-309`) refuses the popping contact, so it deals no damage; the one-shot contact lands. The pivot keeps today's exemption.
- **The sweep factor**: the two speed-curve call sites multiply the contact's `ev.speed` by the factor before `BladeState.speed_damage_multiplier`. They are `BladeDamageInstance.land_on` (authority, reading `t` and T off the contact's node in the gate's world) and `SkillBlade._speed_multiplier` (the cosmetic floater). The factor is a static helper on `BladeState` beside the curve, so the two sites cannot drift. A contact on an unallocated node never lands (`LiveGate.admit`), so the factor only ever meets allocated nodes. Peers take amounts from the record (ADR 0002); nothing re-decides.
- Dies: nothing. Readers: #{fire} / #{lightning} (go-off from the copy), #{ice} (sets the one-shot flag, Frozen vertex overlay), the melee sandbox panel.

**Files touched**
- `attack/melee/sim/blade_state.gd` — the copy arrays, the one-shot flag, the copy spend, the temperature speed helper.
- `attack/melee/blade_vertex_fill.gd` — the copy at fill.
- `attack/melee/sim/blade_pop_resolver.gd` — the one-shot branch in `LiveGate.admit`.
- `attack/melee/sim/blade_damage_instance.gd`, `attack/melee/skill_blade.gd` — the factor at both speed-curve sites; the cue.
- `stats_system/entity_stat_board.gd`, `entity/default_entity_board.tres`, a new `stats_system/defs/` entry — `c` (`manage-stats` skill).
- #{resolver}'s gather — the optional go-off-source argument; the blade landing site that passes it.
- `docs/domain/melee-blade-sim.md` — the copy, the one-shot seat, the temperature term under "Speed-scaled damage", the addons table.

**Acceptance**
1. `test/unit/attack/test_blade_vertex_terrain_copy.gd`: a blade filled from a source node whose `t` and Charge are past T carries each vertex's copy. Spending from a vertex copy leaves the source `NodeState` unchanged. A node under T copies to an inert vertex (its band answers none).
2. Same file: the preview fill (`SkillBlade.build_from_skill_nodes`) and the plan fill agree on the copy (one filler).
3. Same file: a contact from a vertex whose copy is primed hands the gather a go-off source. A fixture `GoOff` fires from it and spends the vertex copy, never the source or target node's ints.
4. `test/unit/attack/test_blade_one_shot_vertex.gd`: with the flag set by hand, the vertex's first contact lands its damage. Its next contact is refused, and the result records it dead at the first contact's `t`. An unflagged vertex is unchanged. `test_blade_pop_resolver.gd` and `test_spike_pop.gd` stay green unedited.
5. `test/unit/skill_node/test_element_addon_shape.gd`: every scene under `skill_node/addons/defs/` whose rider plants an element member status carries no stat modifier and costs exactly 1 of its `_element` count. A fixture addon on a blade member puts its rider on that vertex only, and a swing with count 0 cannot afford it. The directory walk is a pin for #{fire} / #{lightning} / #{ice} (it finds no element scene yet); the fixture carries this unit.
6. `test/unit/attack/test_blade_temperature_speed.gd`: at a fixed contact speed, a contact on a Cold node (`t < 0`) lands less than on `t = 0` and a Heat node more. The factor never leaves `[1 − c, 1 + c]`. A swing over `t = 0` is bit-identical to today's (`test_blade_swing_drag.gd`, `test_blade_whip_reach.gd` unedited). The authority amount and the cosmetic floater agree.
7. Visual (the blade speed/drag cue, handed over from #{terrain-ui}): the player can tell that a contact was sped up by Heat or slowed by Cold, on that contact's damage floater (the hit signal `SkillBlade` emits). Checked in the melee sandbox, with a screenshot in the report.

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Owner aside, parked: *"also maybe easiest: tune the PBD weight?"* (2026-11-10). This is not built here.
- `blade_state.gd:91`'s doc says spends are "recorded on the source nodes as cleanses". Do not carry that over to the element copy (owner: never the source).
- `.claude/rules/explosive.md` says a blade's node-side blast only reaches blade pieces. An element vertex's go-off reaches the board like any hit; #{catalyst} rewrites that rule.
- The Heat / Cold / Charge addon looks and the Burning / Frozen / Shocked vertex looks belong to #{fire} / #{lightning} / #{ice}.
- Permanent element addons on map nodes (procgen pools, `procgen/pools/addon_pool_entry.gd`) are not placed by this unit.
- A one-shot pivot: the seat keeps today's pivot exemption. If #{ice} needs a Frozen pivot to snap, that is an owner question.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:43-53 — the threshold model; the sweep-speed curve on signed t and its knob
docs/design/elements.md:410-458 — blade addon per element, copy-on-fill, spend the copy, the Frozen vertex snap
docs/design/elements.md:791-801 — pair table: a blade feels t of the node it sweeps over
attack/melee/blade_vertex_fill.gd:1-70 — the single per-vertex filler; charges copied at 42-49; addon dispatch at 58-60
attack/melee/sim/blade_state.gd:84-112 — per-vertex arrays: vertex_charges (91), vertex_on_hit (104-112)
attack/melee/sim/blade_state.gd:450-478 — speed_damage_multiplier and stat_value: where the factor helper sits
attack/melee/sim/blade_damage_instance.gd:25-45 — land_on: the gate, then amount × the speed curve
attack/melee/skill_blade.gd:543-547 — _speed_multiplier: the cosmetic floater's copy of the curve
attack/melee/sim/blade_pop_resolver.gd:271-309 — LiveGate.admit: unallocated refused; the spike pop refuses and kills
attack/melee/sim/blade_pop_resolver.gd:603-621 — _kill: the only place a vertex dies
skill_node/addons/defs/toxin_addon.tscn:20-55 — the rider-addon template: ApplyStatusEffect rider, temp_cost_aspects
attack/plan/melee_attack_plan.gd:476-512 — currency_cap / currency_spent: the count budget
attack/aspect_currency.gd:10-21 — cap_of / stat_of (reads the count role)
docs/domain/melee-blade-sim.md:239-276 — speed-scaled damage, two damage sites, determinism note
attack/melee/sim/blade_state.gd — seam: copy arrays, one-shot flag, spend, factor helper
attack/melee/skill_blade.gd — seam: the visual build fill site (188, 407-411) and the floater curve (547)
attack/plan/melee_attack_plan.gd — seam: owns the plan's BladeVertexFill (42)
addons/melee_sandbox/melee_sandbox_panel.gd — seam: reads per-vertex arrays (517)
ui/floating_number_layer/floater_director.gd — seam: the damage-number path the cue rides
skill_node/addons/skill_node_addon.gd — seam: apply_to_blade appends riders; temp costs
stats_system/entity_stat_board.gd — seam: blade speed ScalarStat exports (204-208)
attack/melee/temp_upgrade_catalog.gd — seam: scans addons/defs for temp upgrades
```
