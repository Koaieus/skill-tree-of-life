The forge's element field: a cast carries at most one element, the forge adds to it or replaces it, three int:int units per spell, and `lightning_bolt` gains Charge as its innate element. Child of hub #1716; design home `docs/design/elements.md` § The forge. Its sibling `quiver` is the ammo half of child 9 (element arrows, starter counts, #1765); the two share no file.

Blocked by: #{refresh}, #{fire}, #{lightning}, #{ice}
Blocks: #{forge-ui}

## Acceptance spec

**Decisions**
- *"the spell should carry at most one Element (fire/cold/lightning) and if a spell already has one, forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"* (owner, 2026-11-09; `docs/design/elements.md:380-389`, ADR 0081 §7).
- The slot loads Heat, Cold or Charge, *"not really things like Fuel"*; Catalyst rides as its own aspect row (owner, 2026-11-09; `elements.md:386-389`).
- *"spells could use a separate elemental affinity (3 units of int:int, for fire/ice/lightning, befitting the forge's elemental slot …)"* (owner, 2026-11-08; `elements.md:586-590`), settled as one element field per cast (2026-11-09).
- `lightning_bolt` carries Charge as a Charge ride row, its innate element; nothing else carries an innate element in v1 (the doc's owner-attributed v1 spell bullet, 2026-11-09; `elements.md:1052-1053, 1076`). It keeps its name: *"(a) Keep the name lightning_bolt for now"* (owner, 2026-11-10).
- Ice on a cast is Needs design (#{ice-cast}): *"yeah needs design that one, just stub it as an unconditional ×1 until we fix it/decide on it"* (owner, 2026-11-10). So an Ice load on a cast leaves `max_hops` alone and scales the seed ×1; the Cold ride row still plants Cold. The new Cold spell is #1789 (Needs design) and is not built here.
- The forge budget stays keyed by concept — one `ice` count budgets every Ice row (pass pick, tentative; `elements.md:1129-1133`).
- The element field is not an aspect slot: it never counts toward `infusion_slots` (*"The aspect slots are untouched"*, `elements.md:385-386`) and stays outside `SpellDef.infusion_capacity` (pass pick, tentative).
- An element's three units are the spell's element intake rows' existing `affinity_gain:affinity_cost` (ADR 0060), one per element, an unlisted element trading 1:1 as an unlisted aspect does today (pass pick, tentative: the doc's Ice pricing already reads *"the Ice row's int:int affinity"*, `elements.md:580-583`; a second rate seat on `SpellDef` would mirror the row).

**Knobs** (tentative defaults — easy to change)
- `lightning_bolt`'s Charge row `AspectIntake.innate` = 1 — the innate Charge load per landing; authored in `attack/spell/defs/lightning_bolt.tres`, read in the inspector.
- Per-spell element affinities: none authored here (every v1 spell trades 1:1 on all three elements).

**Composition**
- `Infusion` owns the cast's element: one id + its points, a field beside `points` (aspects), never a key inside it. It exposes `element_of(spell) -> StringName` — the forged element if set, else the spell's innate element (the element of its element intake rows; at most one per def, a test guards it), else empty — the one answer for "which element does this cast carry" (#1789's Thermal shock and #{resolver}'s "a hit carries 0 or 1 element" read it).
- `load_of(spell)`: same element as the innate → its points add `gained` to that element's rows (add); a different element → every innate row of the innate element is *suppressed for this cast* (not removed from the def) and the chosen element's load is `gained(points)` through its row or 1:1 unlisted, spent through `use_of` (replace). Suppression (not deletion) keeps a later Ice `shape` row swappable: when #{ice-cast} is designed, its row drops out on a forged Fire or Lightning by this same rule.
- Ice stub: an Ice element on a cast spends through the Cold ride use only; nothing rewrites hops or multiplies the seed (×1). No `shape` use class lands here.
- `MagicAttackPlan` gains one setter for the element (id, points; 0 clears), `aspect_overrun` adds element points above the element's COUNT (through `AspectCurrency.cap_of`), and the wire dict carries the element beside `"infusion"`; `from_dict` reads it ungated as today (ADR 0035). `ArmedStack`'s per-spell memory remembers it with the points.
- `AspectCurrency.stat_of` maps a concept to its COUNT facet (`fire_element` / `ice_element` / `lightning_element`, #{defs}; it may already); an element id resolves the same way an aspect id does.
- Dies: nothing. `lightning_bolt.tres` gains one intake row naming Charge (#{defs}' row-names-its-status shape).

**Files touched**
- `attack/spell/infusion.gd` — the element field, `element_of`, add/replace in `load_of`.
- `attack/plan/magic_attack_plan.gd` — element setter, overrun term, wire.
- `attack/aspect_currency.gd` — only if #{defs} left the `<concept>_aspect` mapping.
- `systems/armed/armed_stack.gd` — remembered element.
- `attack/spell/defs/lightning_bolt.tres` — the Charge ride row; the name stays (owner, 2026-11-10); #{lightning} may touch the same file.
- `test/unit/spell/test_infusion.gd`, `test/unit/attack/test_attack_plan_wire.gd`, `test/unit/attack/test_magic_attack_plan.gd`, `test/unit/spell/test_spell_defs.gd`.

**Acceptance**
1. `test_infusion.gd`: a spell with an innate Charge row, cast with Charge points → its Charge load is innate + `gained`; cast with Heat points instead → its Charge load is 0 and its Heat load is `gained` at the Heat row's ratio (1:1 when unlisted). `element_of` answers the forged element, else the innate one, else empty.
2. `test_infusion.gd`: forging a different element leaves the `SpellDef`'s rows untouched (re-read the def after the cast: same rows, same innate).
3. `test_infusion.gd`: element points never change `slots_used()`; a cast with full aspect sockets still takes an element.
4. `test_magic_attack_plan.gd`: element points above the caster's element COUNT show in `aspect_overrun()` as the excess; within the count, 0. Assert the relation to the count, never a literal.
5. `test_attack_plan_wire.gd`: a plan with an element round-trips through `to_dict` / `from_dict` with id and points intact; a plan with no element writes no element key (the existing wire shape unchanged).
6. `test_spell_defs.gd`: every spell def carries at most one element across its element rows; `lightning_bolt` carries Charge.
7. `test_infusion.gd`: an Ice load on a spell with authored `max_hops` leaves the resolved `max_hops` and the seed payload as without Ice, and lands Cold riders at the Ice load.
8. `mise run mp:e2e` stays green (it gates `command/`; the wire changed).

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- Ice concentrate (the `shape` use, its pricing, the preview) is #{ice-cast}'s, Needs design; this unit ships the ×1 stub only.
- The AI's infusion picker (`entity/controller/ai_infusion_picker.gd`) forges no element in this unit — parked; the AI casts innate.
- The forge's display (innate element, add or replace, the units, why a spell refuses Ice, the hop change) is `forge-ui`'s. No visual lands here.
- ADR 0081 §7's "orthogonal to its subtype" is stale (the doc deleted it, `elements.md:399-400`); the correction rides the next element ADR, a sibling issue, not this unit.
- Which inner-tree shape holds the elements is a sibling issue in Needs design.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:362-411 — the row type, ride vs shape, one element per cast, add or replace, no Fuel in the slot; an arrow is a subtype or an element (the "orthogonal" passage is gone)
docs/design/elements.md:580-600 — the Ice row's int:int affinity, the "3 units" quote, ride and shape as two rows on one count
docs/design/elements.md:1052-1076 — v1 spell content: lightning_bolt carries Charge, the Cold spell is #1789
docs/design/elements.md:1129-1133 — the forge budget stays keyed by concept
docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md:33-34 — §7 one element per cast, §8 the three units
attack/spell/infusion.gd:13-101 — points, slots_used, intake_of, ratio_of, gained, load_of
attack/spell/infusion.gd:112-142 — use_of and bag: where a load spends through its use
attack/spell/aspect_intake.gd:18-75 — the row: identity, innate, affinity, use
attack/plan/magic_attack_plan.gd:154-158 — the infusion on the wire (to_dict)
attack/plan/magic_attack_plan.gd:175-177 — from_dict reads it ungated
attack/plan/magic_attack_plan.gd:677-690 — set_infusion, the setter shape to mirror
attack/plan/magic_attack_plan.gd:754-771 — aspect_overrun, the host's launch check
attack/spell/defs/lightning_bolt.tres:58-72 — no intakes line today
attack/aspect_currency.gd — seam: concept → count stat id, read by cap_of
systems/armed/armed_stack.gd — seam: per-spell infusion memory (:109, :119)
systems/battle_system.gd — seam: launch refuses on aspect_overrun (:506)
attack/spell/spell_resolver.gd — seam: ctx.load = load_of (:165)
entity/controller/ai_infusion_picker.gd — seam: AI picker, untouched (NOTES)
ui/hud/command_tray/bodies/readout_lines.gd — seam: reads load_of / points (forge-ui's)
test/unit/spell/test_infusion.gd — seam: the unit tests
test/unit/attack/test_attack_plan_wire.gd — seam: wire round-trip pin
test/unit/attack/test_magic_attack_plan.gd — seam: overrun
test/unit/spell/test_spell_defs.gd — seam: names lightning_bolt
tools/balance/balance_scenarios.gd — seam: names lightning_bolt
```
