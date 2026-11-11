---
status: settling
---

# Elements — casting: shape and ride, Ice's concentrate

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## Shape and ride: the two things an element does on a cast (owner, 2026-11-10)

An element reaches a spell in two independent ways, and a caster picks each
(owner: *"sometimes you'd want to set Fire as the reach element, sometimes
you'd want to leave Fire stacks (Heat), sometimes you'd want both, or
neither, or some other combination, all this *besides* other riders you
might want to add -- poison, curse, greed, whatever (which don't modify
reach)"*):

- **Ride**: the cast's hits plant terrain (Heat, Cold, Charge), and a primed
  node goes off when hit. This is everything above; arrows and blades have
  only this.
- **Shape**: the element count reshapes the cast's own walk, at once, and
  plants nothing (owner, on the idea's first form: *"their responsibility is
  reach and only reach"*). It acts on the walk, never on a hit, so a hit still
  carries no reach of its own (ADR 0075) and no neighbour is ever chosen.

| Element | Shape on a cast |
|---|---|
| Fire | widens the seed into a disc |
| Lightning | the seed gathers every node within N hops (level N) |
| Ice | shortens the walk and pays what is left of it (§ Ice on a cast) |

Owner on this table: *"that's exactly what i'd been trying to convey all this
time"*. A spell authors a default for each (or none) and the forge lets the
caster replace or add to either, beside the aspect slots. A cast with several
seeds shapes every seed (owner, 2026-11-11, accepted when asked). The build is its
own design issue, and until it lands an element on a cast is a ride only.

**Three kinds of slot at the forge** (owner, 2026-11-10: *"one slot
determines the color of the crystal in your wand {= reach}, another slot for
elemental payload {at most 1}, and 'regular' slots besides that"*). The one
element field ([forge.md](forge.md) § The forge) is the **shape**; a second field holds the
**ride**, one terrain element at most; the aspect slots stay aspects. A
spell is named by its shape (owner, 2026-11-11: *"A spell with Fire reach on
it is a fire spell and if it had Charge or Cold riders besides that it's
still a fire spell."*); Catalyst reads only the stacks that land ([terrain.md](terrain.md)
§ Catalyst). Shape and ride may be different elements,
each drawing its own count; the same element splits one count between them
(owner: *"say you got 3 Fire … you can spend 1 there and 2 on Heat for 2 Heat
stack riders"*), and the spell's authored baseline is free on top. The ride
never takes an aspect slot, and neither the shape nor the ride counts towards
the spell's total-points cap (owner, 2026-11-11: *"the Elemental slots dont
need to count towards the cap"*; this amends ADR 0085 §2; ADR pending). The
cap, `SpellDef.infusion_capacity`, holds the aspects' points alone. It exists
and is infinite on every spell today, so each spell gets a finite number
([forge.md](forge.md) § The forge, "Overqualified casting"). A shape or ride point is bounded only
by its element's count.

**Lightning's shape talks in levels** (owner, 2026-11-10: *"Lightning reach on
a spell talks in *level*, where level N gathers up to N hops from target.
level 1 -> ring 1; 2->ring 2. cost: {level} aka 1, +2 (3), +3 (6), etc"*). So
the seed lands on every node within N hops, level N costs 1 + 2 + … + N
points, and the walk's own `max_hops` is untouched — this replaces "lengthens
the walk by whole hops" in the table above. Fire's shape feeds the disc's one size
formula ([go-offs.md](go-offs.md) § The trigger and what a go-off pays, "Size") with points × a multiplier (owner,
2026-11-10: *"same shape, with multiplier. and the fit neednt be precise, the
ballpark should feel right"*); the multiplier is a knob, 5 as the tentative
default (at A=2, B=1 it gives 4.1 / 8.9 / 15.6 / 23.4 nodes at 1 / 3 / 6 / 10
points against Lightning's 3 / 8 / 15 / 23).

**A shape and a primed node of the same element add up** (owner, 2026-11-10,
picked over two independent go-offs and over the shape replacing the node's:
*"such that effective powers of local + incoming stay invariant basically. N
lightning shape hitting level M Shocked node creates N+M level arc (e.g.
1+1=2, 2 hops out)"*). One go-off, not two. **On a Frozen node a Fire or
Lightning shape runs alone** (owner, 2026-11-11, accepted when asked):
Frozen mutes the node's own go-off ([frozen.md](frozen.md) § Pair rules), never the cast's shape,
so the shape lands as on an unprimed node. Pass reading, tentative: once the
hit breaks the ice, a shape of the released go-off's element adds into it
and a different one runs beside it ([hit-resolution.md](hit-resolution.md) § Landing resolution, "Dual reach"). (Ice's own case is the
shatter, § Ice on a cast.) A different element stays
independent: the shape lands its hits and the node goes off by its own rule,
the two reaches concatenated ([hit-resolution.md](hit-resolution.md) § Landing resolution, "Dual reach").

**Fire adds the roots** (owner, 2026-11-10, picked over adding the powers
and over excess counting as points): r = A × (√(points × multiplier) +
√excess + B) × the seed node's radius ([go-offs.md](go-offs.md) § The trigger and what a go-off pays, "Size").
Shocked's level is √(count / T), so Lightning's
N + M already adds in the reach domain, and this is its mirror. A 3-point
shape reaches about 9 nodes alone and about 17 on a node of excess 4. Both
elements are superadditive in area by this choice.

**The node pays its solo cost** (owner, 2026-11-10: *"the solo cost"*): what
its own go-off would have spent without the shape — the nodes within M hops
for Shocked level M, the nodes in its own disc for Burning. The shape's part
was paid in points. Pass pick, tentative: at least 1, so a small fire whose
own disc reaches nobody still contributes its root and loses a stack.

**The owner's walkthrough of one hit** (2026-11-10), a Fire 2 shape with a +1
Charge rider on a node one short of Shocked: the Charge lands and the node is
Shocked; then *"the total reach is determined, gathering all AoE targets
(Fire) and gathering all Hops targets (Lightning) by combining present state
(Shocked / Burning) with incoming shape (Lghtn / Fire / ...) where
possible"* — a disc of 2 from the spell plus 0 from the node, an arc of level
1 from the node plus 0 from the spell, every node in either taking the
payload at share, the +1 Charge included.

**A landing a shape adds carries what a go-off copy carries** (owner,
2026-11-10: *"same as what would happen if the cast had no reach but the node
was Burning/Shocked"*): the go-off's share of the seed's damage and riders,
the seed's crit, and it is a copy to a Frozen node. The seed itself lands in
full. The terrain riders are among them, so a Fire shape with Heat riders
lays Heat at share over its whole disc in one cast.

## Ice on a cast: concentrate (owner, 2026-11-04/05/08/10)

Burning and Shocked add copies at a landing. Ice concentrate does the
opposite **at cast time**: an Ice load rewrites the spell's own hops down and
pays up the payload of the walk that is left (owner, 2026-11-08: *"ice concentration should i
think still be a thing just not sure how"*). It reads the cast, not the node,
because the only copies it can remove are the cast's own walk; an arrow or a
blade has no walk, so their Ice faces are Cold ride rows. Owner: *"a 4-hop
spell could be shrunk to a 1 hop spell at more damage (or statuses?) for the
one hop. or reduced to 0 hops even for 1 pinpoint hit. as balance against AoE
euclidean or hop based proliferation being almost strictly "more", frost
could reduce hops yet still achieve "more" somehow"*. The price must be
something the cast knows before it lands, never the realized landing count
(*"a spell beforehand doesnt know how many hits a 4-hop spell would do"*).
Pure hop reduction with no bonus is out: *"a pure nerf if it just reduces
hops"*.

**It is a `ConcentrateUse` on the spell's Ice intake row** (owner,
2026-11-10, picked over a spell-level field and over keeping Ice on a cast a
plain Cold ride): a `LoadUse` subclass (ADR 0070's open set), the shape the
owner sketched on 2026-11-05 (*"some resource? like most spells -> just
reduce hops. some others -> maybe reduce max visits. something that takes the
ice-suppression value and uses it to alter the cast spell?"*). At cast it
spends the row's load as a hop cut and writes a multiplier on the cast's
payload; the resolver reads both once. **The multiplier rides the whole
shortened walk** (owner, 2026-11-11, accepted when asked): every landing of
the walk that is left carries it, the seed's and each later hop's. A variant
that cuts `max_visits` is a second subclass, built when a spell needs it. A
spell with nothing to cut (0 hops, or unbounded hops) authors no gain on its
Ice row and so refuses Ice. A spell with hops to cut and no authored Ice row
concentrates at the defaults below when Ice is forged into its shape field (owner,
2026-11-11, accepted when asked); a Cold ride still plants Cold.

**The price is one number per spell, default +50% of the payload per hop
removed** (owner, 2026-11-10, picked *one number per spell, default 0.5* over
a small named set and a per-hop ladder; the worry it answers: *"a +50% per
hop lost is decent, but very rough. might need +100% in some cases, or +25%
in others.. like not sure but i think this is gonna bite us"*; the lean:
*"L is (very) roughly quadratic, but we dont want to cncentrate ALL that,
there's benefit to having things concentrated at all, even if it'd be, say,
a.. +50% boost for each hop removed. e.g. from 6->3 hops = -3 = +150%
damage"*). Payload × (1 + bonus × hops removed), the bonus one exported knob
on the use, default 0.5: Pestilence 6 → 3 lands every landing of its 3-hop
walk at ×2.5, 6 → 0 its one seed landing at ×4.
The walk it gives up is worth far more than that (the table below), and that
is the point: focus is the purchase, not a refund of the area. Rejected: the
seed multiplied by the measured landings it gave up (L(H) / L(h), ~84× for
Pestilence at 0 hops), and the conserving form 1 + L(H) − L(h); no spell
authors a hop ladder.

**On a Frozen node the hops cut add to the shatter** (owner, 2026-11-10,
picked over nothing special and over the Ice-shaped seed being a breaker):
Ice's case of "a shape and a primed node of the same element add up". If the
concentrated seed breaks the ice, by crit or by the damage threshold its
larger payload makes likelier, the burst reads excess + hops removed × a
knob. It is not a breaker of its own.

**The bonus scales damage and aspect riders, never element stacks** (owner,
2026-11-10: *"whole payload but.. does that mean also a Cold stacks elemental
rider gets boosted? self-boosting ice?"*, then picked *never scales element
stacks* over *scales everything* and *one Ice row per spell*): Poison, Bleed
and the rest scale with the damage, ceil per rider, as a go-off's share does;
Heat, Cold and Charge land at their cast value, the rule Greed already
follows. A spell carrying both a Cold ride row and the concentrate does not
freeze harder for concentrating.

**One Ice is one hop** (owner, 2026-11-10, picked *1 Ice = 1 hop, authorable
per spell*; on the range: *"counts of 20-50 are a bit much, leaning towards
having `x_element` counts be 0..5 or maybe 0..10 at best"*). The Ice row's
int:int affinity (ADR 0060) turns the count into load and the use spends 1
load per hop; the default is 1:1, and a short, strong spell may author a
dearer rate on its row (1:2). Surplus Ice beyond the spell's hops is wasted.

What a hop is worth, measured (2026-11-04, 10 procgen maps of 800 nodes,
mean degree 3.1, 300 seed nodes, whole graph; enemy territory is a subset so
real numbers sit lower):

| hops | unique nodes | landings, visits ≤ 2 | ≤ 3 | ≤ 4 | unbounded |
|---|---|---|---|---|---|
| 1 | 4.0 | 4.0 | 4.1 | 4.1 | 4.2 |
| 2 | 8.9 | 11.9 | 13.4 | 14.3 | 15.9 |
| 3 | 15.5 | 24.4 | 30.6 | 35.5 | 59 |
| 4 | 24.1 | 40.9 | 54.6 | 66.5 | 214 |
| 5 | 34.2 | 60.8 | 84.0 | 105 | 669 |
| 6 | 46.1 | 84.6 | 119 | 151 | 1525 |


Coverage grows sub-quadratically with hops on these planar maps (exponent
about 1.65 between 4 and 8 hops; paths re-merge, the map has edges), never
exponentially. The exponential lives in `max_visits`: unbounded, walks grow
like mean degree to the power of the hops (measured ×3.6 per hop), and a
visit cap k clamps landings near k × coverage. Hop reach is absolute, not
relative: 8 hops is ~75 nodes on an 800-map and about the same on the aimed
2–4k map, so the number to reason against is reach versus the *target's
territory*, which grows over a run (an entity holding 100 nodes is covered by
a 6-hop fan).

**"Ice alters the spell" and "Ice adds Cold riders" are one mechanism, two
uses** (owner asked, 2026-11-08: *"seems both should be made possible, or are
they one and the same?"*): an intake row is identity + rates + a swappable
use (ADR 0070), so a Cold *ride* row plants riders and the concentrate is a
*shape* use on the same row type. Which one a spell's Ice row runs is
authored per spell — a Frost Nova plants Cold, a Pestilence concentrates —
and one spell may carry both as two rows, since rows key on the status or use
they run, never on the bare element (#1660 B2), while the one `ice_element` count
budgets both.

Owner idea, 2026-11-11, not decided: *"It almost feels like the ice row (by
which you mean the field/slot on the spell to specify it's behavior of Ice
being added right?) is one of three fields: how does it react to: adding
fire adding lightning adding ice. Tho fire and lightning are always the same
so far: "produce some AoE or hops spread". Possibly for Firecracker the fire
behavior may be overridden?"* So the Ice row may become one of three
per-spell shape-reaction fields, Fire and Lightning defaulting to the
standard shape and overridable per spell.

**A concentrated seed on a primed node is a combo**, not an exploit to rule
out. The seed lands with its concentrated payload and a Burning or Shocked
node copies it at share like any payload (owner, 2026-11-05: *"hitting
Charged/Fueled nodes with ice load just proliferates whatever the ice would do
but on the defender's side (incoming hit proliferates via hops or AoE boom)
instead of on the attacker's side … and ice + fuel sounds like a combo why
not?"*). The per-hop bonus bounds it: Pestilence concentrated from 6 hops to
0 carries ×4 a landing's payload, and at share 1 every disc node takes that
×4, the seed node twice. The multiplier rides the walk, so a later hop that
lands on a primed node is the same combo at that node.
