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

**1. One element field at the forge, or two?**
Today's call (2026-11-09) is one element field per cast, add or replace.
- (a) **Two fields: a shape field and a ride field**, each none or one element, each with the spell's authored default. Fire shape with a Cold ride is legal; a hit still carries at most one element (the ride's). **Tentative pick**: it is the only option that gives "both, or neither, or some other combination".
- (b) One field plus a per-cast toggle (ride, shape, or both) for that one element. Simpler UI; no mixed elements.
- (c) One field; each spell authors whether its row for that element rides or shapes. The caster never chooses.

**2. One count feeding both fields: split or shared?**
- (a) **Split**: the caster divides their Fire count between shape and ride. A real choice at counts of 0..5. **Tentative pick.**
- (b) Shared: both read the full count. Stronger, nothing to decide.

**3. What does one point buy for Fire and Lightning?**
The three shapes cost the same point, so they should be worth about the same; this is also the frame that prices Ice.
- Fire: seed disc sized like Burning's (√N × node radius, the owner's disc formula) · a per-spell authored radius per point.
- Lightning: +1 hop per point · an authored rate per spell on the row's int:int affinity, as Ice has. Check against the ruling that `max_hops` takes no stat scaling (owner, 2026-09-02, `docs/domain/spell-propagation.md:444-473`): is a per-cast forge load a stat scaling?
- Do the disc's and the extra hops' landings carry the full payload or a share?

**4. The price of an Ice hop.**
- (a) One `bonus_per_hop` knob per spell, default 0.5 (the lean). Per-spell tuning covers "+100% in some cases, +25% in others".
- (b) An authored bonus per hop removed (a small array per spell), so the first hop cut can pay differently from the last.
- (c) Priced against Lightning: removing a hop pays what adding one is worth.
- The risk to settle against: Pestilence gives up ~84 measured landings for a ×4 seed at the lean, so the concentrate is a trap unless focus itself buys something (breaking ice, a kill threshold, a go-off copying the larger payload).

## The look (when built)
The forge shows each field's effect as the count changes: "N hops → M, seed ×X", the disc's size, the added hops, and why a spell refuses a shape.

## Notes
- The Cold spell #1789 (Needs design) carries the Ice shape as its innate, eating its hops to 0. Settle the two together.
- ADR 0081 §7 (one element field) and §8 (the multiplicative ladder as the Ice price) are touched by whatever is picked here; corrections go to the sibling issue for ADR corrections.
- The Frozen vertex's snap is a blade concentrate (#{ice}), not this.
