Title: Cast shapes: what an element count does to a spell's own walk

Intended lane: `Needs design`. Not blocked; blocks nothing. A sibling under hub #1716. Design home: `docs/design/elements.md` § Shape and ride, § Ice on a cast.

**Problem.** An element does two independent things on a cast. The ride (hits plant terrain, primed nodes go off) is specced and split into units. The shape (the count reshapes the cast's own walk, at once, planting nothing) exists only as a direction and as Ice's concentrate. Until this is settled, #{forge} ships an element on a cast as a ride only, and an Ice load leaves hops alone (seed ×1).

## What the owner has already said (verbatim, 2026-11-10 unless dated; not reopened)
- The shape table (Fire widens the seed into a disc, Lightning lengthens the walk by whole hops, Ice shortens the walk and pays the seed): *"that's exactly what i'd been trying to convey all this time"*.
- Shape and ride are picked independently: *"sometimes you'd want to set Fire as the reach element, sometimes you'd want to leave Fire stacks (Heat), sometimes you'd want both, or neither, or some other combination, all this *besides* other riders you might want to add -- poison, curse, greed, whatever (which don't modify reach)"*.
- A spell authors a default element or none, and the caster replaces it or adds their own attunement, beside the limited aspect slots. Pulling a spell apart this way *"is a feature"*.
- A shape's *"responsibility is reach and only reach"*: it mints no terrain stacks.
- Ice's shape is a `ConcentrateUse` on the Ice intake row (picked over a spell-level field). Its bonus scales damage and aspect riders, never Heat / Cold / Charge stacks (picked after *"self-boosting ice?"*). 1 Ice = 1 hop, authorable per spell. Element counts run *"0..5 or maybe 0..10 at best"*.
- The price of a hop is a lean, not settled: *"even if it'd be, say, a.. +50% boost for each hop removed"*, then *"a +50% per hop lost is decent, but very rough. might need +100% in some cases, or +25% in others.. like not sure but i think this is gonna bite us"*.
- The price must be known at cast (*"a spell beforehand doesnt know how many hits a 4-hop spell would do"*, 2026-11-04) and a hop cut must pay (*"a pure nerf if it just reduces hops"*).

## Settled elsewhere, do not re-argue
- A hit carries no reach of its own and no neighbour is ever chosen (ADR 0075; ADR 0073's rejected per-hit load: "a 30-vertex sweep would be 30 blasts"). A shape acts on the walk, which ADR 0075 §2 allows ("may reshape the cast but never gives a hit a reach entry"). Arrows and blades have no walk and so no shape.

## Forks

**1. Where do shape and ride sit at the forge?** Owner lean, 2026-11-10 (not yet a final call):
*"i was under the impression that we already had an element slot (singular) separate from the aspect slot(s), which matches the divide"*. So the one element field (settled 2026-11-09) **is the shape slot**, and terrain stacks become riders beside the aspects: *"for that cast you get to spend your budgets (x_element, x_aspect) on elemental (resp aspect [now to be expanded to elemental/terrain stacks]) slots"*.
- (a) **The element field is the shape; Heat / Cold / Charge riders take rider slots like an aspect does.** The owner's lean. Open under it: do terrain riders share the limited aspect slots or get their own; may the ride element differ from the shape element (a Fire shape with Cold riders); may a cast carry two different terrain riders (ADR 0081 says a hit carries 0 or 1 element, and names "more than one element per hit" as a revisit trigger).
- (b) Two element fields, a shape field and a ride field, apart from the aspect slots.
- (c) One field; each spell authors whether its row rides or shapes. The caster never chooses. Out, given the owner's "both, or neither, or some other combination".

**2. One count, spent across both.** Owner, 2026-11-10: *"split indeed sounds good"*, with the example *"say you got 3 Fire, then you cast a spell with N Fire baseline (or N Ice or N Lightning, or 0) then you can spend 1 there and 2 on Heat for 2 Heat stack riders"*. Settled as split: the count is a per-cast budget the caster divides between the shape and the terrain riders; the spell's authored baseline is added on top and costs nothing.

**3. What does one point buy for Fire and Lightning?** The hard one; a deep dive is in `cast-shapes-rates.md` beside this file. The owner's constraints, 2026-11-10:
- No tie-breaking: *"1 Lightning = 1 arc i think is out, because it introduces some tie breaking formula"*.
- Not target-dependent: *"making it target dependent also sounds like a bad deal, like e.g. basing it off the degree of your target. because you can tweak your spell before you pick the target"*.
- Symmetric like Fire's circle: *"what we'd want is for it to be symmetric like a circular AoE explosion that Fire has"*.
- Small values must not be dead: *"1-sized explosion hits 0~1 node, i think you'd need 2~3 to hit all your neighbors"*; *"a 1-sized AoE likely hits nothing still, but it does explode. does 1 lightning do nothing?"*
- An idea on the table: a boost per element, *"each 1 Fire invested -> 2 Fire shape"* or *"each 1 Lightng invested -> 3 Lightning shape"*, justified because *"these blast/arc effects don't *last* as much as stack-depositing payload rows as reach doesn't mint terrain stacks by default"*.
- Still open with it: do the disc's and the extra hops' landings carry the full payload or a share; does a Lightning shape adding hops stand beside the ruling that `max_hops` takes no stat scaling (owner, 2026-09-02, `docs/domain/spell-propagation.md:444-473`).

**4. The price of an Ice hop.** Owner lean, 2026-11-10: *"knob/resource per spell i think. with some default? but it's both reading the spell as well as its damage profile to set something sensible, not sure if we can find a good default, or a small set of defined behaviors"*. So it is authored per spell; open is whether one default exists or a small set of named behaviours (for example "burst": a high bonus for a damage spell; "dose": a low one for a stack-planting spell), and whether the bonus is one number or one per hop removed. The risk to settle against: Pestilence gives up ~84 measured landings for a ×4 seed at +50% per hop, so the concentrate is a trap unless focus itself buys something (breaking ice, a kill threshold, a go-off copying the larger payload).

**5. How does a shape meet terrain already on the board?** Owner asked, 2026-11-10: *"how does the shape interact with present terrain? do they combine symmetrically?"* Pass reading, tentative: a shape only adds or removes arrivals of the cast's own walk, and every arrival is an ordinary hit, so the terrain rules apply to it unchanged and the two layers stack.
- A Fire-shaped seed disc landing on a Burning node sets off that node's own disc; on a Shocked node, its arc. Shape widens once at the seed, terrain widens again wherever a landing finds a primed node.
- A Lightning-shaped walk crossing Shocked nodes is conducted (no hop spent), so the added hops and a wire add up.
- Frozen is the asymmetric one: it ends a walk and absorbs a copy. Open: is a landing made by a Fire shape's disc a direct hit (lands, can break the ice) or a copy (absorbed under the threshold)?
- An Ice shape does nothing special on Frozen ground; its larger seed is simply more likely to pass the break threshold.
- Open: with the ride picked too, every arrival the shape adds also plants the terrain riders, so a Fire shape with Heat riders lays Heat over the whole disc in one cast.

## The look (when built)
The forge shows each field's effect as the count changes: "N hops → M, seed ×X", the disc's size, the added hops, and why a spell refuses a shape.

## Notes
- The Cold spell #1789 (Needs design) carries the Ice shape as its innate, eating its hops to 0. Settle the two together.
- ADR 0081 §7 (one element field) and §8 (the multiplicative ladder as the Ice price) are touched by whatever is picked here; corrections go to the sibling issue for ADR corrections.
- Parked owner thought, 2026-11-10, far future, not this issue's scope: the forge pulling a spell apart further than element and riders — *"thinking of breaking spells down by their 4~5 identity fields (that describe their behavior, movement, reducer, etc; altogether forming basically a "graph automaton", and which could (much later) be pulled appart and recomposed per-slot. future thought."* Shape and ride as separate slots is the first step of that; keep the slot model open to more fields.
- The Frozen vertex's snap is a blade concentrate (#{ice}), not this.
