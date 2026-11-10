Cast shapes, the reach half: what a Fire or Lightning shape in the forge's shape field does to a cast. A Lightning shape makes the seed land on every node within N hops; a Fire shape widens the seed into a disc. A shape acts on the cast's own seed, at once, and plants nothing. Child of hub #1716 (late unit); design home `docs/design/elements.md` § Shape and ride; ADR 0084 §1-§6. The shape *field* (`Infusion.shape_element`, `shape_points`, `shape_of(spell)`), its count check and the capacity are #{forge} and #{overqualified-casting}; the gather, the disc and the arc are #{resolver}, #{burning} and #{lightning}. This unit feeds a cast's shape into them. The Ice shape (the concentrate) is #{ice-cast}; the two share no decision.

Blocked by: #{forge}, #{forge-ui}, #{pairs}
Blocks: nothing

## Acceptance spec

**Decisions** (owner, 2026-11-10; quotes from `docs/design/elements.md`)
- Shape and ride are independent and the caster picks each (ADR 0084 §1): *"sometimes you'd want to set Fire as the reach element, sometimes you'd want to leave Fire stacks (Heat), sometimes you'd want both, or neither, or some other combination, all this *besides* other riders you might want to add -- poison, curse, greed, whatever (which don't modify reach)"*. A shape reshapes the walk and plants nothing: *"their responsibility is reach and only reach"*. It acts on the walk, never on a hit, so a hit still carries no reach (ADR 0075) and no neighbour is ever chosen. Arrows and blades have no walk and so no shape.
- The shape table: Fire "widens the seed into a disc", Lightning "the seed gathers every node within N hops (level N)". Owner: *"that's exactly what i'd been trying to convey all this time"*.
- **Lightning talks in levels** (ADR 0084 §1): *"Lightning reach on a spell talks in *level*, where level N gathers up to N hops from target. level 1 -> ring 1; 2->ring 2. cost: {level} aka 1, +2 (3), +3 (6), etc"*. The seed lands on every node within N hops; level N costs 1 + 2 + … + N points, so the level is the largest N with N(N+1)/2 ≤ points (1 / 3 / 6 / 10 points give level 1 / 2 / 3 / 4; points 2, 4 and 5 buy nothing more). The walk's own `max_hops` is untouched.
- **Fire feeds the one disc radius** (ADR 0084 §2): r = A × (√power + B) × node radius with power = points × a multiplier knob: *"same shape, with multiplier. and the fit neednt be precise, the ballpark should feel right"*. The function, A = 2 and B = 1 are #{burning}'s (`disc_radius(power, node_radius)`); no copy of the formula or of A and B lands here.
- **A shape and a primed node of the same element add into one go-off** (ADR 0084 §3): *"such that effective powers of local + incoming stay invariant basically. N lightning shape hitting level M Shocked node creates N+M level arc (e.g. 1+1=2, 2 hops out)"*. One go-off, not two. **Fire adds the roots** (owner's pick over adding the powers and over excess counting as points): r = A × (√(points × multiplier) + √excess + B) × node radius.
- **The node pays its solo cost** (ADR 0084 §4; *"the solo cost"*): what its own go-off would have spent without the shape, the nodes within M hops for Shocked level M, the nodes in its own disc for Burning. The shape's part was paid in points. Pass pick, tentative: at least 1, so a small fire whose own disc reaches nobody still contributes its root and loses a stack. A node that is not primed pays nothing.
- **A shape and a go-off of another element are two reaches, concatenated** (ADR 0084 §5; owner picked *same as dual reach: concatenate*; the doubt behind it: *"its close nbs might get hit twice (once by fire once by lghtng)"*). The seed node takes the seed once, in full; a node inside both reaches takes one copy per reach. #{resolver}'s one dedupe switch covers it; no second switch.
- **A landing a shape adds carries what a go-off copy carries** (ADR 0084 §6): *"same as what would happen if the cast had no reach but the node was Burning/Shocked"*. That is the go-off's share of the seed's damage and riders, the seed's crit, and it is a copy to a Frozen node (absorbed under the break threshold, #{ice}). The seed itself lands in full. Terrain riders are among them, so a Fire shape with Heat riders lays Heat at share over its whole disc in one cast.
- Riders first (ADR 0083 §1): the shape is read at the seed's gather head after the hit's element riders land, with the node's primed state. The owner's walkthrough: a Fire 2 shape with a +1 Charge rider on a node one short of Shocked lands the Charge, the node is Shocked, then *"the total reach is determined, gathering all AoE targets (Fire) and gathering all Hops targets (Lightning) by combining present state (Shocked / Burning) with incoming shape (Lghtn / Fire / ...) where possible"*: a disc from the spell plus 0 from the node, an arc of level 1 from the node plus 0 from the spell, every node in either taking the payload at share, the +1 Charge included.
- A shape's reach is shape-blind like every go-off (ADR 0084 §7, #{resolver}): every node inside it, allocated or not; the hit's mask decides who the copies hurt.

**Knobs** (tentative defaults, easy to change; tests read the knob, never the literal)
- Fire's `Element` def `.shape_power_per_point` = 5.0 (`@export_range(0.5, 20.0, 0.25)`): blast power per Fire shape point. **Open (ADR 0084 revisit-when): 5 is a ballpark, not a fit.** At A = 2, B = 1 it gives about 4.1 / 8.9 / 15.6 / 23.4 nodes at 1 / 3 / 6 / 10 points on 150 px spacing, against Lightning's 3 / 8 / 15 / 23 (`tools/disc_reach.py --a 2 --b 1 --per-point 5 --fit-ladder`). Editor feedback: the blast sandbox tab.
- Solo-cost floor = 1 (`@export_range(0, 3)` beside the disc `GoOff`'s knobs, name the drone's). **Open: the pass pick "at least 1".** 0 turns it off.
- Lightning's level cost has no knob: it is the triangular rule above, one pure function (written call: the owner stated a rule, not a table).
- The shares are not new: a shape-added landing uses the element's own `GoOff.share` (0.5, #{resolver}).

**Composition**
- **The read.** A cast's shape is `Infusion.shape_of(spell)` with `shape_points` (#{forge}). This unit acts when it answers Fire or Lightning; Ice is #{ice-cast}'s and anything else is no shape. No v1 spell authors a Fire or Lightning shape default, so the points are the forged `shape_points` (an authored baseline is parked, NOTES).
- **The feed.** At a spell cast's seed landing (each wave-0 seed; pass reading, tentative, for a multi-seed cast), `SpellResolver` hands #{resolver}'s gather the cast's shape: element and points. Later waves' landings carry none. The gather's read step at that head, after admit and land, asks the shape element's `GoOff` (the same instance #{burning} / #{lightning} put on the Burning / Shocked band) to go off with the shape as an extra input, whether or not the node is primed. The shape adds one reach list at most; every other primed band still fires its own. The lists are concatenated under the gather's dedupe bool. The gather gains no shape-specific branch beyond "pass the shape to its element's go-off".
- **Lightning.** #{lightning}'s arc entry point already takes an extra level. This unit passes `level_for_points(points)`; the arc returns the reach of level N + M (M = 0 on an unprimed node) and the spend for level M alone.
- **Fire.** This unit adds the combined radius beside #{burning}'s function, over the same A and B: `shape_disc_radius(points, excess, node_radius)` = A × (√(points × `shape_power_per_point`) + √excess + B) × node radius, excess 0 when the node is not Burning. With points = 0 it must equal `disc_radius(excess, node_radius)`. The disc `GoOff` gets the same extra input as the arc: it reaches by the combined radius and returns the solo spend (the count inside `disc_radius(excess, …)`, floored at the knob when the node is Burning and the combined disc reaches someone). Node radius is the seed node's (pass reading, tentative; it is what the node's own go-off reads).
- **The spend.** The gather commits the spend the go-off returns and never counts the reached nodes (#{resolver} already says so). An unprimed node returns 0. A combined go-off that reaches no node does not go off and spends nothing (the element law).
- **The copies** are ordinary gather entries: share, parent = the seed, `paired` to the head so they carry its crit; `Admits` answers them as copies; chains, the once-per-node set and Lightning's Charge transfer (which moves only the stacks the node spent) are unchanged. The disc's own "little damage" (`damage_per_power × power`) reads the node's excess only, so a shape on an unprimed node adds none (pass reading, tentative).
- **Frozen seed** (pass reading, tentative; decided nowhere): #{pairs}' mute drops a Frozen node's own Burning and Shocked go-offs; the shape is the cast's, not the node's, so it is not muted. Its landings on Frozen neighbours are copies and are absorbed.
- **The record.** The shape's reach is marked in the attack record's blast table like any go-off, so the existing disc and arc looks play at the shaped size.
- **The look.** #{forge-ui}'s shape line (element and points only) gains the effect, from the pure functions here: Lightning "level N: every node within N hops" and the points to the next level; Fire the disc radius in node radii. While aiming, the range preview draws the shaped seed (ring or hop set). #{ice-cast} adds the Ice line on the same files.
- Dies: nothing.

**Files touched**
- the gather class under `attack/outcome/` (#{resolver}) and `attack/spell/spell_resolver.gd` (shared with #{ice-cast}): the seed's shape reaches the gather head.
- the disc `GoOff` (#{go-off-zero} / #{burning}) and the edge `GoOff` (#{lightning}) in `elements/`: the extra shape input; Fire's `Element` def: `shape_power_per_point`; `level_for_points` beside the edge `GoOff`.
- the file holding `disc_radius` (#{burning}): `shape_disc_radius`.
- `ui/hud/command_tray/bodies/readout_lines.gd`, `crucible_readout_line.gd` (#{forge-ui}'s shape line; shared with #{ice-cast}); the spell range preview.
- `docs/domain/spell-propagation.md` (a shape paragraph beside the `max_hops` ruling) and the elements domain doc.
- Tests: `test/unit/elements/test_cast_shape_reach.gd` (new); `test/unit/ui/test_readout_lines.gd`.

**Acceptance** (red first), `test_cast_shape_reach.gd` unless named:
1. `level_for_points`: 0 → 0, 1 → 1, 2 → 1, 3 → 2, 5 → 2, 6 → 3, 10 → 4.
2. Lightning alone: a level-2 shape cast on an unprimed seed lands the seed in full once and one copy on every node within 2 hops (allocated or not), each at Lightning's `GoOff.share` of damage and `ceil(r × share)` per rider; the seed node's Charge is unchanged; the walk's hop count equals the unshaped cast's.
3. Lightning add-up: a level-1 shape on a node at Shocked level 1 produces one go-off reaching every node within 2 hops, one entry per node (not two), and the node loses exactly as much Charge as the same hit without the shape (its 1-hop neighbour count).
4. Fire alone: on an unprimed seed of radius R the reach equals `shape_disc_radius(points, 0, R)`; at the default knobs 1 point is 2 × (√5 + 1) × R ≈ 6.47R and 3 points ≈ 9.75R (assert through the function and a fixture node just inside and just outside); the seed's Heat is unchanged and no status is planted.
5. Fire add-up: 3 points on a node of excess 4 reaches `shape_disc_radius(3, 4, R)` ≈ 13.75R (against 6R for the node alone) as one go-off, and the node loses exactly the Heat its solo disc would spend. `shape_disc_radius(0, e, R) == disc_radius(e, R)`; changing A or B moves both.
6. Floor: a Burning node whose solo disc reaches nobody, hit by a Fire-shaped cast whose combined disc reaches someone, loses the floor (1); with the floor at 0 it loses nothing.
7. Different element: a Fire shape on a Shocked node gives two reaches; a node inside both takes two entries, each with every rider and the damage; with the gather's dedupe on, one. The seed node takes the seed once, in full, in both settings. The Shocked node pays its own arc as without the shape.
8. Copy semantics: every shape-added landing carries the seed's `crit_tier`; one onto a Frozen node under the break threshold is absorbed (no damage, no riders); one onto a Burning node sets it off (once per node per hit). A Fire shape with a Heat ride lands `ceil(Heat × share)` on every disc node.
9. Riders first: the owner's walkthrough above, as a fixture (Fire 2 shape, +1 Charge rider, node at Charge = T): a disc from the shape and a level-1 arc from the node, both in one hit.
10. A cast with no shape, and an arrow or blade hit, gather exactly as before this unit (#{resolver}'s `test_hit_resolver.gd` passes unedited).
11. `test_readout_lines.gd`: the shape line's numbers equal `level_for_points` and `shape_disc_radius` for the same cast.
12. Visible, sandbox host: a shaped Lightning cast shows the arc look to its level, a shaped Fire cast the disc at its radius; the forge readout shows each effect line. `mise run check`, the full suite once, `mise run mp:e2e`.

**NOTES**
- Still open, carried as knobs, not settled here: the Fire multiplier (5) and the solo-cost floor (at least 1). Whether shape points count against `SpellDef.infusion_capacity` is open too (ADR 0085 revisit-when); it is #{forge}'s `Infusion.total_points()` (shape excluded, tentative) and is not read here.
- Pass readings marked tentative above, none stated by the owner: a multi-seed cast shapes every seed; the Fire shape reads the seed node's radius; the disc's own damage reads the node's excess only; the Frozen mute does not drop a cast's shape. If the built seams make one of them a choice between two shapes, stop and say so.
- Parked: a spell authoring a Fire or Lightning shape default (the doc allows "a default for each (or none)"; the baseline would be free on top). No v1 spell has one; `shape_of`'s default branch for these two elements stays empty.
- Reference numbers (10 procgen maps of 800 nodes, 150 px spacing, whole graph; enemy territory sits lower). Nodes within L hops: 3.0 / 7.9 / 14.5 / 23.1 at L = 1..4. Disc at A = 2, B = 1: 0.7 / 2.1 / 3.0 / 3.6 other nodes at power 1 / 2 / 3 / 4, 4.1 at 5, 8.9 at 15, 15.6 at 30. A 3-point Fire shape reaches about 9 nodes alone and about 17 on a node of excess 4.
- `max_hops` takes no stat scaling (owner, 2026-09-02). A Lightning shape never touches it.
- The AI forges no shape (as #{forge}).
- The stamp was cut before the spine and the element units landed; the dispatching lead re-checks `mise run issue-drift`. If it still flags, stop and say so.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp 5cb6de79
docs/design/elements.md:109-125 — Size: the one disc radius, A and B, its three readers
docs/design/elements.md:610-704 — Shape and ride: the table, levels and their cost, Fire's multiplier, add-up, add the roots, solo cost, the walkthrough, what a shape-added landing carries
docs/design/elements.md:949-966 — Dual reach: concatenated, the dedupe switch, a shape against another element's go-off
docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md:27-32 — §1-§6, the calls this unit builds
attack/spell/spell_resolver.gd:140-193 — the cast's infusion, ctx, wave 0: where a seed is made
attack/spell/infusion.gd:13-45 — the points an infusion holds; forge adds the shape fields beside them
graph/graph_mirror.gd:229-250 — nodes_within, the hop ball a level reads
attack/range_finder/euclidean_range_finder.gd:93-108 — the disc's hit test (a node's edge inside the reach)
effects/status/spread/explosive_spread.gd:41-81 — today's disc: radius from power
docs/domain/spell-propagation.md:444-473 — max_hops takes no stat scaling
attack/spell/spell_resolver.gd — seam: shape to the gather head
effects/status/spread/explosive_spread.gd — seam: the class the disc GoOff ports
ui/hud/command_tray/bodies/readout_lines.gd — seam: the shape line's effect
ui/hud/command_tray/bodies/crucible_readout_line.gd — seam: the shape line's text
test/unit/ui/test_readout_lines.gd — seam: the readout test
docs/domain/spell-propagation.md — seam: the shape paragraph
tools/disc_reach.py — seam: the probe behind the reference numbers
```
