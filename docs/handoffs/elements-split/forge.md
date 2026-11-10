The forge's two element fields, the data side: a cast carries a **shape** field and a **ride** field beside its aspect slots (ADR 0085 §1), the ride's points count against the spell's total-points cap with the aspects' (ADR 0085 §2), `lightning_bolt` gains Charge as its innate ride, and every entity starts with 1 in each element count and Catalyst (the dev sandbox Player 3). Child of hub #1716; design home `docs/design/elements.md` § Shape and ride ("Three kinds of slot"), § The forge and § Acquisition. This unit stores, checks and ships the two fields; what a shape does to a cast is #{ice-cast}'s, and the per-node capacity, the caster gate and the socket-time cap are #{overqualified-casting}'s. Its sibling `quiver` is the ammo half of child 9 (element arrows, their bins and stock cap, #1765, which `quiver` closes, not this unit); the two share no file.

Blocked by: #{fire}, #{lightning}, #{ice}
Blocks: #{forge-ui}, #{ice-cast}, #{overqualified-casting}

## Acceptance spec

**Decisions**
- Three kinds of slot: *"one slot determines the color of the crystal in your wand {= reach}, another slot for elemental payload {at most 1}, and 'regular' slots besides that"* (owner, 2026-11-10; `docs/design/elements.md` § Shape and ride, "Three kinds of slot"; ADR 0085 §1). The one element field of 2026-11-09 is the cast's **shape**; a second field holds the **ride**, one terrain element at most, so a hit still carries 0 or 1 element; the aspect slots are untouched.
- Each field adds to or replaces the spell's authored default for that field: *"the spell should carry at most one Element (fire/cold/lightning) and if a spell already has one, forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"* (owner, 2026-11-09; § The forge; ADR 0081 §7 as ADR 0085 §1 splits it). The doc: a spell authors a default for each (or none) and the forge lets the caster replace or add to either (§ Shape and ride).
- Shape and ride may be different elements, each drawing its own count; the same element splits one count between them: *"say you got 3 Fire … you can spend 1 there and 2 on Heat for 2 Heat stack riders"* (owner, 2026-11-10; ADR 0085 §1). The spell's authored baseline is free on top: it draws no count and no capacity.
- The ride takes no aspect slot (never counts toward `infusion_slots`), and its points count against `SpellDef.infusion_capacity` together with the aspects' points (owner, 2026-11-10, picked *own slot, points count against spell capacity*: *"option 1, good solution"*; ADR 0085 §2).
- Whether shape points count against that cap too is open (ADR 0085 revisit-when). Pass pick, tentative: they do not. The answer lives in one function (`Infusion.total_points()`, Composition).
- A field loads Heat, Cold or Charge, *"not really things like Fuel"*; Catalyst rides as its own aspect row (owner, 2026-11-09; § The forge).
- `lightning_bolt` carries Charge as a Charge ride row, its innate element; nothing else carries an innate element in v1, and no v1 spell authors a shape default (the doc's owner-attributed v1 spell bullet, 2026-11-09; § Open). It keeps its name for now (owner picked keeping it, 2026-11-10).
- The shape field is inert in this unit: the doc's *until it lands an element on a cast is a ride only* (§ Shape and ride). It is stored, checked against its count, remembered and carried on the wire, and changes nothing about the walk, the seed or the load. What each element's shape does on a cast (ADR 0084) is #{ice-cast}'s. The new Cold spell is #1789 (Needs design) and is not built here.
- The capacity a node has for a spell (base + bonus per degree above `min_degree`), the loadout gating the caster, and enforcing the cap at socketing and at source gathering (ADR 0085 §3, §4, Consequences) are #{overqualified-casting}'s. Here `infusion_capacity` keeps its per-spell value (infinite on every spell today) and is tested where it is tested today: per spell, at launch.
- Starter 1 goes to every entity as the stat's default value (owner, 2026-11-10); it may later move to innate stat modifiers so it can be looted (NOTES). Starter count: *"1 in each for now, 3 each for the dev_sandbox's Player (for instant testing)"* (owner, 2026-11-09; § Acquisition); Catalyst starts at 1, 3 for the dev sandbox Player, the same interim rule (owner, 2026-11-09; § Acquisition). The dev sandbox Player's 3 is a grant in `dev_sandbox.gd` (Composition).
- The forge budget stays keyed by concept: one `ice_element` count budgets the Ice shape and the Ice ride (pass pick, tentative; § Open, adversarial review (a)).
- The ride's exchange is the spell's ride intake row's existing `affinity_gain:affinity_cost` (ADR 0060), an unlisted element trading 1:1 as an unlisted aspect does today (pass pick, tentative; a second rate seat on `SpellDef` would mirror the row). A shape point is not exchanged here: it is counted 1:1 against the count, and what a point buys is #{ice-cast}'s.

**Knobs** (tentative defaults — easy to change)
- `lightning_bolt`'s Charge row `AspectIntake.innate` = 1 — the innate Charge load per landing; authored in `attack/spell/defs/lightning_bolt.tres`, read in the inspector.
- Per-spell element affinities: none authored here (every v1 spell trades 1:1 on all three elements).
- `SpellDef.infusion_capacity`: not authored here; every spell stays infinite until #{overqualified-casting} sets the base.
- Starter count 1 (owner number): `StatDef.default_value` on `fire_element`, `ice_element`, `lightning_element` (#{defs} creates them with 0) and Catalyst's count def.
- `DevSandbox.starter_count_bonus` (`@export_range(0, 20)`) = 2.0 — added to each of the four counts on the sandbox Player only, so it reads 3 (owner number); inspector on `dev_sandbox.tscn`'s root.

**Composition**
- `Infusion` owns four fields beside `points` (the aspects), never keys inside it: `shape_element: StringName`, `shape_points: int`, `ride_element: StringName`, `ride_points: int`. An empty id or 0 points is "nothing forged" for that field.
- The two reads of "which element": `Infusion.ride_of(spell) -> StringName` — the forged ride if set, else the spell's innate ride element (the element of its element ride rows; at most one per def, a test guards it), else empty; `Infusion.shape_of(spell) -> StringName` — the forged shape if set, else the spell's authored shape default, else empty. No shape row exists in this unit, so the default is always empty here; #{ice-cast} adds the shape row and fills that branch. `ride_of` is the one answer to "which element does this cast's hit carry" (#1789's Thermal shock and #{forge-ui} read it).
- One total against the capacity: `Infusion.total_points() -> int` = the aspects' points + `ride_points`. `shape_points` is not in it (the tentative pick above; flipping it is this one function). It is the number `aspect_overrun()` tests and the number #{forge-ui} shows as "used"; nobody else sums points.
- One spend per element: `Infusion.spent_on(element) -> int` = `shape_points` if the shape is that element + `ride_points` if the ride is. The count check and #{forge-ui}'s "count left for the other socket" both read it.
- `slots_used()` is unchanged: neither field is an aspect slot.
- `load_of(spell)`, the ride only: same element as the innate ride → its points add `gained` to that element's ride rows (add); a different element → every innate ride row of the innate element is *suppressed for this cast* (not removed from the def) and the chosen element's load is `gained(ride_points)` through its ride row or 1:1 unlisted, spent through `use_of` (replace). The shape field never enters `load_of`, `bag` or `riders`. #{resolver}'s gather needs no new read: the ride reaches it as the element rider (Heat / Cold / Charge) the ride row plants through `load_of` → the cast's `LoadBag` → the seed landing, so "a hit carries 0 or 1 element" holds because `load_of` suppresses the innate element's rows on a replace.
- `MagicAttackPlan` gains `set_shape(id, points)` and `set_ride(id, points)` (0 clears), mirroring `set_infusion`. `aspect_overrun()` adds, per element named by either field, `max(0, spent_on(element) − count)` (the count through `AspectCurrency.cap_of`; a shared element is tested once, as the sum), and every ride point on an element the spell refuses (rate 0). Its existing total-points term is unchanged in form — `total_points()` above `floor(spell.infusion_capacity)` when finite — and so now carries the ride. It stays a per-spell read at launch; #{overqualified-casting} re-points it at the casting node's capacity and adds the socket-time and source-gather checks.
- Wire: `to_dict` writes `"shape"` and `"ride"` beside `"infusion"`, each `{id, points}` and each only when set; `from_dict` reads them ungated as today (ADR 0035).
- `ArmedStack`'s per-spell memory remembers both fields with their points; `clamp_infusion` re-clamps them so `aspect_overrun()` is 0: aspects fill first as today, then the ride takes `min(remembered, count − shape's spend on the same element, what the capacity leaves)`, the shape `min(remembered, count)` (the order is a pass pick, tentative).
- `AspectCurrency.stat_of` maps a concept to its COUNT facet (`fire_element` / `ice_element` / `lightning_element`, #{defs}; it may already); an element id resolves the same way an aspect id does.
- Starter counts: each count's `StatDef.default_value` = 1 (the counts are minted facets, `EntityStatBoard.mint_facets`, so there is no board field to author). The dev sandbox's 3 is `DevSandbox._setup_level` granting one ADD_BASE `StatModifier` of `starter_count_bonus` per count through `player.grant_core_modifier`, the seat the file's header names for sandbox-only tuning and `test_dev_sandbox_board.gd` pins ("default base + the sandbox's bonus, not a forked base_value"). The element ammo types that consume the counts are #{quiver}'s.
- Dies: nothing. `lightning_bolt.tres` gains one intake row naming Charge (#{defs}' row-names-its-status shape).

**Files touched**
- `attack/spell/infusion.gd` — the four fields, `shape_of`, `ride_of`, `spent_on`, `total_points` with the ride, add/replace in `load_of`.
- `attack/plan/magic_attack_plan.gd` — `set_shape`, `set_ride`, the overrun terms, wire.
- `attack/aspect_currency.gd` — only if #{defs} left the `<concept>_aspect` mapping.
- `fire_element` / `ice_element` / `lightning_element` count defs (#{defs} creates them) and the Catalyst count def (`stats_system/defs/explosive_aspect.tres` today, retagged by #{catalyst}) — `default_value`.
- `scenes/dev_sandbox.gd` — `starter_count_bonus` and the four grants.
- `systems/armed/armed_stack.gd` — remembered shape and ride, `clamp_infusion`.
- `attack/spell/defs/lightning_bolt.tres` — the Charge ride row; the name stays (owner, 2026-11-10); #{lightning} may touch the same file.
- `test/unit/spell/test_infusion.gd`, `test/unit/attack/test_attack_plan_wire.gd`, `test/unit/attack/test_magic_attack_plan.gd`, `test/unit/spell/test_spell_defs.gd`, `test/unit/systems/test_armed_stack.gd`, `test/integration/scenes/test_dev_sandbox_board.gd`.

**Acceptance**
1. `test_infusion.gd`: a spell with an innate Charge ride row, cast with a Charge ride → its Charge load is innate + `gained(ride_points)`; cast with a Heat ride instead → its Charge load is 0 and its Heat load is `gained` at the Heat row's ratio (1:1 when unlisted). `ride_of` answers the forged ride, else the innate one, else empty; `shape_of` answers the forged shape, else empty.
2. `test_infusion.gd`: forging a different ride leaves the `SpellDef`'s rows untouched (re-read the def after the cast: same rows, same innate).
3. `test_infusion.gd`: neither field changes `slots_used()`; a cast with full aspect sockets still takes a shape and a ride. `total_points()` equals the aspects' points + `ride_points` and does not move when only `shape_points` changes.
4. `test_magic_attack_plan.gd`, counts: shape and ride on the same element with `shape_points + ride_points` above the caster's count show in `aspect_overrun()` as the excess, and exactly at the count as 0; shape and ride on two different elements are each tested against their own count (each at its count → 0, either one above → that excess). Assert the relation to the count, never a literal.
5. `test_magic_attack_plan.gd`, capacity: on a spell with a finite `infusion_capacity` C, aspects + ride points totalling C → overrun 0; one more ride point → 1; adding shape points at that total changes nothing. With the spell's capacity infinite, no total is tested.
6. `test_attack_plan_wire.gd`: a plan with a shape and a ride (different elements) round-trips through `to_dict` / `from_dict` with both ids and both points intact; a plan with neither writes neither key (the existing wire shape unchanged); a plan with only one writes only that key.
7. `test_spell_defs.gd`: every spell def carries at most one element across its element ride rows; `lightning_bolt` carries Charge.
8. `test_infusion.gd`, the shape is inert: for each of the three elements, a cast with that shape forged resolves the same `max_hops`, the same seed payload and the same `load_of` / `bag` as the cast without it. An Ice ride on a spell with authored `max_hops` leaves `max_hops` alone and lands Cold riders at the Ice load.
9. `test/unit/systems/test_armed_stack.gd`: a remembered shape and ride come back from `clamp_infusion` with `aspect_overrun()` 0 after the caster's count drops below the remembered spend.
10. `test_dev_sandbox_board.gd`: the sandbox Player's four counts each read the default count + `starter_count_bonus`; the sandbox Enemy reads the default. Assert the relation, never the literal 3.
11. A fresh non-sandbox entity on `default_entity_board.tres` reads each count's `StatDef.default_value` (relation, never the literal 1).
12. `mise run mp:e2e` stays green (it gates `command/`; the wire changed).

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- What a shape does on a cast (Fire's disc, Lightning's levels, Ice's concentrate; the shape row and its use, its pricing, a spell refusing a shape, the preview) is #{ice-cast}'s (ADR 0084). This unit ships the field: stored, count-checked, remembered, on the wire, inert.
- The node's capacity (base 10 + 5 per degree above `min_degree`), the caster gate in `SpellTargetUnion`, the cap at socketing and at source gathering, and making `infusion_capacity` finite per spell are #{overqualified-casting}'s (ADR 0085 §3, §4). `aspect_overrun()` takes no casting node here.
- Still open (ADR 0085 revisit-when): whether shape points count against the capacity. Tentative: no. Flipping it is `Infusion.total_points()` and acceptance 3 and 5, nothing else.
- The AI's infusion picker (`entity/controller/ai_infusion_picker.gd`) forges no shape and no ride in this unit — parked; the AI casts innate.
- The forge's display (the shape and ride sockets, add or replace, the exchange, used / cap) is `forge-ui`'s; it reads `shape_of`, `ride_of`, the four fields, `spent_on` and `total_points()` and sums nothing itself. No visual lands here.
- ADR 0085 supersedes ADR 0081 §7's single element field in part; this unit owes no ADR correction.
- Which inner-tree shape holds the elements is a sibling issue in Needs design.
- Parked (owner, 2026-11-10): the starter may later move from `StatDef.default_value` to innate stat modifiers (e.g. `default_entity_board.tres`'s `intrinsic_modifiers`, `:673`) so it can be looted. Not now. A `CoreClass` grant is not the sandbox seat: `balanced_core.tres` is a real pickable class.
- The default change is suite-wide: Catalyst's count 0 → 1 changes every AI reload and volley composition. Grep `test/` for reload, quiver-content and volley assertions and re-point them (never delete); the full suite is the gate, not `test:dir`.
- The facets must be minted before the sandbox grants land: `mint_facets` runs inside `apply_intrinsics`, and `_setup_level` grants after `super()`, as `blade_size` does today.
- `dev_sandbox.gd:13`'s `_SANDBOX_BLADE_SIZE_BONUS` is a `const` against the tunables rule; the new knob is an `@export`. Converting the old one is a drive-by the drone may take.
- The later direction (all counts start at 0; gains from the inner tree, core class, metagame, keystones) is not built; #1787 generator keystones is its own issue.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:362-411 — the row type, ride vs shape, one element per cast, add or replace, no Fuel in the slot; an arrow is a subtype or an element (the "orthogonal" passage is gone)
docs/design/elements.md:580-600 — the Ice row's int:int affinity, ride and shape as two rows on one count
docs/design/elements.md:638-656 — three kinds of slot: shape field, ride field, one count split, the ride's points under infusion_capacity
docs/adr/0085-the-forge-has-three-kinds-of-slot-and-a-spells-point-cap-grows-with-the-caster-nodes-degree.md — §1 three kinds of slot, §2 the ride counts against the cap (§3, §4 are overqualified-casting's)
docs/design/elements.md:1052-1076 — v1 spell content: lightning_bolt carries Charge, the Cold spell is #1789
docs/design/elements.md:1129-1133 — the forge budget stays keyed by concept
docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md:33-34 — §7 one element per cast, §8 the three units
attack/spell/infusion.gd:13-101 — points, slots_used, intake_of, ratio_of, gained, load_of
attack/spell/infusion.gd:112-142 — use_of and bag: where a load spends through its use
attack/spell/aspect_intake.gd:18-75 — the row: identity, innate, affinity, use
attack/plan/magic_attack_plan.gd:154-158 — the infusion on the wire (to_dict)
attack/plan/magic_attack_plan.gd:175-177 — from_dict reads it ungated
attack/plan/magic_attack_plan.gd:677-690 — set_infusion, the setter shape to mirror
attack/plan/magic_attack_plan.gd:754-771 — aspect_overrun, the host's launch check, its total-points term
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
