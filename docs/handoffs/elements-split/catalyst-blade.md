This unit removes the blade's explosive path: per-vertex charges, the two-sided contact (ADR 0062's formula), the charge beads, and a barrel on the blade. Catalyst never goes off (`elements.md:120-122`), and a vertex copies only a *primed* state (`:425-433`), which #{blade-elements} rebuilds generically. It is spine unit 10 of the #1716 split. Design home: `docs/design/elements.md`.

Blocked by: #{catalyst}
Blocks: #{refresh}

## Acceptance spec

**Decisions**
- Catalyst is *"one aspect status, inert and colourless: it never counts toward T, never primes, never goes off and has no derived state"*. That is the doc's statement of the owner's call: *"yeahhh exactly option 1. w/visually like purple crystals or smth instead of black goo"* (owner, 2026-11-09; `:120-122`, `:166-170`).
- *"copy a burning node and you get a burning blade node (booms). copy frozen node -> frozen blade node … copy shocked node -> get shocked blade node (zaps/arcs)"* (owner, 2026-11-09; `:425-433`). A vertex carries its node's primed state. Charges are not that state, and Catalyst has none.
- The blade-side teardown is its own unit after the retag (owner, 2026-11-10, on the blast-gap split: *"option 1 but spare no drones, split if needed"*).
- The deletion of ADR 0062's two-reservoir blade formula sits here. It is a pass assignment from the split, taken as settled.

**Knobs** — none survive. `BladePopResolver.LiveGate.warhead_reach` and `shrapnel_fraction` are deleted with the path they tune (written call).

**Composition**
- What remains is a contact that lands one hit. (The blast no longer popping plain blade pieces is a pass call, parked in NOTES.) A primed struck node goes off through #{resolver}'s gather, as any hit does. Nothing on the blade holds or spends a charge, and no blast reaches blade pieces.
- **Dies:**
  - `BladeState.vertex_charges`, and its zero-fill in `build()`.
  - `BladeVertexFill`'s Catalyst read (the `EXPLOSIVE` const, lines 42-49). The fill keeps its stats and `vertex_shielded`.
  - From `BladePopResolver.LiveGate`: `_admit_explosive`, `_piece_pass`, `piece_charges`, `_spend_piece`, `_spend_node`, `explosive_def`, `arm_blasts`, the two knobs, and the explosive fields of `Contact` (`piece_reach`, both powers, the piece verdicts SPENT / SHRUG on charges). Read `Result.contacts` first: if it has no other user, it dies too.
  - In `swing_resolve.gd`: whatever of the charged-piece path remains. #{go-off-zero} already deleted the node-spend handover (`_append_spends`, `_flush_spends` and their calls) and moved the board-blast arming (`arm_blasts`) onto the gather, so the line numbers here are cut before it; grep, and delete only what is left.
  - `BladeNode.charges`, the spend flare, the shrug sheen, and `ChargeBand` (`blade_charge_band.gd` and the `blade_node.tscn` node).
  - `BladeStyle.charge_band_width`, `charge_tier`, `charge_identity`, `charge_color`, and the sheen/ring colour that reads them.
  - `SkillBlade._build_charges`, `_snapshot_build_charges`, `_charges_at`, the spent-count helper, and the piece-blast rings.
  - The melee sandbox's charge-bead and blast-ring controls.
  - `CatalystBarrelAddon.apply_to_blade`'s temp half. A temp barrel then adds nothing to a swing (the map barrel's Catalyst refill stays).
- **`vertex_shielded`** (deflection) has its own reader: keep it, and its shrug path for non-charge reasons, if any survives.

**Files touched** — the seam map. #{blade-elements} later adds the generic copy-on-fill to `blade_vertex_fill.gd` and `blade_state.gd`, so leave clean seats and no dead fields.

**Acceptance**
1. Characterization first: `test_blade_explosive.gd` and `test_blade_piece_charges.gd` are deleted with the path they pin. Every other melee test passes un-re-pointed, including `test_blade_severance`, the melee pop and fill tests, and `test_catalyst_barrel_addon` (minus its temp-barrel-on-blade case, which is deleted).
2. New test `test/unit/attack/test_blade_contact_on_primed_node.gd`, red first. A blade contact on a Burning node lands one hit, and the node's disc goes off through the gather. A contact on a node holding only Catalyst blasts nothing and spends no Catalyst.
3. `git grep -n -i "vertex_charges\|piece_charges\|_admit_explosive\|charge_band\|explosive"` over `attack/melee/`, `skill_node/addons/` and `addons/melee_sandbox/` returns nothing.
4. `docs/domain/melee-blade-sim.md` § "Explosive charges: `vertex_charges` and the two-sided contact" (from line 724) is deleted. Any line elsewhere in that doc naming charges is fixed. The blade passage of `docs/domain/catalyst.md` goes.
5. `.claude/rules/explosive.md` is deleted, since its last claim dies here. `mise run rules-hygiene` and `mise run docs-hygiene` are clean.
6. Visual: a swung piece shows no beads, flare or sheen. Nothing replaces them here; #{blade-elements} and the element units draw vertex states.

**NOTES**
- Reading list and seam map were cut before #{resolver} and #{go-off-zero} landed. #{go-off-zero} moved these lines. The dispatching lead re-checks `mise run issue-drift`; if it still flags this issue, stop and say so.
- Parked, not decided by the owner (pass call): the behaviour that leaves with no replacement in the design, a node's blast popping plain blade pieces (ADR 0062's node side). If play misses it, that is a new design issue for the owner, not this unit.
- ADRs 0061, 0062 and 0070 (`DetonateUse` / `FuelUse`, the default face, the two-sided blade) join ADR 0081 §5-§7 and §9 and ADR 0082's Context in the sibling issue for ADR corrections. Write no ADR here.
- The `.claude/rules/blade-budget-and-clamps.md` budget for temp addons is untouched: a temp barrel still costs its slot until the element addons arrive.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:115-174 — Catalyst never goes off
docs/design/elements.md:418-458 — the blade's element addon and the vertex copy rule #{blade-elements} builds
docs/domain/explosive.md:123-158 — the two-sided contact being removed
docs/domain/melee-blade-sim.md:724-740 — the passage to delete
attack/melee/sim/blade_pop_resolver.gd:224-240 — LiveGate knobs and ledgers
attack/melee/sim/blade_pop_resolver.gd:324-460 — the explosive contact path
attack/melee/blade_vertex_fill.gd:21-49 — the vertex charge read
attack/melee/sim/blade_state.gd:85-91 — vertex_charges
attack/melee/skill_blade.gd:405-490 — build charges and piece-blast rings
attack/melee/sim/blade_state.gd — seam: delete vertex_charges
attack/melee/blade_vertex_fill.gd — seam: delete the charge read
attack/melee/sim/blade_pop_resolver.gd — seam: delete the explosive contact path
attack/melee/swing_resolve.gd — seam: delete handover, piece blast, charge landing
attack/melee/blade_node.gd — seam: delete charges, flare, sheen
attack/melee/blade_node.tscn — seam: ChargeBand node goes
attack/melee/blade_charge_band.gd — seam: delete
attack/melee/blade_style.gd — seam: delete charge_*
attack/melee/skill_blade.gd — seam: delete build charges and rings
addons/melee_sandbox/melee_sandbox_panel.tscn — seam: charge controls go
skill_node/addons/explosive_barrel_addon.gd — seam: (catalyst_barrel_addon.gd by then) temp blade half goes
test/unit/attack/test_blade_explosive.gd — seam: delete
test/unit/attack/test_blade_piece_charges.gd — seam: delete
docs/domain/melee-blade-sim.md — seam: section deleted
.claude/rules/explosive.md — seam: delete
```
