The first child of the #1716 elements split, and the root of the spine: the three element counts, the `Element` def with its ordered bands, the Heat / Cold / Charge `StatusDef`s with their facets, the vocabulary, and the element counts' place on the UI. It adds no terrain behaviour. Design home: `docs/design/elements.md`. Parent hub: #1716.

Blocked by: none
Blocks: #{terrain}, #{resolver}

## Acceptance spec

**Decisions**
- Separate axis (owner, 2026-11-04): *"Separate axis sounds good"*; *"elements not being parents of aspects makes sense"* (`elements.md:13-22`).
- Aspect:Status 1:1 is guarded by a test (owner, 2026-11-04): *"option 1 sounds very clean"* (`elements.md:24-29`, ADR 0072 §1).
- The roles table (owner, 2026-11-04): *"that table looks very good, should be persisted"*. Fire = Heat → Burning, Ice = Cold → Frozen (Frostbite is the mover, #1444), Lightning = Charge → Shocked (`elements.md:245-256`).
- `Identity.Kind.ELEMENT` (owner, 2026-11-09): *"yes Kind.ELEMENT is surely needed"*. It is presentation-only (`elements.md:1187-1189`).
- An element is its own def beside `Aspect` (owner, 2026-11-09): *"Elements as a class might be better for now, duck typing is also still a thing, and we never enumerate the whole list i think"*. A shared `Concept` base is not taken. The shared fields keep `Aspect`'s names (`elements.md:1190-1196`).
- `StatDef.Role.ASPECT` is renamed `COUNT`. A member keys its own facets (`heat_resistance`) (pass pick, tentative; `elements.md:1184-1191`).
- A row names the status it plants (owner, #1660, 2026-10-18): *"B2: agreed"*. It defaults to its concept's only status (`elements.md:1179-1183`). This unit adds only the field. Rekeying the forge budget and `Infusion.load_of` / `use_of` belongs to #{forge}.
- Bands (owner, 2026-11-09): *"iff these 3 statuses are a special case (or subclass) by virtue of all being `elemental/reach-y/go-off`-ey, option 1 seems cleanest"*. A band is a threshold as a multiple of T, an `Identity`, and its answers: go off, admits, travel verb, decay rate, light. A new band is earned only by a change in kind (`elements.md:864-876`).
- `GoOff` sits on the `Element` def (owner, 2026-11-09): *"i think it should sit on Element def, going off is just about their thing"* (`elements.md:739-745`). Here the field exists and is null on every band.
- Burning is a light source (owner, 2026-11-06): *"burning being a light source does sound clever, could be one of the cells filled by burning"* (`elements.md:901-904`).
- Schools: Fire is in STR's pool, Ice in DEX's, Lightning in INT's. Element counts come from the aspect sources (owner, 2026-11-09; `elements.md:1044-1049`).
- Vocabulary guard (owner, 2026-11-04): *"stay mindful of concepts drifting"*. "Volatile" is adopted for Burning and Shocked (owner, 2026-11-09): *"`volatile` is a better fit to describe Burning *and* Shocked"* (`elements.md:1021-1040`).
- The Element Matrix has one row per family status, with columns `Ammo : Addon : Spell : Infusion` (owner, 2026-11-04): *"option 1 sounds good"* (`elements.md:1142-1145`).
- The count stat ids are `fire_element`, `ice_element` and `lightning_element`, with display names "Fire attunement", "Ice attunement" and "Lightning attunement" (owner, 2026-11-10, picked `fire_element`, shown as "Fire attunement", over `fire_attunement` and a bare `fire`; the picks are recorded in `docs/handoffs/elements.md` § 0, not as a quoted sentence). The suffix follows the kind, as `_aspect` does.

**Knobs**: none. The band multiples and decay rates are authored data on the `.tres` (below), not tuning exports. T, k and the cap belong to #{terrain}.
- `ElementBand.decay_per_world_turn` (int ≥ 0). Primed bands default to 1, the pass default "decay 1 per world turn". Overflow bands default to 2, **undecided** (owner, 2026-11-10: *"overflow decay idk yet 2 or 3 or proportional"*); the doc says "decay fast" but gives no number. Keep it a knob. Only #{flow} reads the rates; all terrain decay happens in its world-turn pass.

**Composition**
- **`Element`** (`elements/element.gd`, `class_name Element`, Resource, `@tool`). Its fields keep `Aspect`'s names: `identity`, `stat` (the COUNT facet), `ammo`, `addon_scene`, `spells` (the last three stay empty here). New fields:
  - `terrain: StatusDef`: the one terrain stack.
  - `movers: Array[StatusDef]`: empty in v1. Frostbite joins with #1444.
  - `school: Identity`: an attribute identity.
  - `decay_per_world_turn: int`: the rate below the first band.
  - `bands: Array[ElementBand]`: ascending.
  - `id()`, as on `Aspect`.
- **`ElementBand`** (Resource):
  - `threshold_multiple: int` (≥ 1, × T).
  - `at_cap: bool`: when true, the threshold is the node's cap k × T and `threshold_multiple` is ignored. k is per node.
  - `identity: Identity`: null means the display falls back to the band below.
  - `go_off: GoOff = null`.
  - `admits: Admits = null`.
  - `travel: Travel { NONE, ENDS, CONDUCTS, SPREADS }`.
  - `decay_per_world_turn: int`.
  - `light: bool`.
- **The authored bands.** Fire: Burning (×1, SPREADS, light), then overflow (at_cap, no identity). Ice: Frozen (×1, ENDS), then Deep freeze (at_cap, own identity). Lightning: Shocked (×1, CONDUCTS), then overflow (at_cap). Volatile is a word, not a field.
- **`GoOff` and `Admits`.** Each is an empty abstract `Resource` base (`elements/go_off.gd`, `elements/admits.gd`) so the fields type-check. #{resolver} owns the contract (methods and the disc subclass) and #{ice} owns the admits answer.
- **`ElementRoster`** (`elements/element_roster.gd` + `.tres`) follows the `AspectRoster` pattern: `shared()`, `by_id`, `for_stat`, and a `for_status(def)` that returns the element whose `terrain` or `movers` holds the def. That lookup is the one way any later unit asks "is this status a member, and of what".
- **Nothing computes a band here.** #{terrain} owns the band function (count, T, k) and reads the band list from here.
- **Statuses.** `effects/status/{heat,cold,charge}.tres` use the plain `StatusDef` script, each with its own identity (`heat`, `cold`, `charge`) and no tags. They are added to `effects/status_roster.tres`. They land as host rows until #{terrain} diverts them; nothing plants them yet.
- **Facets.** The COUNT stats `{fire,ice,lightning}_element` take the element identity, `role = 1`, and no family parent (spec pick: the doc names none). The resistance stats `{heat,cold,charge}_resistance` take the member identity, `role = 3` and parent `status_resistance`, copying `poison_resistance.tres`. All of them go on `stat_def_roster.tres`, and every board mints them through `mint_facets` with no code change.
- **`Role.ASPECT → COUNT`.** The ordinal stays 1, so no `.tres` changes. Rename the symbol in `stat_def.gd:14`, the two production readers (`ammo_type.gd:52`, `aspect_currency.gd:20`) and the 25 test files that name it. Doc comments that say "ASPECT facet" follow.
- **`Identity.Kind.ELEMENT`** is appended last, so the stored ints of existing identities do not shift. The new identities use it: fire, ice, lightning, heat, cold, charge, burning, frozen, shocked and deep_freeze, all added to `identity/identity_roster.tres`. Readers:
  - `badge_frames.tres` gets an ELEMENT frame.
  - `concept_card.gd:47` stays ASPECT-only (no card for elements in this unit).
  - `infusion_socket.gd:188` is unchanged.
  - The identity sandbox picks the new kind up through `Kind.values()`.
- **`AspectIntake`** gets `@export var plants: StatusDef = null`. `status()` (`aspect_intake.gd:55-57`) returns `plants` when it is set, and otherwise falls back to `by_concept` as today. No authored row sets it here.
- **Pool rolls.** One supply entry per count goes in its school's pack, copying `dexterity.tres:239-246` (`passes [budget, supply]`, regular and blight subtypes). The rolls are `fire_element` in `strength.tres`, `ice_element` in `dexterity.tres` and `lightning_element` in `intelligence.tres`.
- **Docs.** In the `aspect_matrix.md` Glossary:
  - Fix the Element row: the count id, and terrain-only reach. "An element's reach load feeds reach" is stale per ADR 0075.
  - Fix the Catalyst row: it is an aspect status on allocated nodes only, not "terrain".
  - Add Volatile.
  - Widen Face to "one aspect or member in one facet".

  Add an `## Element Matrix` section with rows Heat, Cold, Charge and Frostbite. Each cell names the unit or issue that fills it: arrows #{quiver}, addons #{blade-elements}, the spell `lightning_bolt` #{forge}, the Cold spell #1789. `docs/domain/aspect-cell-authoring.md:21` follows the rename.

**Files touched**
- New: `elements/element.gd`, `elements/element_band.gd`, `elements/go_off.gd`, `elements/admits.gd`, `elements/element_roster.gd`, `elements/element_roster.tres`, `elements/defs/{fire,ice,lightning}.tres`.
- New: `identity/defs/{fire,ice,lightning,heat,cold,charge,burning,frozen,shocked,deep_freeze}.tres`, `effects/status/{heat,cold,charge}.tres`, `stats_system/defs/{fire,ice,lightning}_element.tres`, `stats_system/defs/{heat,cold,charge}_resistance.tres`.
- Edited: `identity/identity.gd`, `identity/identity_roster.tres`, `stats_system/stat_def.gd`, `stats_system/stat_def_roster.tres`, `effects/status_roster.tres`, `attack/ammo/ammo_type.gd`, `attack/aspect_currency.gd`, `attack/spell/aspect_intake.gd`, `ui/identity_badge/badge_frames.tres`, `procgen/pools/{strength,dexterity,intelligence}.tres`.
- Docs: `docs/design/aspect_matrix.md`, `docs/domain/aspect-cell-authoring.md`.
- Tests: the 25 `Role.ASPECT` test files.

**Acceptance**
1. `test/unit/aspects/test_aspect_roster.gd` gets a new test that guards ADR 0072 §1: every aspect has exactly one status, no two aspects share one, and no aspect's status is any element's member (via `ElementRoster.for_status`). If an aspect ships with a null status today, stop and report it; do not weaken the assert.
2. New `test/unit/elements/test_element_roster.gd` mirrors `test_aspect_roster.gd`:
   - The roster equals `elements/defs/`.
   - Ids are unique, and `by_id`, `for_stat` and `for_status` resolve.
   - Every facet carries its element's identity, and every identity is `Kind.ELEMENT`.
   - Bands ascend: `threshold_multiple` is non-decreasing, an `at_cap` band comes last, and no band below the cap is `at_cap`.
   - Every `go_off` is null.
   - The travel verbs are Burning SPREADS, Frozen ENDS, Shocked CONDUCTS, and only Burning has `light`.
3. `test/unit/stats/test_concept_facets.gd` gets a new test. For each element, `StatRegistry.facet_def(element_id, Role.COUNT)` and `facet_def(member_id, Role.RESISTANCE)` resolve. A default entity board mints all six stats.
4. `test/unit/test_pool_scoping.gd`: `_SUPPLY_HOME` gains the three counts with their schools, and the existing sweep stays green. `test/unit/procgen/test_roll_pass.gd:186-206` currently selects supply stats by the suffix `_aspect`. Re-point it to COUNT-role stats so the element entries are counted as supply. This is a re-point, not a deletion.
5. `test/unit/spell/test_aspect_intake.gd` gets a new test. A row with `plants` set returns that def from `status()`. A row without it still returns `by_concept`'s def. The existing asserts pass unchanged.
6. Characterization pins: the 25 files that named `Role.ASPECT` pass with only the symbol renamed (re-pointing is allowed, assertion changes are not). `test_identity_roster.gd`, `test_identity_badge.gd` and `test_status_roster.gd` stay green.
7. Visual: in the identity sandbox, an element badge draws its own ELEMENT frame, not the hexagon fallback, tinted by its identity. The three element hues are distinct from one another and from STR red and Health crimson, and none is gold (`.claude/rules/ui-palette.md`). An icon is optional, since the letter fallback is fine.
8. Visual: the three counts show on the entity's stat surface wherever `<x>_aspect` counts show today (`docs/domain/stat-surfaces.md`), tinted and badged. If that surface filters by Role or parent and so misses them, include them there. The readout must say "Fire attunement" and the count (a default entity reads `default_value`; #{quiver} raises it to 1).

**NOTES**
- The audit's "ring slots" for elements is not in this unit. Which inner-tree shape holds the elements is a sibling issue in Needs design. `entity/ring/aspect_ring.tscn` is untouched.
- `*_stacks_per_hit` facets for the members are not named by the design. They are parked: a member without one lands its authored power as-is (`status_def.gd:85-90`).
- The starter count (1 for every entity, through the stat's default value; owner, 2026-11-10) belongs to #{forge}, which sets `StatDef.default_value` = 1 on these defs. The element ammo types and their stock cap belong to #{quiver}. Here the COUNT defs keep `default_value` 0.
- `effects/status/explosive.tres:20` carries the tag `charge`. No code reads it. #{catalyst} frees it. The new status id `charge` does not collide with it.
- Not here: the next element ADR's corrections (ADR 0081 §5, §6 and §9, and ADR 0082's Context) are a sibling issue. `stats_system/defs/aspects.tres`'s description says "eight" `<concept>_aspect` stats, but 13 exist. Fix it if you touch the file.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.

**Stubs on master**: none. The shapes are named in Composition, and the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:13-33 — the two axes; Aspect:Status 1:1 is to be test-guarded
docs/design/elements.md:245-256 — the roles table: count, terrain stack, mover, state
docs/design/elements.md:739-752 — the GoOff resource sits on the Element def; the applier worklist call
docs/design/elements.md:864-882 — bands on the Element def: threshold, identity, answers; nothing stores a band
docs/design/elements.md:884-904 — travel verbs per state; Burning is a light source
docs/design/elements.md:1021-1040 — vocabulary guard incl. Volatile, Member
docs/design/elements.md:1042-1049 — schools and the pool roll
docs/design/elements.md:1142-1145 — the Element Matrix columns
docs/design/elements.md:1177-1196 — adversarial (a) row keys, (b) COUNT role, Kind.ELEMENT, Element def beside Aspect
aspects/aspect.gd:17-36 — the field names Element keeps
aspects/aspect_roster.gd:13-32 — the roster pattern to copy
stats_system/stat_def.gd:10-28 — Role enum and the (identity, role) uniqueness
effects/status/status_def.gd:85-94 — _facet_id: facets key on the def's identity
attack/spell/aspect_intake.gd:18-57 — the intake row and status() via by_concept
procgen/pools/dexterity.tres:239-246 — the supply-roll entry to copy
test/unit/aspects/test_aspect_roster.gd:22-35 — the 13-count roster test, home of the 1:1 guard
stats_system/stat_def.gd — seam: Role.ASPECT → COUNT
attack/ammo/ammo_type.gd — seam: per_reload_stat_id falls back to the ASPECT facet
attack/aspect_currency.gd — seam: cap_of reads the ASPECT facet
identity/identity.gd — seam: Kind enum gains ELEMENT
ui/identity_badge/badge_frames.gd — seam: per-kind frame dictionary
ui/identity_badge/badge_frames.tres — seam: authored frames
ui/concept_card/concept_card.gd — seam: Kind.ASPECT gate
ui/hud/command_tray/bodies/infusion_socket.gd — seam: badge frame keyed on ASPECT
addons/identity_sandbox/identity_sandbox_panel.gd — seam: iterates Kind.values()
effects/status_roster.gd — seam: by_concept first-match on identity.id
attack/spell/infusion.gd — seam: by_concept callers at 119, 141 (untouched here; forge rekeys)
docs/design/aspect_matrix.md — seam: Glossary rows Element / Catalyst / Face; Catalyst Matrix row
docs/domain/aspect-cell-authoring.md — seam: documents StatDef.Role.ASPECT
docs/domain/stat-surfaces.md — seam: where counts are read out
test/unit/test_pool_scoping.gd — seam: _SUPPLY_HOME
test/unit/procgen/test_roll_pass.gd — seam: supply selected by the _aspect suffix
test/unit/stats/test_concept_facets.gd — seam: facet round-trip
test/unit/attack/test_concept_stat_edge.gd — seam: ASPECT / RESISTANCE lookups
test/unit/attack/test_ammo_type_roster.gd — seam: ASPECT minting assert
test/unit/identity/test_identity_roster.gd — seam: identity roster and kinds
```
