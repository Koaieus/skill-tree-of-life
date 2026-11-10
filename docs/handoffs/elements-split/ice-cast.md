Ice on a cast, the concentrate: an Ice shape in the forge's shape field cuts the spell's own hops and pays the seed for each hop removed. It reads the cast, not the node, at cast time. Child of hub #1716 (late unit); design home `docs/design/elements.md` § Ice on a cast; ADR 0084 §8. The shape *field* (`Infusion.shape_element`, `shape_points`, `shape_of(spell)`), its count check and the capacity are #{forge} and #{overqualified-casting}; Frozen and its shatter are #{ice}. Fire's and Lightning's shapes are #{cast-shapes}; the two share no decision.

Blocked by: #{forge}, #{forge-ui}, #{ice}
Blocks: nothing

## Acceptance spec

**Decisions** (owner, 2026-11-10 unless dated; quotes from `docs/design/elements.md`)
- Ice "shortens the walk and pays the seed" (the shape table; owner: *"that's exactly what i'd been trying to convey all this time"*). It acts on the cast's own walk and plants nothing; an arrow or a blade has no walk, so their Ice faces are Cold ride rows.
- **It is a `ConcentrateUse` on the spell's Ice intake row** (ADR 0084 §8; owner picked it over a spell-level field and over a plain Cold ride): a `LoadUse` subclass (ADR 0070's open set). "At cast it spends the row's load as a hop cut and writes a seed multiplier; the resolver reads both once." A variant that cuts `max_visits` is a second subclass, not built.
- **The price is one number per spell**: seed × (1 + bonus × hops removed), the bonus one exported knob on the use, default 0.5 (owner picked *one number per spell, default 0.5* over a small named set and a per-hop ladder; the lean: *"a.. +50% boost for each hop removed. e.g. from 6->3 hops = -3 = +150% damage"*; the worry it answers: *"a +50% per hop lost is decent, but very rough. might need +100% in some cases, or +25% in others.. like not sure but i think this is gonna bite us"*). Pestilence 6 → 3 lands its seed at ×2.5, 6 → 0 at ×4. The price is known at cast (*"a spell beforehand doesnt know how many hits a 4-hop spell would do"*) and a cut always pays (*"a pure nerf if it just reduces hops"*).
- **One Ice is one hop** (owner picked *1 Ice = 1 hop, authorable per spell*): the Ice row's int:int affinity (ADR 0060) turns the points into load and the use spends 1 load per hop; default 1:1, a spell may author a dearer rate (1:2). Surplus Ice beyond the spell's hops is wasted. A spell with nothing to cut (0 hops, or unbounded hops) authors no gain on its Ice row and so refuses Ice.
- **The bonus scales damage and aspect riders, never element stacks** (owner, after *"whole payload but.. does that mean also a Cold stacks elemental rider gets boosted? self-boosting ice?"*, picked *never scales element stacks*): Poison, Bleed and the rest scale with the damage, ceil per rider; Heat, Cold and Charge land at their cast value. A spell with a Cold ride and the concentrate does not freeze harder for concentrating.
- **On a Frozen node the hops cut add to the shatter** (owner's pick over nothing special and over the Ice seed being a breaker): if the concentrated seed breaks the ice, by crit or by the damage threshold its larger payload makes likelier, the burst reads excess + hops removed × a knob. The Ice seed is not a breaker of its own.
- A concentrated seed on a Burning or Shocked node is copied at share like any payload (owner, 2026-11-05: *"ice + fuel sounds like a combo why not?"*). Nothing to build: it is the gather's rule.
- Ride and shape are one row type, two uses (owner asked, 2026-11-08: *"seems both should be made possible, or are they one and the same?"*): a spell may carry a Cold ride row and a concentrate row, and the one Ice count budgets both (#{forge}'s `spent_on`).

**Knobs** (tentative defaults, easy to change; tests read the knob, never the literal)
- `ConcentrateUse.bonus_per_hop` = 0.5 (`@export_range(0.0, 2.0, 0.05, "or_greater")`): the owner's default, authored per spell on the row's use. Inspector on the spell `.tres`.
- The Ice shape row's `affinity_gain:affinity_cost` = 1:1: load per point; gain 0 refuses.
- Frozen band `.shatter_excess_per_hop_cut` = 1.0 (`@export_range(0.0, 5.0, 0.25, "or_greater")`), beside #{ice}'s shatter knobs. **Open: the owner named neither this knob nor its value**; name and 1.0 are tentative.

**Composition**
- **The row.** This unit adds the shape row #{forge} left out: an `AspectIntake` on Ice whose `use` is a `ConcentrateUse` (rows key on the use they run, #{defs}), and fills `Infusion.shape_of`'s default branch for it (a spell authoring a concentrate row with `innate` > 0 has Ice as its shape default; none does in v1, #1789 will). A spell with no authored row and a finite, positive `max_hops` concentrates through a shared default `ConcentrateUse` (1:1, 0.5), the way an unlisted aspect takes a default use (pass reading, tentative). A forged Fire or Lightning shape suppresses the authored Ice shape row for that cast (#{forge}'s replace rule).
- **The load.** When `shape_of(spell)` is Ice, the Ice shape load = the row's `innate` + `shape_points` exchanged at the row's affinity (`floor`, as `Infusion.gained`). It is kept apart from the Cold ride's load: the ride plants Cold through its own row, the shape never plants.
- **The use.** `ConcentrateUse extends LoadUse` in `attack/spell/load_use/`. `spend` writes two new `LoadBag` fields, the hop cut (the load, 1 per hop) and its `bonus_per_hop`; it adds no rider.
- **The resolver.** `SpellResolver._resolve` reads both once, before wave 0: hops removed = min(hop cut, `config.max_hops`); `seed_state.hops_remaining = config.max_hops − hops removed`; multiplier = 1 + bonus × hops removed, applied to `seed_state.damage` / `seed_damage` and, ceil per rider, to the power of every cast rider that is not Heat, Cold or Charge (test by the rider's `Element`, #{defs}). `PropagationConfig.max_hops` on the def is never written. Pass reading, tentative: the multiplier is on the cast, so the landings of the shortened walk carry it the way they carry the seed's payload today; nothing re-applies it per hop.
- **Refusal** is the row's gain 0 as today (`Infusion.ratio_of`): the defs with `max_hops` 0 or `inf` author an Ice shape row with `affinity_gain` 0.
- **The shatter.** The seed landing carries hops removed as a fact into #{resolver}'s gather; #{ice}'s shatter keeps its excess an input that can be added to, and this unit adds hops removed × `shatter_excess_per_hop_cut` to the burst when that seed breaks the ice. It adds nothing to the Cold removed and is no breaker.
- **The look.** #{forge-ui}'s shape line gains "H hops → h, seed ×X", or why the spell refuses, from one pure function the resolver also uses. On the board the shorter walk is the spell's own preview. #{cast-shapes} adds the Fire and Lightning lines on the same files.
- Dies: nothing.

**Files touched**
- `attack/spell/load_use/concentrate_use.gd` (new), `attack/spell/load_use/load_bag.gd`.
- `attack/spell/infusion.gd` (shared with #{forge}): the Ice shape load, the default use, `shape_of`'s default branch.
- `attack/spell/spell_resolver.gd` (shared with #{cast-shapes}): wave 0 reads the hop cut and the multiplier.
- the Frozen band and its `Admits` (#{ice}): the knob and the added excess.
- `attack/spell/defs/trail_blazer.tres` and every def with `max_hops` 0: the refusing Ice shape row.
- `ui/hud/command_tray/bodies/readout_lines.gd`, `crucible_readout_line.gd` (shared with #{cast-shapes}).
- `docs/domain/spell-propagation.md` (a concentrate paragraph beside the `max_hops` ruling) and the elements domain doc.
- Tests: `test/unit/spell/test_concentrate_use.gd` (new); `test/unit/spell/test_spell_defs.gd`; `test/unit/ui/test_readout_lines.gd`.

**Acceptance** (red first), `test_concentrate_use.gd` unless named:
1. A 6-hop spell with 3 Ice shape points (1:1) walks 3 hops and its seed damage is ×(1 + `bonus_per_hop` × 3) of the unshaped cast (×2.5 at the default); with 6 points, 0 hops and ×4; with 9 points the same as 6. The def's `max_hops` reads 6 afterwards. A row authoring `bonus_per_hop` 1.0 gives ×4 at 3.
2. Rate: on a row authored 1:2, 2 points cut 1 hop and 1 point cuts none. A row with gain 0 refuses (`rate_of` ≤ 0) and the cast is unchanged.
3. Riders: at ×2.5 a Poison rider of 3 lands 8 (`ceil`); a Cold ride of 2 on the same cast lands 2; the concentrate itself plants no Cold.
4. No shape, or a Fire or Lightning shape: hops and seed are those of the plain cast (the multiplier is exactly 1).
5. Shatter: a concentrated seed that breaks a Frozen node bursts for (excess + hops removed × `shatter_excess_per_hop_cut`) × #{ice}'s per-stack fraction × max HP, and removes the same Cold as an unconcentrated break; a concentrated seed with no crit and under the threshold does not break it.
6. `test_spell_defs.gd`: every def whose `max_hops` is 0 or `inf` refuses an Ice shape; every other def accepts one.
7. `test_readout_lines.gd`: the Ice shape line's hops and multiplier equal the resolver's for the same cast; a refusing spell yields the refusal line.
8. Visible, sandbox host: an Ice-shaped cast walks fewer hops and lands a larger seed number; the forge readout shows the line and the refusal. `mise run check`, the full suite once, `mise run mp:e2e`.

**NOTES**
- Still open, carried as a knob, not settled here: the name and value of the hops-cut → shatter knob. Whether shape points count against `SpellDef.infusion_capacity` is open too (ADR 0085 revisit-when); it is #{forge}'s `Infusion.total_points()` and is not read here.
- Pass readings marked tentative above, none stated by the owner: the multiplier rides the whole shortened walk (not the seed landing alone); a spell with no authored Ice shape row concentrates at the default. If the built seams make either a choice between two shapes, stop and say so.
- What a hop is worth (measured 2026-11-04, 10 procgen maps of 800 nodes, whole graph): landings at visits ≤ 2 are 4.0 / 11.9 / 24.4 / 40.9 / 60.8 / 84.6 at 1..6 hops. Pestilence 6 → 0 gives up about 84 landings for ×4: focus is the purchase, not a refund of the area. Rejected, do not rebuild: the seed multiplied by the measured landings (L(H) / L(h)), a per-hop ladder, a named set of presets.
- `max_hops` takes no stat scaling (owner, 2026-09-02). The concentrate is a per-cast spend on a per-spell row that a spell can refuse, not a board stat; the def is never written.
- The Cold spell #1789 (Needs design) carries the Ice shape as its innate; not built here. The Frozen vertex's snap is a blade concentrate (#{ice}), not this. The AI forges no shape (as #{forge}).
- Parked, far future (owner, 2026-11-10): *"thinking of breaking spells down by their 4~5 identity fields (that describe their behavior, movement, reducer, etc; altogether forming basically a "graph automaton", and which could (much later) be pulled appart and recomposed per-slot. future thought."*
- The stamp was cut before the spine and the element units landed; the dispatching lead re-checks `mise run issue-drift`. If it still flags, stop and say so.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp 5cb6de79
docs/design/elements.md:610-631 — Shape and ride: the two things an element does, the shape table
docs/design/elements.md:706-815 — Ice on a cast: ConcentrateUse, the price, hops cut on Frozen, what the bonus scales, 1 Ice = 1 hop, what a hop is worth, ride and shape as two uses
docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md:34-34 — §8, the call this unit builds
attack/spell/spell_resolver.gd:140-193 — the cast's bag and riders, ctx.load, wave 0: seed damage and hops_remaining
attack/spell/propagation/propagation_config.gd:39-44 — max_hops: 0 is seed only, inf is unbounded
attack/spell/infusion.gd:59-142 — ratio_of, gained, load_of, use_of, bag: how points become a load and spend through a use
attack/spell/load_use/load_use.gd:1-27 — the LoadUse base a ConcentrateUse extends
attack/spell/load_use/load_bag.gd:1-12 — the bag the use writes into
attack/spell/load_use/plant_use.gd:27-35 — a rider is built at power = load: what the multiplier scales
attack/spell/aspect_intake.gd:18-77 — the row: innate, affinity, use, the default use
docs/domain/spell-propagation.md:444-473 — max_hops takes no stat scaling
attack/spell/spell_resolver.gd — seam: hop cut and multiplier at wave 0
attack/spell/infusion.gd — seam: the Ice shape load and default use
attack/spell/load_use/load_bag.gd — seam: hop cut and bonus fields
attack/spell/defs/trail_blazer.tres — seam: unbounded hops, refuses Ice
ui/hud/command_tray/bodies/readout_lines.gd — seam: the Ice shape line
ui/hud/command_tray/bodies/crucible_readout_line.gd — seam: the line's text
test/unit/spell/test_spell_defs.gd — seam: the refusal guard
test/unit/ui/test_readout_lines.gd — seam: the readout test
docs/domain/spell-propagation.md — seam: the concentrate paragraph
```
