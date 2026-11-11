---
status: settling
---

# Elements — Frozen: the snap, the breakers, pair rules

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## A blade on Frozen, and what breaks the ice (owner, 2026-11-08/10/11)

**A blade on Frozen: a fragile snap.** Owner, 2026-11-08: *"if a melee blade
node has Frozen on it, if should shatter on first contact. Reduces reach
right? Any blade node popped is less sweep. And if frozen node is hit by
blade node, it.. shatters the ice … but *also* shatters the offending blade
node!"* (the blade's touch is one breaker among three — § What breaks the
ice), then *"We want to pop just the two vtx. Not too dramatic, and
remember Ice is 0D. Point like. Single target. So no splash or anything just
a fragile snap"*. First contact pops that one vertex (the spike pop, no drain
check, nothing severed) only if the node is still Frozen after that contact's
terrain riders. **A vertex whose touch thaws the node with its own Heat does not pop**
(owner, 2026-11-11, picked *No pop: read after riders*): the contact lands as
on an unfrozen node, with no break, no burst and no extra landing, and the
vertex keeps sweeping. It is the same read as the path end (a path ends at
Frozen only if the node is still Frozen after the arrival's terrain riders). **A touch that breaks the ice lands as a normal
hit, then the vertex pops** (owner, 2026-11-11: *"So basically bladd node
should land as normal but with a guaranteed shatter (and then pop)"*): its
payload lands, the ice shatters — the break's channels (2 by default) and
the burst land (§ What breaks the ice) — and only then does the vertex snap.
**The touch breaks the ice only if the vertex is at least as heavy as the
node** (owner, 2026-11-10: *"melee blade nodes shatter frozen nodes they hit
*only if their radius is equal or larger than the node they hit*
(specifically: if they have more weight; ignoring temporary modifications by
e.g. passing over Cold (but not frozen) nodes)"*). Weight is the blade sim's
mass, `(radius / 32)²` — the vertex's from its source node's radius times
Bunker's `blade_mass` (owner picked *Bunker counts*: a build choice, not a
temporary modifier), the node's from its own `SkillNode.radius` (stake growth
included) by the same formula. A tie breaks (*"equal or larger"*). Nothing
per-contact enters the weight: Cold's drag (and the parked "tune the PBD
weight" aside, were it built) is ignored. ADR 0088 records the weight gate
and the breaking touch, ADR 0090 the lighter vertex's plain hit. A lighter vertex still snaps and the ice holds (owner picked *snaps, ice holds*, with *deflects off the ice* —
the vertex recoils like a defender plate, deals nothing, nothing breaks — as
the fallback *"if it turns out to nerf melee too much"*). **Every blade
contact lands as normal; weight decides only whether the touch breaks the
ice** (owner, 2026-11-11, picked *lands as a plain hit*): a lighter
vertex's contact lands its payload as a plain hit — no break, no burst, no
extra landing — and then the vertex pops. Its contact still breaks the ice
through the other two breakers (owner picked *only the touch is gated*), so
a light vertex whose contact crits or whose damage (mitigated, as the floater shows it) clears the threshold
shatters it, and that contact lands as a breaking hit: its payload, the
break's channels and the burst, then the pop. **The burst is
corruption-shaped** (owner, 2026-11-08: *"frozen side: effect removed at %maxhp propto the amount
removed"*; earlier: *"maybe %dmg like corruption stack triggers?"*): the
shatter removes everything above T, overflow (deep freeze) included, and
deals excess × a knob fraction × max HP to the frozen node's holder as TRUE
damage, nothing if unallocated — the same shared burst path corruption's
topple uses (`CorruptionStatus` deals topples × threshold × 2% of max HP
through `DotTick.mint`), so there stays one implementation of "a burst
lands". The crit side is dropped for now (owner, 2026-11-08: *"drop crit for
now. might do something else with it later"*); the spend fraction is a knob,
default 1.0 — everything above T.

**What breaks the ice** (owner, 2026-11-08): a blade vertex's touch (one at
least as heavy as the node — owner, 2026-11-10, § A blade on Frozen), **any
crit hit landing on the node**, and **any damage at or above a flat
threshold** — a knob, default 10% of the holder's max HP, deliberately *not*
scaling with excess (owner: *"a flat amount not scaling with excess. else it
would mean that a deep-frozen node would require more damage to shatter
right? and that doesn't sound good"*). Each triggers the shatter. **The damage read is the number the player sees** (owner, 2026-11-11, 02:43: *"If dmg is checked first and then riders land that e.g. raise min dmg taken then the actual hit resolves differently compared to the check at the start. And that feels like gaslighting the player."*, then, ~16:29, on the beat-scoped riders-after-damage order below: *"sounds agreeable"*): the breaker reads `Mitigation.compute` (armor and the `min_damage_taken` floor, `attack/formulas/mitigation.gd`) on the arrival's amount, crit already multiplied in (`CritRoll.apply`) and times its load multiplier, against the node as it stood before the beat. That is the floater's number, because within a beat all damage lands before any aspect rider ([hit-resolution.md](hit-resolution.md) § Landing resolution), so no rider can move the floor or the armor between the read and the landing. Armor hardens ice (a Bolt of 12 on Bunker ice floats 6 against a threshold of 7 and holds), the floor lifts a small hit as it lifts the floater, and the "% max health" breaker stays, read mitigated. The read is the arrival's own landing, before the break adds its channels, so the test is not circular. **Each arrival is tested alone** (owner, 2026-11-11, picked
over *summed per generation*): weak arrivals of one generation (below) never
sum toward the threshold, which keeps one clear breaker to hand the break's
landings to. A landing the dedupe merged ([hit-resolution.md](hit-resolution.md) § Landing resolution, "Dual
reach") is one arrival at its summed multiplier, mitigated (owner, 2026-11-11, picked:
*"the merged landing IS the arrival: its 2x amount is tested once"*): with
dedupe on, two channels' damage sums into the one amount the break tests,
and with it off the entries are separate arrivals, each tested alone. A blade contact is read at what it deals, mitigated. This
holds while a damage breaker exists. **A Frozen
node with no holder has no flat breaker** (owner, 2026-11-11, accepted when
asked): there is no max HP to measure against, so a copy that does not crit
is absorbed whatever its damage, and the ice breaks only by a crit or a
blade touch (the burst is nothing there); Heat and decay still end it.
**Breaking the ice counts as a channel** (owner, 2026-11-10, night: *"Break
counts as a channel (or more radical: 2, more concentrated single target
vibes) sounds like a fitting unification"*): it is Frozen's match for the
whole hit ([hit-resolution.md](hit-resolution.md) § Landing resolution) and the 0D case turned inward (above). **A break
counts as 2 channels** (owner, 2026-11-11: *"+1 is what a 1-burning node
would get already. Shatter is aggressively single target."*, then *"2 for
now sounds good. Can retune later, most likely a knob or const"*): the
shattered node takes two more payloads of the hit that breaks it, on top of
that hit's own landing, plus the burst. The extra landings carry damage and
aspect riders only, as every extra landing does; the count is a knob or
const, default 2 (ADR 0090). That holds for a hit, a copy or a blade touch
that breaks it (§ A blade on Frozen). The threshold applies to direct hits and arriving copies alike — the glass
ceiling of 2026-11-05 unified with the *"a hit that deals X amount of % max
health"* breaker: a copy that breaks through also lands — so deep freeze
raises the burst's stakes, never the wall's strength. Heat and decay still
end Frozen without a shatter: a thaw is not a breaker, so a Heat rider netting
Cold below T ends Frozen with no shatter and no burst. No re-evaluation
anywhere: the break check reads three facts, each the hit's own — its crit
(decided at the head of the gather, pre-hit), the blade vertex's weight
(build time) and its mitigated damage. **Frozen reads at two points** (owner, 2026-11-10,
picked *admit on arrival, the rest after riders* over all of Frozen reading
pre-hit): whether an arriving copy is absorbed is checked on arrival,
against the node as it stood before this generation; the path-end and the
break check read after the element riders land, once over all of the
generation's arrivals at the node (below), as Burning and Shocked do. **The admit gates a copy's damage and
aspect riders only; terrain lands at the tip of every hit** (owner,
2026-11-10, night: *"How i see it: terrain sits at the tip of each hit, and
lands no matter what. It can thaw a freeze? Or prime a node as it hits? (Or
that last one might be a little intense but still kinda valid?)"*). An
absorbed copy's Heat, Cold and Charge land all the same, once per node per
hit: Heat on an absorbed copy can thaw the ice, and a tipping rider primes
the node as it hits (terrain riders first, ADR 0083 §1). An arc's transferred Charge
lands too: it moves with the spend, before the next node's admit. ADR 0087
records this and the walk past a shatter (below), amending ADR 0083 §2.
So a hit that freezes a node ends its own walk there, a crit or heavy hit that freezes it
shatters it at once, and a Heat hit that thaws it passes through without a
shatter. **An arrival that breaks the ice walks on**
(owner, 2026-11-10, night: *"Arrival shattering sounds like it should no
longer be blocked tbh. But might be sensitive to race conditions e.g. during
many nodes being hit simultaneously during a magic spell's Wave (beat)."*):
it lands, and its path goes on past the shattered node. **Same-beat
arrivals at the ice: the node settles first** (owner, 2026-11-11, picked over
*Frozen for the whole beat*: *"Option 1 sounds best"*), answering the
owner's requirement (2026-11-11): *"Players see: ice on a node. Then a spell
bounces on that node and the shocked nb. The ice, it shatters or it
doesn't, that's the primary continuation we need to make clear. And if it
shatters, the end state would be the same no matter which hit is resolved
first like if it shatters the lightning arc either always passes through it
or it never does, shouldn't be up to the in-wave hit resolution order"*. A
beat lands in generations ([hit-resolution.md](hit-resolution.md) § Landing resolution): the beat's own arrivals
first, then each go-off's copies one generation later. Within a generation
every arrival at the node lands its terrain riders at once; the node is then
read once over all its arrivals — primed state, Frozen, and whether it
breaks — and only then do paths leave it. If any arrival breaks the ice, it
shatters once, with one burst, and every path through it walks on; only the
breaking arrival or arrivals take the break's two extra landings, each of
its own payload, and each sets off the node's trapped go-off (§ Pair rules). A sibling of that generation that does not break the ice
keeps what its admit decided on arrival (an under-threshold copy stays
absorbed) and still walks on, as an absorbed copy whose Heat thaws the ice
does. **An absorbed copy whose Heat thaws the ice walks on** (owner,
2026-11-11, picked: *a path ends at Frozen only if the node is still Frozen
after the arrival's terrain riders*): the rule is the read after the riders,
as for every path at the node. The answer is decided once per generation,
not once per beat: the ice can hold against a wave's direct hit and shatter when a crit
arc copy reaches it a generation later, and the result never depends on
resolution order. The owner's case: a wave lands on Frozen A and level-2
Shocked B in one beat; B's arc reaches A one generation later and passes
through if the wave's hit shattered A, and stops there, unless its own copy
breaks A, if A held. So the ported Cold spell's chain ([open.md](open.md) § Open, "v1 spell
content") still shatters every Frozen node it crits on. ADR 0091 records
this.

## Pair rules (from the threshold model and #1444)

Rows are what rests on the node, columns what arrives; a blank cell means
*nothing special*.

| On the node ↓ / arriving → | a hit (a copy and a blade vertex included) | the opposite temperature (rider or flow) | a Frostbite pack |
|---|---|---|---|
| **inert** (count ≤ T) | lands; a blade feels `t` (Cold drags, Heat speeds) | nets | sheds Cold first: the toll (#1444) |
| **Burning** | explodes ([go-offs.md](go-offs.md) § The trigger and what a go-off pays) | nets before the read: a Cold rider cools it for its own hit (terrain riders first), a flow for the next landing | |
| **Shocked** | arcs to every neighbour; a spell walk conducts | | |
| **Frozen** | a direct hit lands; a copy under the break threshold (with no holder, any copy that does not crit) is absorbed (its terrain riders still land) and the path ends, only if the node is still Frozen after them (owner, 2026-11-11); a breaking hit or copy lands, takes two more payloads (the break counts as 2 channels) and walks on; a blade vertex's contact lands as a normal hit and the vertex snaps (unless its own riders thaw the node first), and one at least as heavy as the node also breaks it | nets before the read: a Heat rider thaws it for its own hit (terrain riders first), an absorbed copy's included, a flow for the next landing | cold passage: no shed (#1444) |

**Frozen mutes the node's own go-offs; the break releases what it trapped**
(owner, 2026-11-08: *ice wins — frozen solid*, then, after the deeper look it
asked for, *trapped until broken*): a node both Frozen and Shocked does not
arc — the Charge sits trapped under the ice, and Charge an arrival lands joins
it. A cast's shape is not muted ([casting.md](casting.md) § Shape and ride). Freezing a wire cuts it
and stakes the trapped Charge as a visible bomb. **The release is once per
hit that breaks the ice, tentative pending playtest** (owner, 2026-11-11,
picked: *"The ice releases its trapped go-off once for each hit that breaks
it."*; then: *"mark it as tentative, given playtesting will see if this is ok
or needs to be toned down (e.g. alternative would be: collect all cascaded
towards nodes (via blasts / arcs separately) as one union (for each channel)
per hit. )"*). The toning-down alternative: each hit collects every node its
cascade reaches into one union per channel, blasts and arcs separately, so a
node lands once per channel per hit. As the current rule: a Frozen node is still
read once per generation and shatters once, with one burst, but each hit of
that generation that breaks the ice sets off the node's trapped go-off as its
own, the same once-per-hit count an unfrozen node goes off with ([hit-resolution.md](hit-resolution.md) § Landing
resolution), crack the ice, release the storm, plus the shatter burst. Each
release carries the payload of the hit that set it off, and its *power*
follows the one power rule ([go-offs.md](go-offs.md) § The trigger and what a go-off pays): it is read after that
hit's own riders land, so a Charge-carrying breaker feeds the storm it
releases (owner, 2026-11-10, picked *after the hit lands* over the trapped
Charge exactly as it sat). A hit the ice absorbed sets nothing off, even when
another hit of its generation breaks the ice; it still walks on. When a thaw
leaves no ice at the read, nothing is muted and the node goes off as any
unfrozen node does. Arrows land one beat at a time, so only a magic wave puts
several hits in one generation. One compound read, never a re-evaluation: a
hit's crit and damage are its own facts, and both states are read after its
riders land.

**Frozen is a boon with two costs** (owner, 2026-11-05, asked for drawbacks
and kept exactly these): *cold passage* — a Frostbite pack crossing it pays
no shed and Afterdrop turns it into a pack aimed at its owner (#1444) — and
*brittle* — a blade vertex touching it lands its hit and snaps (unless its own riders thaw it first), and when it
is at least as heavy as the node it breaks the ice before it snaps (§ A blade on Frozen). The list is open to more small costs of that grain (owner:
*"possibly we find more small things like what Cold passage to add later"*),
and your own spells walk less far through it. Rejected: a Frozen node unable
to launch attacks, and suspending its stat contributions.
