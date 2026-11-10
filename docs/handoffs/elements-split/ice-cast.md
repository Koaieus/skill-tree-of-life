Ice on a cast: the concentrate. An Ice load on a spell cuts the walk's hops and pays the seed a flat bonus per hop removed, as a `ConcentrateUse` on the spell's Ice intake row. Child of hub #1716; design home `docs/design/elements.md` § Ice on a cast. It replaces the ×1 stub #{forge} ships.

Blocked by: #{forge}, #{forge-ui}
Blocks: none

## Acceptance spec

**Decisions**
- The concentrate is a `ConcentrateUse` on the spell's Ice intake row (owner, 2026-11-10, picked over a spell-level field and over keeping the ×1 stub for good; `elements.md:566-575`). The shape is the owner's of 2026-11-05: *"some resource? like most spells -> just reduce hops. some others -> maybe reduce max visits. something that takes the ice-suppression value and uses it to alter the cast spell?"*
- The price is flat per hop: *"L is (very) roughly quadratic, but we dont want to cncentrate ALL that, there's benefit to having things concentrated at all, even if it'd be, say, a.. +50% boost for each hop removed. e.g. from 6->3 hops = -3 = +150% damage"* (owner, 2026-11-10; `:577-587`). Seed × (1 + bonus × hops removed). No spell authors a hop ladder.
- The bonus scales damage and aspect riders, never element stacks: *"whole payload but.. does that mean also a Cold stacks elemental rider gets boosted? self-boosting ice?"*, then the owner picked "never scales element stacks" over "scales everything" and "one Ice row per spell" (2026-11-10; `:589-597`). Heat, Cold and Charge riders land at their cast value.
- One Ice is one hop, authorable per spell (owner, 2026-11-10, picked "1 Ice = 1 hop, authorable per spell"; on the range: *"counts of 20-50 are a bit much, leaning towards having `x_element` counts be 0..5 or maybe 0..10 at best"*; `:599-604`). The rate is the Ice row's existing `affinity_gain:affinity_cost`; the use spends 1 load per hop. Surplus load is wasted.
- The price is known at cast: *"a spell beforehand doesnt know how many hits a 4-hop spell would do"*; a hop cut must pay: *"a pure nerf if it just reduces hops"* (owner, 2026-11-04; `:551-564`).
- A concentrated seed on a primed node is a combo, bounded by the bonus knob: *"… and ice + fuel sounds like a combo why not?"* (owner, 2026-11-05; `:639-647`).
- (pass pick, tentative) Pestilence is the spell that proves it: its Ice row runs `ConcentrateUse` at 1:1 (the doc's own example, *"a Pestilence concentrates"*, `:627-630`). Every other spell keeps the unlisted-element default, a Cold ride.
- (pass pick, tentative) The multiplier lands on the seed arrival only, the wave at hop 0. Arrivals of the remaining hops land at their cast value.

**Knobs** (tentative defaults, easy to change; tests assert ratios, never the literal)
- `ConcentrateUse.bonus_per_hop` (`@export_range(0.0, 2.0, 0.05)`) = 0.5 (owner number): the seed gains this fraction per hop removed. Inspector on the row's use sub-resource; the forge preview shows the result live.
- The Ice row's `affinity_gain:affinity_cost` = 1:1 on Pestilence (owner default): Ice per hop. A dearer rate (1:2) is the per-spell tuning.

**Composition**
- `ConcentrateUse` extends `LoadUse`. Its `spend` writes two facts into the `LoadBag`: the hop cut (the load, an int) and the seed multiplier's bonus. The bag owns them; `SpellResolver` reads the bag once per cast, where it sets the seed's `hops_remaining` raw today: `hops_remaining = max(0, max_hops − cut)`, and `removed = max_hops − hops_remaining` gives the seed factor `1 + bonus × removed`.
- The seed arrival's payload is scaled through the payload-scale path #{resolver} built for a go-off's share (damage and every rider's stacks, `ceil` per rider), with one difference this unit adds to that path: a rider whose status is an element's terrain (`ElementRoster.for_status`, #{terrain}) is left at its cast value. If the share path cannot take that filter without a second scaling routine, stop and report it as a fork.
- A spell with nothing to cut refuses Ice the way an un-priced row refuses today: `max_hops` 0 or `inf` authors no `ConcentrateUse` (a config warning on the row if one is authored there).
- The forge preview (#{forge-ui}'s element field): with a concentrating spell selected, the field shows "N hops → M, seed ×X" as the Ice load changes, and names the wasted surplus. It reads the same bag facts the resolver reads, never a second formula.
- #{forge}'s ×1 stub line and its test for it are replaced.
- Dies: nothing else. A `max_visits` variant is a second subclass, built when a spell needs it, not here.

**Files touched**
- `attack/spell/load_use/concentrate_use.gd` (new), `attack/spell/load_use/load_bag.gd`.
- `attack/spell/spell_resolver.gd`: the seed's hops and the seed arrival's scale.
- `attack/spell/defs/pestilence.tres`: the Ice row.
- The forge's element field scene and script (#{forge-ui} names them).
- `test/unit/spell/test_concentrate_use.gd` (new).
- `docs/domain/aspect-cell-authoring.md` (the `LoadUse` set), `docs/domain/spell-propagation.md` (a paragraph beside `max_hops`).

**Acceptance**
1. `test_concentrate_use.gd`, red first: a spell with H hops and an Ice load of c walks `max(0, H − c)` hops. The seed's damage is the plain cast's × `(1 + bonus × removed)`; assert the ratio between two loads, never the literal 0.5.
2. Same file: a load above H cuts H hops and no more; the seed factor reads the hops removed, not the load.
3. Same file: on the seed, an aspect rider's stacks scale by the same factor, `ceil`; a Heat, Cold or Charge rider on the same cast lands its cast value.
4. Same file: with hops left, an arrival at hop 1 or later lands the plain cast's payload.
5. Same file: a row with affinity 1:2 cuts one hop per 2 Ice.
6. A concentrated seed landing on a Burning node (or go-off zero's charged node, whichever is on master) is copied at the go-off's share of the concentrated payload.
7. Pestilence cast with no Ice is unchanged: its existing tests stay green untouched.
8. Visible: in the forge, raising the Ice count on Pestilence steps the preview "6 hops → 5, seed ×1.5" down to "6 hops → 0, seed ×4" (at the default knob), and a spell that cannot concentrate shows Ice as a Cold ride. Sandbox host, `mise run check` only.

**NOTES**
- The Cold spell #1789 (Needs design) carries this use as its innate Ice row, eating its hops to 0. It is not built here.
- No tension with the `max_hops` ruling (owner, 2026-09-02, `spell-propagation.md:444-473`, no stat scaling of propagation hops): the concentrate only lowers hops, per cast, and never writes the def.
- ADR 0081 §8 records the multiplicative ladder as the pricing lean; the flat bonus reverses it. The correction joins the sibling issue for ADR corrections. Write no ADR here.
- The Frozen vertex's snap is a blade concentrate (#{ice}), not this.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (the bag facts) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before the spine landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:549-647 — Ice on a cast: ConcentrateUse, the flat per-hop bonus, element stacks never scale, 1 Ice per hop, the combo
docs/design/elements.md:362-389 — the forge: ride and shape uses, one element per cast
attack/spell/infusion.gd:46-77 — intake_of, ratio_of (gain 0 refuses), gained
attack/spell/infusion.gd:90-142 — load_of, use_of, bag: where a use's spend enters the cast
attack/spell/load_use/load_use.gd:1-27 — the abstract use
attack/spell/spell_resolver.gd:140-190 — bag read once per cast; seed hops_remaining = max_hops raw (:185)
attack/spell/propagation/propagation_config.gd:36-50 — max_hops, max_visits_per_node
docs/domain/spell-propagation.md:444-473 — max_hops takes no stat scaling
docs/domain/aspect-cell-authoring.md:205-216 — affinity convention gain:cost; the LoadUse set
attack/spell/load_use/load_bag.gd — seam: the bag a use spends into
attack/spell/defs/pestilence.tres — seam: max_hops 6, visits 2; the Ice row
```
