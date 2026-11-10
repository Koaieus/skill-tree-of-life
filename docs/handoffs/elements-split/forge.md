The forge's element field: a cast carries at most one element, the forge adds to it or replaces it, three int:int units per spell, `lightning_bolt` gains Charge as its innate element, and every entity starts with 1 in each element count and Catalyst (the dev sandbox Player 3). Child of hub #1716; design home `docs/design/elements.md` § The forge and § Acquisition. Its sibling `quiver` is the ammo half of child 9 (element arrows, their bins and stock cap, #1765, which `quiver` closes, not this unit); the two share no file.

Blocked by: #{fire}, #{lightning}, #{ice}
Blocks: #{forge-ui}

## Acceptance spec

**Decisions**
- *"the spell should carry at most one Element (fire/cold/lightning) and if a spell already has one, forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"* (owner, 2026-11-09; `docs/design/elements.md:380-389`, ADR 0081 §7).
- The slot loads Heat, Cold or Charge, *"not really things like Fuel"*; Catalyst rides as its own aspect row (owner, 2026-11-09; `elements.md:386-389`).
- *"spells could use a separate elemental affinity (3 units of int:int, for fire/ice/lightning, befitting the forge's elemental slot …)"* (owner, 2026-11-08; `elements.md:586-590`), settled as one element field per cast (2026-11-09).
- `lightning_bolt` carries Charge as a Charge ride row, its innate element; nothing else carries an innate element in v1 (the doc's owner-attributed v1 spell bullet, 2026-11-09; `elements.md:1052-1053, 1076`). It keeps its name for now (owner picked keeping it, 2026-11-10).
- Shapes on a cast, Ice's concentrate among them, are Needs design (#{ice-cast}); here an element on a cast is a ride only: *"yeah needs design that one, just stub it as an unconditional ×1 until we fix it/decide on it"* (owner, 2026-11-10). So an Ice load on a cast leaves `max_hops` alone and scales the seed ×1; the Cold ride row still plants Cold. The new Cold spell is #1789 (Needs design) and is not built here.
- Starter 1 goes to every entity as the stat's default value: *"every entity. and possibly later we can decide to replace it with statmodifiers innate, meaning they can get looted too."* (owner, 2026-11-10). Starter count: *"1 in each for now, 3 each for the dev_sandbox's Player (for instant testing)"* (owner, 2026-11-09; `elements.md:996-999`); Catalyst starts at 1, 3 for the dev sandbox Player, the same interim rule (owner, 2026-11-09; `:999-1003`). The dev sandbox Player's 3 is a grant in `dev_sandbox.gd` (Composition).
- The forge budget stays keyed by concept — one `ice` count budgets every Ice row (pass pick, tentative; `elements.md:1129-1133`).
- The element field is not an aspect slot: it never counts toward `infusion_slots` (*"The aspect slots are untouched"*, `elements.md:385-386`) and stays outside `SpellDef.infusion_capacity` (pass pick, tentative).
- An element's three units are the spell's element intake rows' existing `affinity_gain:affinity_cost` (ADR 0060), one per element, an unlisted element trading 1:1 as an unlisted aspect does today (pass pick, tentative: the doc's Ice pricing already reads *"the Ice row's int:int affinity"*, `elements.md:580-583`; a second rate seat on `SpellDef` would mirror the row).

**Knobs** (tentative defaults — easy to change)
- `lightning_bolt`'s Charge row `AspectIntake.innate` = 1 — the innate Charge load per landing; authored in `attack/spell/defs/lightning_bolt.tres`, read in the inspector.
- Per-spell element affinities: none authored here (every v1 spell trades 1:1 on all three elements).
- Starter count 1 (owner number): `StatDef.default_value` on `fire_element`, `ice_element`, `lightning_element` (#{defs} creates them with 0) and Catalyst's count def.
- `DevSandbox.starter_count_bonus` (`@export_range(0, 20)`) = 2.0 — added to each of the four counts on the sandbox Player only, so it reads 3 (owner number); inspector on `dev_sandbox.tscn`'s root.

**Composition**
- `Infusion` owns the cast's element: one id + its points, a field beside `points` (aspects), never a key inside it. It exposes `element_of(spell) -> StringName` — the forged element if set, else the spell's innate element (the element of its element intake rows; at most one per def, a test guards it), else empty — the one answer for "which element does this cast carry" (#1789's Thermal shock and #{forge-ui} read it). #{resolver}'s gather does not call it and needs no new read: the cast's element reaches the gather as the element rider (Heat / Cold / Charge) that the element's ride row plants through `load_of` → the cast's `LoadBag` → the seed landing, so "a hit carries 0 or 1 element" holds because `load_of` suppresses the innate element's rows on a replace. This unit adds nothing to the gather.
- `load_of(spell)`: same element as the innate → its points add `gained` to that element's rows (add); a different element → every innate row of the innate element is *suppressed for this cast* (not removed from the def) and the chosen element's load is `gained(points)` through its row or 1:1 unlisted, spent through `use_of` (replace). Suppression (not deletion) keeps a later Ice `shape` row swappable: when #{ice-cast} is designed, its row drops out on a forged Fire or Lightning by this same rule.
- Ice stub: an Ice element on a cast spends through the Cold ride use only; nothing rewrites hops or multiplies the seed (×1). No `shape` use class lands here.
- `MagicAttackPlan` gains one setter for the element (id, points; 0 clears), `aspect_overrun` adds element points above the element's COUNT (through `AspectCurrency.cap_of`), and the wire dict carries the element beside `"infusion"`; `from_dict` reads it ungated as today (ADR 0035). `ArmedStack`'s per-spell memory remembers it with the points.
- `AspectCurrency.stat_of` maps a concept to its COUNT facet (`fire_element` / `ice_element` / `lightning_element`, #{defs}; it may already); an element id resolves the same way an aspect id does.
- Starter counts: each count's `StatDef.default_value` = 1 (the counts are minted facets, `EntityStatBoard.mint_facets`, so there is no board field to author). The dev sandbox's 3 is `DevSandbox._setup_level` granting one ADD_BASE `StatModifier` of `starter_count_bonus` per count through `player.grant_core_modifier`, the seat the file's header names for sandbox-only tuning and `test_dev_sandbox_board.gd` pins ("default base + the sandbox's bonus, not a forked base_value"). The element ammo types that consume the counts are #{quiver}'s.
- Dies: nothing. `lightning_bolt.tres` gains one intake row naming Charge (#{defs}' row-names-its-status shape).

**Files touched**
- `attack/spell/infusion.gd` — the element field, `element_of`, add/replace in `load_of`.
- `attack/plan/magic_attack_plan.gd` — element setter, overrun term, wire.
- `attack/aspect_currency.gd` — only if #{defs} left the `<concept>_aspect` mapping.
- `fire_element` / `ice_element` / `lightning_element` count defs (#{defs} creates them) and the Catalyst count def (`stats_system/defs/explosive_aspect.tres` today, retagged by #{catalyst}) — `default_value`.
- `scenes/dev_sandbox.gd` — `starter_count_bonus` and the four grants.
- `systems/armed/armed_stack.gd` — remembered element.
- `attack/spell/defs/lightning_bolt.tres` — the Charge ride row; the name stays (owner, 2026-11-10); #{lightning} may touch the same file.
- `test/unit/spell/test_infusion.gd`, `test/unit/attack/test_attack_plan_wire.gd`, `test/unit/attack/test_magic_attack_plan.gd`, `test/unit/spell/test_spell_defs.gd`, `test/integration/scenes/test_dev_sandbox_board.gd`.

**Acceptance**
1. `test_infusion.gd`: a spell with an innate Charge row, cast with Charge points → its Charge load is innate + `gained`; cast with Heat points instead → its Charge load is 0 and its Heat load is `gained` at the Heat row's ratio (1:1 when unlisted). `element_of` answers the forged element, else the innate one, else empty.
2. `test_infusion.gd`: forging a different element leaves the `SpellDef`'s rows untouched (re-read the def after the cast: same rows, same innate).
3. `test_infusion.gd`: element points never change `slots_used()`; a cast with full aspect sockets still takes an element.
4. `test_magic_attack_plan.gd`: element points above the caster's element COUNT show in `aspect_overrun()` as the excess; within the count, 0. Assert the relation to the count, never a literal.
5. `test_attack_plan_wire.gd`: a plan with an element round-trips through `to_dict` / `from_dict` with id and points intact; a plan with no element writes no element key (the existing wire shape unchanged).
6. `test_spell_defs.gd`: every spell def carries at most one element across its element rows; `lightning_bolt` carries Charge.
7. `test_infusion.gd`: an Ice load on a spell with authored `max_hops` leaves the resolved `max_hops` and the seed payload as without Ice, and lands Cold riders at the Ice load.
8. `test_dev_sandbox_board.gd`: the sandbox Player's four counts each read the default count + `starter_count_bonus`; the sandbox Enemy reads the default. Assert the relation, never the literal 3.
9. A fresh non-sandbox entity on `default_entity_board.tres` reads each count's `StatDef.default_value` (relation, never the literal 1).
10. `mise run mp:e2e` stays green (it gates `command/`; the wire changed).

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- Ice concentrate (the `shape` use, its pricing, the preview) is #{ice-cast}'s, Needs design; this unit ships the ×1 stub only.
- The AI's infusion picker (`entity/controller/ai_infusion_picker.gd`) forges no element in this unit — parked; the AI casts innate.
- The forge's display (innate element, add or replace, the units, why a spell refuses Ice, the hop change) is `forge-ui`'s. No visual lands here.
- ADR 0081 §7's "orthogonal to its subtype" is stale (the doc deleted it, `elements.md:399-400`); the correction rides the next element ADR, a sibling issue, not this unit.
- Which inner-tree shape holds the elements is a sibling issue in Needs design.
- Parked (owner, 2026-11-10): the starter may later move from `StatDef.default_value` to innate stat modifiers (e.g. `default_entity_board.tres`'s `intrinsic_modifiers`, `:673`) so it can be looted. Not now. A `CoreClass` grant is not the sandbox seat: `balanced_core.tres` is a real pickable class.
- The default change is suite-wide: Catalyst's count 0 → 1 changes every AI reload and volley composition. Grep `test/` for reload, quiver-content and volley assertions and re-point them (never delete); the full suite is the gate, not `test:dir`.
- The facets must be minted before the sandbox grants land: `mint_facets` runs inside `apply_intrinsics`, and `_setup_level` grants after `super()`, as `blade_size` does today.
- `dev_sandbox.gd:13`'s `_SANDBOX_BLADE_SIZE_BONUS` is a `const` against the tunables rule; the new knob is an `@export`. Converting the old one is a drive-by the drone may take.
- The later direction (all counts start at 0; gains from the inner tree, core class, metagame, keystones) is not built; #1787 generator keystones is its own issue.

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
docs/design/elements.md:989-1009 — Acquisition: starter 1 each, dev sandbox Player 3, Catalyst the same
scenes/dev_sandbox.gd:1-31 — sandbox-only tuning as core modifiers on the live board
test/integration/scenes/test_dev_sandbox_board.gd:1-55 — the pins for that pattern
stats_system/defs/explosive_aspect.tres:6-16 — a count def, default_value 0.0 (:15)
stats_system/entity_stat_board.gd:222-238 — counts are minted facets (mint_facets)
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
