---
status: settling
---

# Elements — reach as terrain

> Design doc: what an element *is* and *is not*, beside the aspects of
> [aspect_matrix.md](aspect_matrix.md). Owner calls are dated and quoted;
> everything else is a pass proposal. Nothing elemental exists in code yet;
> the issues carrying the build are #1716 (the axis, Lightning), #1660 /
> #1695 / #1696 (Fire), #1444 (Ice), #1733 (payload and reach across facets).

## The two axes (owner, 2026-11-03/04)

An entity has three kinds of growth: the six primary attributes, its aspects
(*"how Poison are you"*: `poison_aspect`) and its **elements** (*"how fire
are you"*). Owner, 2026-11-03: *"i see it like an entity has: primary attrs
(6), a bunch of aspects (poison, curse, hex, etc it goes on), an elemental
composition or affinity [new]"*; 2026-11-04: *"Separate axis sounds good"*.
Elements are **not** a parent of aspects (owner, 2026-11-04: *"elements not
being parents of aspects makes sense"*), and an aspect never belongs to an
element: Hex is never "lightning-typed".

**An aspect is one status; an element is a family.** Owner, 2026-11-04, on
re-enforcing Aspect:Status as 1:1 with elements the only axis that owns a
status family: *"option 1 sounds very clean"*. ADR 0072 records it. The code is 1:1 today
(`aspects/aspect.gd` holds one `status`; thirteen aspects, thirteen defs);
the widening #1694 asked for was only ever for Fire's second status, and Fire
is now wholly an element, so #1694 is unneeded; the 1:1 is to be guarded by a test (none exists yet).
Poison's "does it move" idea (#1657) must therefore be a behaviour of the one
Poison status, never a second one. Fuel left Fire and is **Catalyst**
(§ The threshold model), the Explosive aspect retagged.

## The threshold model (owner, 2026-11-08)

Owner, 2026-11-08: *"make them all inert before some threshold T is passed.
when "elemental terrain-reach stacks" (== cold/heat/charge stacks) exceed T,
then they become primed -- the derived status … this derived effect has a
"trigger" and if triggered it performs (generally) a reach-based action, and
finally, each triggering has a stack-cost … this derived status IS the reach
face of the element. without it, no reach effects"*.

**One terrain stack per element, inert up to T.** Heat (Fire), Cold (Ice) and
Charge (Lightning) are side-less terrain, owner-blind. At or under T they
only *feel*: Cold drags a blade and Heat speeds it, one curve of the signed
`t = heat − cold` (owner: *"maybe cold stacks slowing blade nodes sweeping
over them (and heat stacks... should speed them up a lil?)"*; pass knob,
2026-11-08: sweep-speed × `clamp(1 + c × t / T, 1 − c, 1 + c)`, `c` exported
on the blade def, default 0.5 — tentative, easy to change). Past T the node
is **primed**: Burning, Frozen, Shocked. **T = 2 × graph degree**, primed at
count > T (owner: *"T = 2*graph_degree, so a leaf node fits 2 stacks of any
without any effects, the third would be 3"*), a knob. The **excess** is
count − T; the band above the cap k × T is the **overflow**.

**Reach is terrain-only.** A hit is damage plus riders and carries no reach of
its own; reach is read off the node it lands on. Owner, 2026-11-08: *"Think that charge settles it in favor of the
"there's 1 and its just the terrain stacks": if 1 "charge as direct arc
reach" is infused it reintroduces "which one neighbor then?" While a system
where "charge Level = 1" means you got enough to hit *all* nbs."* What an
element infusion does is an open set of uses (ADR 0070's swappable
`LoadUse`; owner, 2026-11-08: *"spell infusions may also do bespoke stuff
instead of simply adding riders, we are free to design what feels useful and
fun to have"*). A ride row planting Heat or Charge is one use, so an infused
AoE spell ramps: its early hits warm the ground, its later hits blow it. A
bespoke `shape` use is another, as Firecracker's blast waves and Ice
concentrate are; it may shape the cast (Ice trading hops for payload at cast
time) but never gives a hit a reach entry. ADR 0075 records the threshold
model and terrain-only reach.

**The trigger is a hit on a primed node**, a copy included, so a chain needs
no rule of its own:

| State | A hit on it | Also |
|---|---|---|
| **Burning** | explodes: a disc, power = the excess, a little damage ∝ power, the triggering hit's payload copied over the disc | burns its holder each world turn ∝ the excess, side-blind (owner pick, 2026-11-08) |
| **Shocked** | arcs to **every** neighbour (owner: *"it will arc to *all its neighbors* each time it is hit"*) | conducts a spell walk (§ Derived states) |
| **Frozen** | denies: a copy under the break threshold is absorbed whole (no damage, no riders), a path ends (0D); a direct hit lands (owner, 2026-11-09, picked *absorbed* over *lands, then stops*) | a blade snaps on it (below) |

**What a go-off pays (owner, 2026-11-08): 1 per node it reaches.** One law
across the triad: a trigger pays 1 stack per target its reach touches —
Shocked 1 per neighbour struck (*"charge is more travel-across-edges-ey"*),
Burning 1 per node its disc covers (picked over 1 per blast, whose big disc
underpays a shock — *"at some explosion size, fire would hit basically "all
its nbs" like equalling a shock to each nb"* — and over a radiating transfer,
which mirrors the diffusion flow), Frozen the 0D case turned inward: one
target, the whole store (§ A blade on Frozen). A blast whose disc reaches no
*other* node **does not go off** — no spend (owner: *"possibly extend this rule to
make it cost 0 if it hits nobody?"*, framed as no targets, no go-off, so
every go-off still voids at least one stack — *"there should be at least 1
stack disappearing, possibly more"*). A spend pays its full cost even when
that digs under T (owner picked *dig below T* over clamping at T: a degree-4
node at 9 Charge arcs all four neighbours at cost 4 and drops to 5 — *"would
decharge more rapidly"*). **Power is the excess read after the triggering
hit's element riders land**, a consequence of the two-stage order (§ Landing
resolution; owner, 2026-11-09): primed-ness and the Frozen check read
pre-hit, while the disc's size — and so whether anyone is reached — follows
the post-land power. The Heat a hit lands joins its own blast: 1-Heat arrows on a
sub-reach node charge it hit by hit until the disc first catches a neighbour
— the owner's ramp (*"heat builds up as arrows land, critical at some point,
then explodes spreading, then heat up again, more explosion"*) — and a capped
degree-5 hub pays out as roughly 20 → 10 → 5 → 3 → 1, the volley (*"explode
for size(F), size(F-1), …, size(1)"*) in topology-sized steps. What
no-target-no-spend costs: a tiny fire cannot be beaten out by hitting it;
Cold and decay are the extinguishers. The spend destroys stacks and hands
none to the reached nodes; only the triggering hit's riders ride the copies. **Copies carry everything**, element
stacks included, chained links flat (owner, 2026-11-08: *"everything rides
yeah, LET IT RIDE! can change that later if it becomes too much"*); the spend,
the cap and decay are the brakes.

**Size.** Burning's disc is Euclidean, radius = √power × node diameter (2 ×
node radius), power = the excess (owner, 2026-11-10: *"i was actually
thinking ×2. like twice the node radius = 1 node diameter"*; first form,
2026-11-08: *"size(N) ≈ sqrt(N)×node_radius so chances are power 1 doesn't
hit any node, but that's tuning"*). It is one formula with three readers
(owner, 2026-11-10: *"burning's go-off would be the same AoE radius here, as
burning's light source, as well as the proposed "Fire reach" part of a
spell"*): the go-off's disc, Burning's light radius, and a Fire shape on a
cast (§ Shape and ride; what a point of that shape is worth is open). On
150 px spacing a ×2 disc first touches a neighbour near power 4 and covers
every neighbour near power 9 (rescaled from a simulation of the ×3 disc, not
re-run). Today's Explosive disc keeps its 3.0 until the retag deletes it.
Shocked's hops: level
L at count > L² × T (owner: *"T = 1 hop, 4T = 2 hops, 9T = 3 hops"*). Knobs.

**Catalyst is a converter, in no family.** Owner, 2026-11-09, on where Fuel
sat: *"so my relevation yesterday was: maybe we should move Fuel OUT of Fire,
and turn it into smth like "Catalyst" instead, and let it act on any incoming
elemental-terrain status (Heat, Cold, Charge)"*, and on the trade: *"like "3
Catalyst" has incoming hit of "2 Heat" and it turns it into "5 Heat" doing a
1:1 Catalyst→{incoming element} trade."* Catalyst is one **aspect status**,
inert and colourless: it never counts toward T, never primes, never goes off
and has no derived state, and it lives on allocated nodes only, clearing with
its holder as Poison does (owner, 2026-11-09: *"i think catalyst only sits on
allocated nodes like most/all Aspect statuses (but we can always make an
exception and make it owner-agnostic)"* — taken as settled: it is exactly the
shape the Explosive status already has, so the retag changes no lifecycle,
and a blast's copies land on hostile allocated nodes anyway). When a hit whose
payload carries exactly one element rider (Heat, Cold or Charge) lands on a
node holding Catalyst, the node's whole Catalyst store converts 1:1 into that
element (ratio 1:1 a knob), so 3 Catalyst plus an incoming 2 Heat is 5 Heat on
the node. The conversion happens in the **land** phase, the rider's stacks
amplified as they are added, so § Landing resolution's read/land/settle
stands: primed-ness still reads pre-hit, and the converted stacks count toward
the post-land power and the next hit. **Colouring** (owner, 2026-11-09: *"option 1. or: also when "igniting"? in
the broadest sense like when enough Heat turns into Burning (through flow,
hits already covered), or when Cold turns into Frozen, or when Charge turns
into Shocked? still element-symmetric right?"*). Owner call, 2026-11-09,
picked *hits and priming*: the whole store converts into an element in
exactly two cases, (a) a hit carrying that
element's rider lands on its node (land phase), (b) the node primes, its
stack crossing T into Burning, Frozen or Shocked by any route, read at
settle. Flow below T never colours it. The rule is symmetric; in practice only
temperature reaches T without a hit, since Charge never flows and an arc's
copy is a hit, which is Charge's "stays put" character, not a rule. A goo
arrow landing on an already-primed node carries no element and flips nothing:
it is an ordinary trigger, the blast goes off at the node's current excess
and its copies carry the Catalyst rider over the disc (barrels laid where the
blast reached), while the Catalyst on the node itself waits for the next
element. **The trade** (owner, 2026-11-09: *"this is turning into a real
chemistry question. both options have something going for them. i think
option 1 sounds best for now. option 2 is more like the Greed's "slice"
mechanics but that was mostly needed to make multi-status payloads play nice.
and iff we decide a hit can have at 0 or 1 Element associated with it then we
don't need the "slice" part and can just consume all"*): the whole store, 1:1,
no slice. A hit carries 0 or 1 element (§ The forge's one element per cast,
generalised to every hit; copies carry the root hit's one element). A copy is
a hit, so a blast's or arc's copies carrying
an element rider colour the Catalyst on every node they reach. It is the
element analogue of Greed: Catalyst multiplies incoming element stacks the way
Greed multiplies aspect stacks, and Greed must not (owner, 2026-11-09: *"in
essence this is almost like what Greed is for Aspect Statuses, but for
Elements (i think Greed shouldn't multiply incoming Heat/Cold/Charge stacks,
but Catalyst may?)"*). Catalyst stays put (no flow) and decays slowly (knob);
the map's barrels are the Catalyst addon on map nodes, as the Explosive
barrel addon is today. **Catalyst is an
aspect, the Explosive aspect retagged** (owner, 2026-11-09: *"yeahhh exactly
option 1. w/visually like purple crystals or smth instead of black goo"*; the
line behind it: *"Aspects do anything else"*): one status, side-less terrain,
count `catalyst_aspect`, school DEX (where Explosive sits), facets
`catalyst_stacks_per_hit` / `catalyst_resistance`; the goo arrow plants it. Two volley shapes: Heat arrows
sustain, each landing adding its own stacks; Catalyst-then-Heat makes the
first Heat landing a big one (3 Catalyst plus 1 Heat on a leaf, T 2, is
Burning at once with excess 2). No node holds Catalyst at a go-off that
matters: it is gone at landing, so no world-tick fuse exists.

**A blade on Frozen: a fragile snap.** Owner, 2026-11-08: *"if a melee blade
node has Frozen on it, if should shatter on first contact. Reduces reach
right? Any blade node popped is less sweep. And if frozen node is hit by
blade node, it.. shatters the ice … but *also* shatters the offending blade
node!"* (the blade's touch is one breaker among three — § What breaks the
ice), then *"We want to pop just the two vtx. Not too dramatic, and
remember Ice is 0D. Point like. Single target. So no splash or anything just
a fragile snap"*. First contact pops that one vertex (the spike pop, no drain
check, nothing severed) and breaks the ice. **The burst is corruption-shaped**
(owner, 2026-11-08: *"frozen side: effect removed at %maxhp propto the amount
removed"*; earlier: *"maybe %dmg like corruption stack triggers?"*): the
shatter removes everything above T, overflow (deep freeze) included, and
deals excess × a knob fraction × max HP to the frozen node's holder as TRUE
damage, nothing if unallocated — the same shared burst path corruption's
topple uses (`CorruptionStatus` deals topples × threshold × 2% of max HP
through `DotTick.mint`), so there stays one implementation of "a burst
lands". The crit side is dropped for now (owner, 2026-11-08: *"drop crit for
now. might do something else with it later"*); the spend fraction is a knob,
default 1.0 — everything above T.

**What breaks the ice** (owner, 2026-11-08): a blade vertex's touch, **any
crit hit landing on the node**, and **any damage at or above a flat
threshold** — a knob, default 10% of the holder's max HP, deliberately *not*
scaling with excess (owner: *"a flat amount not scaling with excess. else it
would mean that a deep-frozen node would require more damage to shatter
right? and that doesn't sound good"*). Each triggers the shatter. The
threshold applies to direct hits and arriving copies alike — the glass
ceiling of 2026-11-05 unified with the *"a hit that deals X amount of % max
health"* breaker: a copy that breaks through also lands — so deep freeze
raises the burst's stakes, never the wall's strength. Heat and decay still
end Frozen without a shatter. No re-evaluation anywhere: a hit's crit and
damage are its own facts, and every check reads pre-hit state.

**Cooling.** Heat is terrain, so it rests on unallocated ground as Cold does;
every warm or cold node decays 1 toward zero per world turn (owner: *"if we
make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it
should eventually cool off"*), Charge likewise, Catalyst slowly — knobs. The
Metropolis step is the discrete graph-Laplacian step; its integer floor is a
dead band, and the decay clears it. Every warm node loses one, so spread heat
cools faster than a lump: no board-wide budget is needed.

**Reading it: a capacity bar on hover** (owner idea, 2026-11-08: *"neat UIs
of "element capacity" in blocks e.g. when hovering nodes. Hover leaf node and
see N*degree empty blocks for heat/cold and maybe sparkles inside for
counting blips of Charge (same threshold? Tho excess.. can make this
messy)"*). Pass proposal: **one block = degree stacks** (one arc's cost; a
blast pays per disc node).
With T = 2 × degree every node's bar then has the same shape: 2 inert blocks,
then 2(k − 1) primed blocks to the cap (4 on bare ground, +2 per stake), and
each lit block reads "one more blast left". On a leaf a block is one stack, so
the blips count exactly; on a hub a block fills in fractions. Heat and Cold
share one bar, filling red or blue, since they net and a node holds only one
sign; Charge gets a second bar of the same shape with sparkles; Catalyst, which never counts toward T, is a crystal layer
under both bars (owner, 2026-11-09: *"purple crystals or smth instead of
black goo"*), violet until it takes the colour that lands. The overflow
is a few blocks past the frame that flicker and fade, so the fast decay is
visible and the bar never grows unbounded. Same thresholds for all three, so
the messiness the owner flagged stays in the overflow tail.

**Where it sits and what it reads** (owner, 2026-11-09). The terrain bars sit
at the **south side of the skill node** (*"since these are terrain
properties, something tells me UI bars for these should be at the south side
of the skillnode"*), apart from the status icons, which are rows. The label
is **one entry per element, updated in place**: the band's name with the
total count against T (*"show total with different name, and tooltip
indeed"*) — `Heat 6/6`, then `Burning 7/6`, back to `Heat 5/6` after a
blast — and the tooltip gives the excess and the power it buys. Never a
second entry beside the first: the node holds one number.

## One count, a family of statuses with fixed roles (owner, 2026-11-04/08)

An element is one count on the entity and a short family of statuses on
nodes. Nobody points at "the" fire status; the **roles** are what you point
at (owner, 2026-11-04: *"that table looks very good, should be persisted"*).

| Element | Count (entity) | Terrain stack — side-less, inert up to T | Beside it | Primed state — past T, derived |
|---|---|---|---|---|
| Fire | `fire_element` (shown "Fire attunement") | **Heat** | none; Catalyst (§ The threshold model) sits beside every element, in no family | **Burning** |
| Ice | `ice_element` | **Cold** (owner, 2026-11-05: *"Cold i think. Frozen is a different effect, derived by Cold count (and degree) … frost sounds too "already being a DoT""*) | **Frostbite**, the mover: #1444's inward pack, sided, hurts | **Frozen** |
| Lightning | `lightning_element` | **Charge** | none in v1 (owner, 2026-11-04: *"Fun but maybe start with just the 1"*) | **Shocked**, #1733 round 3's *critical Charge* under its name |

- **The count never ticks on anyone.** A mover is an ordinary sided status
  that clears with its owner like Poison does; terrain hurts only through its
  primed state (a blast, Burning's burn).
- **Terrain is side-less.** A terrain stack rests on a node
  regardless of owner, survives kills, retakes and deallocs, and leaves by
  being *spent* (a go-off spends its own node's stacks), by decay (per-def,
  ADR 0048; § The threshold model's cooling) or by a cleanse. **A holder's
  death changes nothing**: death is not a hit and terrain cannot see owners
  (owner, 2026-11-08, picked *nothing — terrain persists* over a terrain hit
  per primed node; #1660's "death blasts first" is pre-threshold history).
  The battlefield a fight built stays dangerous for whoever retakes it. Heat and Cold
  flow as one signed `t` (§ Temperature) and rest on unallocated ground; Charge
  stays put. Catalyst is not terrain: an aspect status, allocated nodes only
  (§ The threshold model). Owner, 2026-11-05, on a capped wall beside bare
  neighbours: *"something doesn't quite feel right of a 100 Cold node with
  neighbors of 0 Cold … just sits there as if perfectly isolated"*, then
  *"option 1!"* (flow): a wall sheds a fringe around it, #1444's channels for
  free. The readability test: *if nobody owned this node, would it still make
  sense for this to be here?* Heat on an empty node, yes; Poison or Catalyst on
  an empty node, no. **Terrain is node state, not a status row** (owner,
  2026-11-09: *"these are actually just node state no? … imho it's a property
  of a SkillNode"*, and *"if it is modified mid combat, the combat mirror
  world might need to know about it"*): two ints on `NodeState` (the signed
  `t`, and Charge). Every shadow world already clones `NodeState` on a node's
  first touch, so previews and AI scoring see terrain for nothing, and no
  `on_dealloc` path can clear what is not a row. Heat, Cold and Charge stay
  `StatusDef`s for identity, facets and riders; landing one writes the node's
  ints, never a host row.
- **A state has no count.** It is a threshold on its terrain stack (primed
  at count > T), derived at every read, never saved: Frozen re-forms whenever
  Cold is back over T (owner, 2026-11-05: *"Yes, pure threshold"*).
- **A terrain stack is capped per node at k × T**, **k = 2 + the node's
  `stake_level`** (owner, 2026-11-06: *"k = 2 (base value) + stake_level
  (statformula)"*) — a derived scaling rule on the node board (manage-stats),
  so a deeper-staked node holds more terrain and bare ground (`stake_level`
  1) gives k = 3. `stake_ceiling` is 3 unless raised, so k runs 3–5; a leaf
  (T 2) holds 6–10, a degree-5 hub (T 10) 30–50, which late counts (20–50)
  can fill. The cap is soft: stacks past it are the **overflow** (§ Derived
  states). **Catalyst takes a cap of the same k × T** (pass default, carried from the
  Fuel cap the owner picked on 2026-11-08, over sharing the temperature cap or
  none): one derived rule reused, one bar shape. The converted stacks land into
  the element's own cap with the overflow rules, so a blast is bounded by
  k × T alone. Owner, 2026-11-05, asked whether a 100-Cold wall should be nigh
  impossible to remove: *"option 1 sounds good"* (the cap) over proportional
  decay alone. One rule bounds a Cold wall's depth, a blast's power and a
  Shocked node's hops — the magnitude fork of #1733 round 3.

## The count is supply, never a load (owner, 2026-11-04)

The count is a budget a face draws from; by itself it loads nothing onto a
hit. Owner: *"this is like "how Fire/Ice/Lightning ARE you really" counter,
which likely ends up being a maximum/budget of sorts for some situation, but
in most cases doesn't load automatically (maybe some cases would arise later?
so far just none)"*. This is the same sentence an aspect count already says —
X poison means X poison arrows a reload, X of poison-costing temp addons, X
maximum poison infusion — and it keeps #1733 R2: a stat never grants a hit
reach, so a 30-vertex sweep blasts only where it crosses primed terrain. A
build with zero in every element still sets off terrain others primed;
nothing in its own hits changes.

The counts are meant to grow well past the small ints aspects sit at today.
Owner: *"attaining 20 of it, or maybe into 50 or possibly even 100 (tho 100,
that's a stretch. 50 sounds *somewhat* reasonable for late game …)
everything starts small. the inner-core mini skill tree, i envision, would be
one of the primary sources of adding +1..N modifiers to aspects, alongside
map-found modifiers, or stolen mods from slain enemies"*. Every rate that
reads a count is therefore an int:int affinity (ADR 0060), never "one count,
one hop".

## The hit: damage and riders (owner, 2026-11-04)

A hit has two kinds of entry, together its **payload**, and no reach of its
own (§ The threshold model):

| Entry | Shape | Lands as |
|---|---|---|
| **damage** | one number | HP loss |
| **riders** | status id → stacks, one summed entry per id per landing entry (#1733 R1; owner, 2026-11-09, picked the summed map) | statuses planted — aspect statuses and element statuses alike |

A hit crits once, as its own fact, and its riders copy it (#1741, built
2026-11-04), **and so does every go-off copy** (owner, 2026-11-09, picked *it
rides* over flat copies; ADR 0082): a spell blast's shrapnel rolls its *own*
crit today (its `paired` is null, so `draws_own_crit()` is true and
`CritRoll.decide` rolls afresh — 2026-11-09 code check; the earlier "draws no
crit" was wrong) and must come to copy the hit's crit as a melee blast's
copies and riding landings already do. #1741's owner line
also fixes an order inside a hit — *"elemental riders first … then other
status(es), then damage(s)"* — which § Landing resolution must keep.

An element status (Heat, Cold, Frostbite, Charge) rides exactly as
Poison rides; it differs only in which count caps it. Catalyst rides too,
budgeted by its own count. Owner, on one rider
map: held, conditional on aspects being 1:1 (*"depends on the status
cardinality maybe"*), which § The two axes settles. There is no third entry:
anything new is a number that lands (payload); where it lands is the node's.

**Which element statuses ride.** Every counted role — terrain stack, Catalyst,
mover — can be a rider row (a goo arrow plants Catalyst, an ice spell plants
Cold on the chokepoint, a hot arrow plants Heat); a state never rides, it has
no count. The quote that settled the rule, owner, 2026-11-04:
*"if fuel is to be a fire status.. and option 2
says `fire:heat` at exactly one then how could a fuel-planting arrow exist? it
couldn't. so i guess that rules out option 2? option 1 sounds reasonable"*.
One cap per element across its whole family.

## The forge: one row type, an open set of uses (owner, 2026-11-04/08)

An intake row is the one `AspectIntake` type (ADR 0060: identity, innate,
int:int rates) plus a **use** that says what its load buys: ADR 0070's
swappable `LoadUse`, an open set. The seam exists: Firecracker's intake row (a
`FuelUse`) already carries a `use` (`attack/spell/load_use/`). Owner, 2026-11-08:
*"spell infusions may also do bespoke stuff instead of simply adding riders,
we are free to design what feels useful and fun to have"*. Two uses carry
the elements so far:

| Row use | Buys | Supply cap |
|---|---|---|
| **ride** (the default) | a rider of the named status: Heat, Cold, Charge, Catalyst, or any aspect status | that status's aspect or element count |
| **shape** (bespoke, per spell) | spell-specific: Firecracker's blast waves, Ice concentrate (§ Ice on a cast) | whichever count it names |

- **No use gives a hit reach.** A shape use may reshape the cast (Ice trades
  hops for seed payload before it leaves), but reach at a landing is read off
  the node alone.
- **A spell carries at most one element, and the forge adds to it or swaps
  it** (owner, 2026-11-09: *"the spell should carry at most one Element
  (fire/cold/lightning) and if a spell already has one, forge can add to it
  (synergy) or replace it for the cast (original cleared, your choice put
  in)"*). So the forge's elemental slot is one element field per cast, not a
  slot count: the same element as the spell's innate one adds load, a
  different one replaces it for the cast. The aspect slots are untouched. The
  owner's own caveat in the same breath: the slot loads Heat, Cold or Charge,
  *"not really things like Fuel"*. Catalyst is not on the element
  axis; it rides as its own row, an aspect (§ The threshold model).
- **An element arrow is its own ammo type, one per element** (owner,
  2026-11-09: *"arrow pools are *per type* given Fuel is now an Aspect called
  Catalyst, we can reintroduce plain fire arrows that simply add heat stacks.
  1:1 fire_element -> fire arrows each reload. possibly more scalers later
  idk. then ranged could add 1 type of elemental arrows with their volley,
  and they can reorder it with the others"*): a fire, a cold and a charge
  arrow beside goo and poison, each a plain arrow whose one rider is its
  element's stacks, minted 1:1 from the count on every reload into its own
  bin and ordered in the volley like any card (ADR 0051). An arrow is an
  aspect subtype *or* an element, never both, so the combination is
  sequencing across arrows, the owner's suggested use: *"launch Catalyst
  shots first, then elemental, causing your e.g. fire arrows to generate a
  lot more Heat which can then be exploited by your next arrows"* —
  *"catalyst + fire would be needed to AoE spread your status arrows,
  catalyst + charge for hops-spreading, catalyst + ice to freeze the target
  and hope one of the many next arrows in the volley crits it"*. **No cap on
  elements per volley** (owner, 2026-11-09, picked over one element per
  volley): fire, cold and charge arrows may share one; Heat × Cold netting
  on the node is the only price of mixing. One type per element is also
  #1765 Q2's answer, one budget per element. A spell keeps its aspect rows
  and, separately, its one element; a blade its addons and an element addon
  (below).
- For arrows and blades the count is supply the way an aspect count is:
  it sets how many element arrows a reload mints (1:1, `AmmoType.per_reload_stat_id`)
  or how much element addon a build affords, and each arrow or vertex carries
  an *authored* innate load. A count-scaled load on every arrow would be the
  per-hit load this doc rejects. There is no int:int rate seam on an ammo type
  or an addon today; whether one is wanted is a spec-time call.
- **A blade's element is an addon per element** (owner, 2026-11-09: *"an
  addon per element"*): Heat, Cold and Charge addons beside Clamp and the
  Catalyst barrel, each vertex carrying an authored innate load, how many a
  build affords budgeted by the element count. The addon grants the rider and
  nothing else — the owner asked *"what stats? e.g. +1 fire_element sounds
  *too strong*"*, and the answer from § The count is supply is none: the count
  is the only element stat and supply never rides an addon.
- **A blade vertex copies its source node's primed state** (owner,
  2026-11-09: *"copy a burning node and you get a burning blade node (booms).
  copy frozen node -> frozen blade node (detrimental so far, makes blade node
  fragile, but maybe we do add a damage increase to even it out?). copy
  shocked node -> get shocked blade node (zaps/arcs)"*): `BladeVertexFill`
  reads the state at fill as it reads stats; a Burning vertex blasts a disc
  where it touches, a Shocked vertex arcs from the node it touches, a Frozen
  vertex is brittle and snaps on first contact. Your terrain travels with
  your blade.
  - **A vertex go-off spends the copy, never the source** (owner,
    2026-11-09: *"so far there is *no* gameplay connection back to the
    source node after a blade node copy is made from it. not starting
    now"*): the fill is a read, the source node keeps its stacks, and the
    excess at fill is the vertex's power. An elemental blade lasts while its
    owner holds primed terrain on their own nodes; that terrain's upkeep and
    shatter risk are its price.
  - **The Frozen vertex's snap is a concentrate** (owner, 2026-11-09, picked
    over no bonus and a flat multiplier): the vertex spends its whole sweep
    on the first node it touches — one contact hit, then the vertex pops.
    The bonus rides the stat pipeline as an overlay on that vertex's
    `blade_damage` read at fill (owner: *"bonus or multiplier riding the
    pipeline (see `overlay`)"*, picked over a multiply at land and a second
    hit), the hook a swing's temp upgrades already use, scaled by the Cold
    excess at fill (owner: *"maybe +10% per excess stack, or +20% or +25%
    (or 5%, it all depends on balance..?)"*). Knob, pass default: +10% per
    excess stack as its own multiplier, no base term — ×1.2 off a leaf at
    stake 0 (excess ≤ 2 at the cap), ×3.4 off a degree-3 node at stake 3
    (excess ≤ 24), so a shallow freeze an enemy lays on a blade's source
    node is still a net loss (a disarm) and a deep freeze the owner holds
    pays. It is one hit, so its crit, the target's armour and the 10% break
    threshold all see the full amount.

  Spec-time (the Fire and Lightning children): what a Burning or Shocked
  vertex's go-off reads and reaches.

## The reach rule (owner's atomics, 2026-11-04)

**A hit landing on a primed node sets it off, and the go-off copies the
hit's payload to every node it reaches at one share** — Burning over a disc,
Shocked to every neighbour; Frozen denies. The owner's atomics (2026-11-04),
each a tiny unit of play the rule must produce, all need the node primed:

1. *"a ranged poison arrow can hit a fueled up, volatile node and have its
   poison payload be applied amongst the blast radius instead of just the one
   node"* — the node is Burning (Heat past T); the arrow is the trigger; the
   disc's power is the excess; any Catalyst the node held was already turned
   into Heat when Heat first landed there (that is how it got Burning so
   fast); the poison lands on the target and a share on the disc.
2. *"take poison spell, craft an AoE effect on it by picking Explosive
   infusion, and watch each hit turn into an AoE hit"* — the infusion plants
   Heat (or is a bespoke shape use, § The forge): early hits warm their
   nodes, and once a node is past T each later hit there blasts, so the AoE
   ramps in rather than arriving with the first hit.
3. *"A Curse arrow hits a Charged (lightning) node and it applies curse to the
   target *and* to 1..N neighbors"* — the node is Shocked (Charge past T);
   the curse arcs to every neighbour, and further hops as the Charge climbs
   the size ladder.

Reach reads the same for an arrow, a blade vertex and a spell hit, since
none carries any. **Planting** (a goo arrow laying Catalyst, an ice spell laying
Cold on a chokepoint — the player control #1716 asks for) is a ride row like
any rider, and a planting hit is a hit: on a primed node it sets it off like
any other.

**Chains** need no rule of their own: a copy landing on a primed node is a
hit there, once per node per *hit* — per arrow, per spell wave, as
`HitLanding.detonated` is today. Every link carries the root hit's payload
flat — `damage × s`, riders `ceil(r × s)`, never `s^k` (owner, 2026-11-05,
#1735 fork 1: *"I am tempted to say: LET IT RIDE. The hit, all rider, no
decay. Maybe raise you: for charge arcs hitting charged nodes also just keep
arcing (and consuming a stack ofc) and concatenating hits."*). That is how it
is built (#1735's finding), so #1735 closes with a doc line.

**A go-off with no parent hit** is a **terrain hit** (owner, 2026-11-05:
*"option 1"*): its copies carry only the blast's own damage (∝ power), no
riders, no crit, side-blind. Nothing triggers one yet: a generator keystone's
minting is not a hit (owner, 2026-11-09: *"just adding those isn't a hit so
also triggers no go-off"*), so the terrain hit is a defined shape with no
caller until something earns it.
**The attacker is the sided party in the reaction**: the Heat's latest
applier (a `NodeStatus` already records `applier_id`). No new fact lands on
side-less terrain. **Sync by determinism**: a terrain cascade has no crit and
no pick, so every peer reproduces it as it reproduces diffusion today, never
a host-minted record (owner, 2026-11-05: *"no crit on unallocated nodes doing
things. but even if they did, we shouldve found a way to sync the seed
(perhap during turnmanager ticks) such that it is deterministic anyway"*).

**A copy carries everything**, terrain riders included (owner, 2026-11-05:
*"stuff that mutates the terrain (by adding fuel or charge or cold) i think
should be able to be proliferated just fine, throw 5 Cold on a Fueled up
volatile target node and watch it apply Cold to its surroundings in an AoE
blast"*); a Cold arrow onto a Shocked node lays Cold along the arcs. A Charge
rider on an arc copy replants `ceil(r × s) ≥ 1` Charge on every node the arc
reaches while the go-off spent its own, a wire that re-lays itself; shown
that loop, the owner kept it (2026-11-05: *"Leaning 2. My reasoning: if
buildup is too strong we can always tune up decay rates/mechanisms"*). So the
spend, the k × T cap and decay are the bounds: **no terrain stack ships
without a decay**, and its rate is the knob that tunes buildup. Rejected: a
copy carrying every rider except the stack its go-off spent.

**A copy lands raw.** `ceil(r × s)` of the hit's payload *as cast* — after a
cast-time shape (an Ice concentrate) put its mass on the seed, before any
per-landing fold — so `stacks_per_hit` never multiplies with reach (#1733
R2). A hit's copies take the hit's own target mask (the shipped bolt filters
to hostile); only a terrain hit is side-blind, so terrain is side-less but a
landing's copies are not. A copy carries its parent's crit (§ The hit).

**A go-off picks its nodes by shape alone, at every level** (owner,
2026-11-10: *"option 1"*, then *"so far just keep it shape blind always"*):
Burning's disc takes every node inside it and a Shocked arc every node within
its L hops, allocated or not, whoever holds them; the hit's mask then decides
who the copies hurt. So an arc's transferred Charge (§ Order) lands on empty
ground too, and a wire can be laid across it. Kept as a backup, not built
(same answer: *"if we so want later we can define it like "allocated only at
lv1, whole graph at lv 2+" for both fire and lightning, could make
interesting gameplay"*): if it is ever wanted it is one rule for Fire and
Lightning together, never Lightning alone.

**Damage type: none.** Elements change reach (through the terrain they lay),
aspects change payload, damage stays one number. Movers get
`<mover>_resistance` as any status does. If a fourth type ever earns its
place it is one word, "elemental" (owner, 2026-11-04: *"if it gets one, its
just 'elemental' (opposing physical or magic or true)"*).

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
| Lightning | lengthens the walk by whole hops |
| Ice | shortens the walk and pays the seed (§ Ice on a cast) |

Owner on this table: *"that's exactly what i'd been trying to convey all this
time"*. A spell authors a default for each (or none) and the forge lets the
caster replace or add to either, beside the aspect slots. Only the direction
is settled; the build is its own design issue, and until it lands an element
on a cast is a ride only. Open there: whether the forge's one element field
(§ The forge) becomes two, a shape field and a ride field; whether one count
feeding both is split between them or read by both; what one point buys for
Fire and Lightning (the three shapes cost the same point, so they should be
worth about the same, which is also what prices the Ice bonus); and whether
a Lightning shape adding hops stands beside the ruling that `max_hops` takes
no stat scaling (`docs/domain/spell-propagation.md`).

## Ice on a cast: concentrate (owner, 2026-11-04/05/08/10)

Burning and Shocked add copies at a landing. Ice concentrate does the
opposite **at cast time**: an Ice load rewrites the spell's own hops down and
pays the seed payload up (owner, 2026-11-08: *"ice concentration should i
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
spends the row's load as a hop cut and writes a seed multiplier; the resolver
reads both once. A variant that cuts `max_visits` is a second subclass, built
when a spell needs it. A spell with nothing to cut (0 hops, or unbounded
hops) authors no gain on its Ice row and so refuses Ice.

**The price leans flat, +50% of the seed per hop removed, and is not
settled** (owner, 2026-11-10, later the same day: *"a +50% per hop lost is
decent, but very rough. might need +100% in some cases, or +25% in others..
like not sure but i think this is gonna bite us"*; the lean itself:
*"L is (very) roughly quadratic, but we dont want to cncentrate ALL that,
there's benefit to having things concentrated at all, even if it'd be, say,
a.. +50% boost for each hop removed. e.g. from 6->3 hops = -3 = +150%
damage"*). Seed × (1 + bonus × hops removed), the bonus one exported knob on
the use, default 0.5: Pestilence 6 → 3 lands its seed at ×2.5, 6 → 0 at ×4.
The walk it gives up is worth far more than that (the table below), and that
is the point: focus is the purchase, not a refund of the area. Rejected: the
seed multiplied by the measured landings it gave up (L(H) / L(h), ~84× for
Pestilence at 0 hops), and the conserving form 1 + L(H) − L(h); no spell
authors a hop ladder.

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

**A concentrated seed on a primed node is a combo**, not an exploit to rule
out. The seed lands with its concentrated payload and a Burning or Shocked
node copies it at share like any payload (owner, 2026-11-05: *"hitting
Charged/Fueled nodes with ice load just proliferates whatever the ice would do
but on the defender's side (incoming hit proliferates via hops or AoE boom)
instead of on the attacker's side … and ice + fuel sounds like a combo why
not?"*). The per-hop bonus bounds it: Pestilence concentrated from 6 hops to
0 carries ×4 a landing's payload, and a 0.5 share of that is twice a plain
landing on every disc node.

## Landing resolution (owner, 2026-11-05)

**Two stages per hit** (owner, 2026-11-09: *"resolve elements first which
settles the reach [as in, total set of targets] for the hit (including
cascades..?) and then resolve the remainder of the hit for each target
(riders, damage?)"*, confirmed as the two stages below; ADR 0082). The
2026-11-05 three phases (*"hold it"*) survive inside stage one, at each node;
the shipped order inside a landing stands — riders before their hit (ADR
0067) and the owner's #1741 order, element riders, then other statuses, then
damage — so a Curse arrow still lifts its own hit. Every read is a pure
function of one snapshot (#1733 R4); nothing reacts mid-land.

1. **Terrain: elements land, the reach is gathered.** At the node the hit
   lands on: *read* its primed states as they were before this hit — they
   are the reach, and the Frozen check is here, against the hit's own crit
   and damage facts; *land* the element riders (Catalyst converting as they
   add); *settle* — the Heat × Cold netting, the power read post-land, the
   go-offs the read found spend their stacks and name the nodes they reach.
   Each reached node runs the same three steps on the copy's element riders
   under the once-per-node-per-hit cap (per arrow, per blade contact, per
   arrival of a wave), a Frozen node
   absorbing an under-threshold copy whole; dual reaches concatenate (below).
   The result is the hit's whole target set with a share per entry — the
   attack record's blast table, one mark and its copies — before anything
   else lands.
2. **Payload: the remainder lands per target.** For every gathered entry the
   other status riders, then the damage, land at that entry's share (a
   concatenated node takes one landing per entry). Nothing in this stage
   touches a terrain stack, so an aspect rider can never change reach.

A hit carrying +1 Heat onto a 5-Cold node is read against 5, lands, and
leaves 4: it thaws for the *next* hit, never for itself; a Cold *copy* onto a
Frozen node lands nothing, so only a direct Cold hit deepens a freeze. The
same terrain settle runs after every world-turn tick.

**Build shape (2026-11-09).** Stage one runs when the hit *lands*, not where
landings are compiled: ranged and blade compile every landing before the
first one lands, and only the applier mutates the world (ADR 0079), so a
compile-time resolver would need a ledger mirroring terrain. A gather owns
the once-per-node set and the entry list; a gather hit at the head of the
span is the only thing that touches terrain, and it records its terrain
changes for peers to replay (ADR 0077). Stage two has no class: the existing
compile-and-land path runs per entry. An element answers two questions and
nothing else — *admits* (does an arriving copy land here: Ice) and *go off*
(what is spent, which nodes are reached, at what share: Fire, Lightning).
The owner picked one owner for the gather with an element callback
(*"option 1 looks squeaky clean. possible advisor on top to confirm"*); the
land-time correction is that independent review's, taken as the direction.
**The gather's unit is one hit** (owner: *"landing arrow = 1 hit (+optional
reach etc) / landing blade contact = 1 hit / 1 spell WAVE = 1..N hits.. these
do NOT compare to the above … imho each branch of a spell may get varied
payloads if spell so wants to author that"*): a wave is N gathers, never one
summed payload.

**The resolver's five build calls (owner, 2026-11-09, night; each picked
from scored options).**

- **A spell's crit is per arrival, decided at the head of its gather**
  (owner: *"option 1. does it then also do the CritCondition?"* — yes). The
  spell's crit conditions and the stat roll are both evaluated there, once,
  against the node as it was before this hit: a condition reading terrain
  (Thermal shock) would read stale terrain if stamped at compile, as
  `SpellDef.crit_conditions` are today. Every copy and shrapnel points at the
  head through the existing `paired` link and copies its crit; a copy never
  re-evaluates a condition, so only a direct arrival crits by Thermal shock.
- **Each hit owns its once-per-node set; hits of one beat settle terrain
  from one snapshot** (owner: *"option 1. and can we make it order
  independent somehow?"*, then picked *one snapshot per beat*). All hits
  landing on the same beat (one wave's arrivals) read the same pre-beat
  terrain; their element riders land as sums; the go-offs that read found
  are computed from it and their spends committed together, summed and
  clamped at 0; the nodes reached form the next generation, settled the same
  way. The result never depends on the walk's order, and the routine is the
  one the world-turn tick needs, whose go-offs have no order at all. The
  per-wave `detonated` scope goes. Known consequence: several same-beat
  go-offs each read a deep store at full power before the clamp. **A blade
  follows the same rule** (owner, 2026-11-10, picked *one snapshot* over
  *sequential, as today*): two contacts of one sample on one node are hits of
  one beat, both read the pre-beat store and their spends are summed, so the
  swing keeps no spend ledger; contacts of different samples read the world,
  which already carries the earlier spend.
- **One share scales the whole payload** — damage and every rider's stacks,
  rounded up per rider (§ The reach rule's *"at one share"*, taken as
  settled by the pass). Today's stacks-only splash scale and the separate
  shrapnel fraction collapse into one knob per go-off, default 0.5.
- **Today's explosive detonation is ported first, as go-off zero** (owner:
  *"optoin 1. and for Charge / Shocked: an ArcEffect? or howzat? or shared
  base class between these?"*). The resolver lands with detonation re-hosted
  on the go-off contract, proving it on the shipped tests and deleting both
  spend ledgers; the game keeps its blast until Burning inherits it. The
  contract is one small `GoOff` resource on the `Element` def (owner,
  2026-11-09: *"i think it should sit on Element def, going off is just
  about their thing"*): a disc subclass (go-off zero, then Burning
  unchanged with another power source) and an edge subclass (Shocked);
  `DetonateEffect` and `BlastEffect` dissolve into the gather plus the disc
  subclass, and no `ArcEffect` exists. Ice's *admits* sits beside it, on
  the `Element` def too. Explosive is not an element, so go-off zero's disc
  rides the Explosive `Aspect` def under the same field name until the
  Catalyst retag deletes it (pass pick, tentative).
- **The applier drains an open worklist** (owner picked it over the head
  landing its own copies). Landing a gather head appends its entries' hits
  to the applier's queue, compiled through one stamping callable the landing
  site hands in (replacing the spell and ranged post-compile stamps); the
  three status, detonate and paired-damage stampers fold into one.

**Two clocks, two sync shapes (pass write-back, 2026-11-09, of the owner's
2026-11-05 call; stated to the owner, not objected to; ADR 0081 records
it).** The attack record (ADR 0077) carries what a *command's*
resolution did, the go-offs its hits trigger included — the record's blast
table (one mark, many copies) is already that shape. The world turn carries
what *time* did — decay, diffusion, a no-parent go-off, Burning's burn — and
every peer reproduces it from the end-turn command, as the damage-over-time
ticks already land HP on the world turn today with no record (ADR 0055's
`_end_world_turn` runs inside `end_turn`). ADR 0079's "mutated only by
`OutcomeApplier`" is scoped to attack resolution and never claimed the world
turn. The constraint that makes this safe: the settle is roll-free (the
temperature step is the integer Laplacian, `floor((t_i − t_j) /
(max(d_i, d_j) + 1))`) and obeys the transcendental ban. The sync model's
"the obligation reaches exactly one subsystem: the stat pipeline" is stale
already and widens to the stat pipeline plus the world-turn settle.

**Dual reach** resolves by the read phase alone: every primed state present
at read fires, each spending its own stacks, so a node both Burning and
Shocked blasts and arcs. Each gathers its own target list and the lists are
**concatenated, not deduplicated**: a node inside the disc that an arc also
reaches takes one copy per reach. Owner, 2026-11-05: *"the double counting
might be a feature! tentative option 2, where union is kept as an easily
switched to option if we change our minds. after all it's just a "do you
dedupe the list or not" after gathering each reach medium's additional
targets"*. Tentative: the dedupe is one switch at the gather step, so the
build keeps it as a knob rather than a structure. A node gathered by two
reaches is two entries, each landing every rider and the damage (owner,
2026-11-10: *"riders twice, payload twice. charged burning nodes sounds like
a dangerous concept"*), but if that node is itself primed its own go-off
fires **once per hit**, not once per entry (owner, 2026-11-10, picked *once
per hit*): the once-per-node set bounds every cascade by node count.

## The reach triad (pass proposal, 2026-11-04; owner asked for the shape)

Owner, 2026-11-04: *"1. Melee - STR - AoE - explosive (fuel = AoE) - fire …
2. Ranged - DEX - single target - … - …ice? … 3. Magic - INT - edge hops based
propagation (like 90% of the time) - lightning. Make sense? Canonicalize this
somehow? What shape is this here exactly?"*; later: *"the vibes are: fire -
AoE spread - euclidean - melee; lightning - edge-hop spread - edge-hops-based
- magic; ice - single-target - pinpoint / 0-D - ranged"*.

The shape: **each element is one attack mode's native reach, made terrain.**
There are three reaches a hit can have on a graph — a disc, a path, a point —
and each attack mode is born with one. An element lays its reach on the
board, where any mode's hit sets it off (Fire, Lightning) or is stopped by it
(Ice).

| Mode | School | Native reach | Element | What its primed terrain does to a hit |
|---|---|---|---|---|
| Melee | STR | **disc** — a blade sweeps a hurtbox | Fire | Burning copies it over a disc |
| Ranged | DEX | **point** — a target is 0-dimensional | Ice | Frozen denies its reach and ends its path; a blade vertex on it snaps (§ The threshold model), so melee meets Ice in the counters; on a cast, concentrate (§ Ice on a cast) |
| Magic | INT | **path** — projectiles are graph automata over edges | Lightning | Shocked copies it to every neighbour and conducts a spell walk |

Ice reads as ranged's nature turned into terrain: the kiter's gift is
denial, freezing the chokepoint so the sweeper and the hop-caster cannot
reach back. It is the counter-element, anti-reach; the other two are reach.

This is a **school assignment**, the same thread every aspect already has
(Poison under DEX, Greed under WIS, § Attributes and pairs in
[aspect_matrix.md](aspect_matrix.md)), and it carries the same rule: a school
**never scales** what it houses (ADR 0059; owner 2026-09-28). The triad couples
by geography, colour, persona and which inner-tree sector holds the element —
never by a fold. Two orthogonal threads then spread the content out: aspects
hang off all six attributes, elements off the three attack schools. Owner,
2026-11-04: *"It really shapes up the game content to be somewhat.. spread
out, instead of a burning focus on just 1 group of features. which is a
feature on it's own"*.

## Pair rules (from the threshold model and #1444)

Rows are what rests on the node, columns what arrives; a blank cell means
*nothing special*.

| On the node ↓ / arriving → | a hit (a copy and a blade vertex included) | the opposite temperature (rider or flow) | a Frostbite pack |
|---|---|---|---|
| **inert** (count ≤ T) | lands; a blade feels `t` (Cold drags, Heat speeds) | nets | sheds Cold first: the toll (#1444) |
| **Burning** | explodes (§ The threshold model) | nets: Cold cools it, for the next landing | |
| **Shocked** | arcs to every neighbour; a spell walk conducts | | |
| **Frozen** | a direct hit lands; a copy under the break threshold is absorbed whole and the path ends; a breaking copy lands; a blade vertex snaps | nets: Heat thaws it, for the next landing | cold passage: no shed (#1444) |

**Frozen mutes the node's own go-offs; the break releases what it trapped**
(owner, 2026-11-08: *ice wins — frozen solid*, then, after the deeper look it
asked for, *trapped until broken*): a node both Frozen and Shocked neither
receives nor emits — the Charge sits trapped under the ice — and the hit that
breaks the ice sets off the Shocked state in the same settle: crack the ice,
release the storm, plus the shatter burst. Freezing a wire cuts it and stakes
the trapped Charge as a visible bomb. One compound read, never a
re-evaluation: the breaking hit's crit and damage are its own facts, both
states are read pre-hit, and the read says "Frozen mutes Shocked unless this
hit shatters". The released arc's *power* follows the one power rule (§ The
threshold model): it is read after the breaking hit's own riders land, so a
Charge-carrying breaker feeds the storm it releases (owner, 2026-11-10,
picked *after the hit lands* over the trapped Charge exactly as it sat).

**Frozen is a boon with two costs** (owner, 2026-11-05, asked for drawbacks
and kept exactly these): *cold passage* — a Frostbite pack crossing it pays
no shed and Afterdrop turns it into a pack aimed at its owner (#1444) — and
*brittle* — a blade vertex touching it snaps and breaks the ice (§ The
threshold model). The list is open to more small costs of that grain (owner:
*"possibly we find more small things like what Cold passage to add later"*),
and your own spells walk less far through it. Rejected: a Frozen node unable
to launch attacks, and suspending its stat contributions.

## Derived states: Frozen, Burning, Shocked (owner, 2026-11-06)

A state is its terrain stack past T, remembers nothing, and is side-less like
its stack. **Shocked** is #1733 round 3's *critical Charge* (every neighbour
struck) under its name; Burning's landing verb is the blast (§ The threshold
model).

**Modelled as bands on the `Element` def, never as status rows** (owner,
2026-11-09: *"iff these 3 statuses are a special case (or subclass) by virtue
of all being `elemental/reach-y/go-off`-ey, option 1 seems cleanest"* — they
are: a status row is sided, records its applier and clears on death, while a
state is side-less, sits on unowned nodes, survives death and is rewritten by
the diffusion pass on every node at once). An element holds an ordered list
of bands; a band is a threshold as a multiple of T (1, k, …), an `Identity`
for the name and look, and what the band answers (*go off*, *admits*, travel
verb, decay rate, light) — so the `GoOff` sits on its element's band. A
node's state is the highest band its count passes, one pure function of the
int and T; nothing stores it. **A new band is earned only when behaviour
changes in kind**; a change in size is the excess curve (blaze, inferno are
display names on it). Pass picks, tentative: the crossing is announced by
the node — the one write path to a terrain int compares the band before and
after and emits one `terrain_band_changed(element, from, to)`, which the
capacity bar, the glow and vision's light source listen to; no stack, status
or entity knows about bands (terrain is owner-blind; a holder only receives
damage through the ordinary path), and a go-off's moment is the attack
record's blast table, not this signal.

**The travel cell completes the triad** (owner, 2026-11-06: *"picture A
sounds very good. also in some sense: elec - hops -> 1D (lines); fire - discs
-> 2D; cold - point -> 0D. it checks out"*). Each element is one mode's
native reach made terrain, and its state is that reach's verb on travel:

| State | Dimension | Travel verb | Spends |
|---|---|---|---|
| **Frozen** | 0D, a point | a path **ends**: hops, chains and arcs stop here (a Frostbite pack, #1444, is the one exception: cold passage) | nothing |
| **Shocked** | 1D, a line | a path **conducts**: a spell walk entering a Shocked node leaves it without spending a hop — a line of Shocked nodes is a wire for anyone's magic | one Charge per pass-through |
| **Burning** | 2D, a disc | a disc **spreads**: a blast's copy landing on a Burning node sets it off in turn (the trigger) | what a go-off pays (§ The threshold model) |

A leaf (T 2) primes cheaply and a degree-5 hub (T 10) rarely does, so
corridors conduct and chain and hubs do not. Both verbs are side-less: your
own cast conducts through the enemy's wire, your own blast sets off your own
Burning node. Rejected for v1 (offered as picture B): Burning denying
allocation while it burns, Shocked self-discharging on the tick.

**Burning is a light source** (owner, 2026-11-06: *"burning being a light
source does sound clever, could be one of the cells filled by burning"*): a
Burning node is visible through fog to every entity and reveals its
neighbours — a VisionSystem fact, no combat rule. A Shocked "crackle"
revealing charged nodes within its arc reach is parked as minor (owner:
*"likely minor?"*, *"more related to the `sensor_range` system, just not sure
how"*).

**The overflow: past the cap** (owner, 2026-11-06: *"a 2nd "post cap" state
sounds good too … the excess is there but burns off quickly. like over-limit
portion either triggers some collapse / expunge trading it for damage (or
nothing if unallocated) or it spreads out, or gets chunked for bonus damage
next incoming hit … or a mix of all of these, each fitting to the status
effect"*). The cap k × T is **soft**: stacks past it are the overflow, decay
fast (a per-def rate, knob) and are only stacks above a threshold, so a state
still remembers nothing. The owner's ladder (*"ramping up fire der states to
blaze to inferno"*) is Burning's power growing with the excess, so Fire and
Lightning need no overflow verb. Ice keeps one, **deep freeze** (owner:
*"deep-freeze stacks dealing bonus damage on breaking ice and get removed
along with it"*): the shatter spends the overflow with the rest of the excess
(§ The threshold model). "Chunked for the next incoming hit" is lawful only
as the stack itself being the stored amount, as deep freeze is; a separate
charged-up bonus would be a count, not a state.

## Temperature: Heat and Cold are one flow (owner, 2026-11-04/05/08)

Exactly one pair nets: **Heat against Cold**. Owner, 2026-11-05, on whether
the two enter one formula literally: *"option 1, 100%. hell yeah"*. Each
world turn every node has a signed temperature `t = heat − cold`; the
Metropolis rule of #1660 round 2 (`floor((t_i − t_j) / (max(d_i, d_j) + 1))`
per edge, one snapshot, integer dead band) runs on `t`, and the result is
written back as Heat where positive and Cold where negative. A hot node
beside a frozen one exchanges along the edge and cancels on both sides, so
the netting is the diffusion itself; the per-landing `min(heat, cold)` at
settle is the same rule applied to a rider. Both signs rest on unallocated
ground, and the flat decay cools the board (§ The threshold model). Frozen
ends when Cold drops back to T; **Burning** is its mirror — Heat past T, same
T, derived, never saved — and **Burning is what ignites** (owner, 2026-11-05:
*"Burning ignites"*, picked over "any Heat ignites" of #1660 round 2)). A
leaf (T 2) lights at three Heat, a degree-5 hub needs eleven, so hubs are
hard to blow and tips burn bright. The door the owner kept open (*"a bespoke
twist or tweaked T value later for Burn. or extinguish mechanics"*) stays
open.

**An arc moves its Charge, it does not void it** (owner, 2026-11-10: *"knob,
transfer by default"*, reasoning: *"decay is 1 per charged node. if it voids
4, they are gone. if it spreads them to 0 charge nodes, they are gone by next
tick. if more charge is at play, more things can happen, chain effects,
priming mid hit or after, all reads as *very* STATIC DISCHARGE i must
say"*). A Shocked go-off still pays 1 per node reached, but each spent stack
lands on the node it reached (+1 there, in the same commit as the -1 on the
source: the beat's one set of sums, so no timing is added). Where the spent
Charge goes — the reached node, or the void — is one exported choice on
Lightning's edge go-off, transfer by default. It is Lightning's exception to
the one spend law (ADR 0081 §1, whose rejected "radiating transfer" was
weighed for Burning's disc, where it mirrors diffusion; the next element ADR
records the reversal for arcs). Consequence to tune against: an interior node
of a wire gets back what it gives, so decay and the conduct cost are what end
a wire. Pass readings, tentative: the conduct cost of a pass-through is still
voided; a transferred stack is treated exactly like the Charge rider an arc
copy lands (same commit, same primed-ness read); Burning and Frozen keep the
void.

**Charge stays put** (owner, 2026-11-08: *"charge staying put sounds
good"*): static charge. Its travel is the arc it fires when hit, and since
copies carry everything, an arc's Charge rider moves Charge outward. Fire
spreads, Ice creeps (the shared flow), Lightning is placed.

**The world clock.** Diffusion, decay of terrain and the terrain settle run
on the world turn as built (owner, 2026-11-05: *"option 1"*) — today it fires
once every N played turn ends, N = living initiative carriers, reproduced on
every peer. Steps per world turn is an exported knob (pass default 1). The
owner wants the world turn's own rate revisited: *"possibly revise the rate
at which the world clock ticks. like maybe speed it up with the number of
entities (but not linearly? idk)"* — pass knob: a world turn every
`ceil(sqrt(N))` played turn ends instead of every N (2 entities: every 2; 4:
every 2; 9: every 3), tentative, easy to change, and it moves the turnless
hosts and lingering rows that already ride that clock. Rejected: an
initiative clock (a new seam in TurnManager plus a resync row), per-node
staggered clocks (the one-snapshot Metropolis rule needs one snapshot).

**Build note (pass, not an owner call; the owner asked, 2026-11-08).** Decay
needs no tick: a flat decay of 1 per world turn is computable on read (stored
count, minus world turns since it was last written, floored at 0). So Charge, which never flows, costs nothing per world turn (Catalyst is an aspect status row, not node state: it keeps its own decay rule). Only the Heat/Cold
diffusion is a real pass: **one** pass over the signed `t`, over the
temperature index (nodes holding Heat or Cold, the `_lingering` registry's
shape), on packed arrays, never a walk of the graph (the arrays are the
pass's scratch, gathered from the indexed nodes' state and written back; the
index is live-only, since no shadow world runs a world turn). Worst case is a fully
hot 3k-node board at mean degree 3: ~9k integer edge updates once per world
turn, not per frame. A GDExtension only if a profile says so. The native
toolchain already exists (the XPBD solver is C++), so the cost is a C++
implementation that must stay the **only** implementation (never a GDScript
mirror), not a new build.

Everything else coexists. Catalyst and Cold coexist: Catalyst under a Frozen
node is colourless until a hit's element lands; a direct Cold hit deepens the
freeze (a Cold copy is absorbed), a Heat hit thaws harder. Heat never touches a Frostbite
pack (owner, 2026-11-04: *"Heat & Cold don't make sense together. frostBITE
is an ailment"*). Charge has no opposite. Rejected: Catalyst damped by Cold
(terrain fighting terrain with nobody acting).

## Three things wear the word "explosive" (pass clarification, 2026-11-04)

Owner: *"fuel defensive: explode (trigger aoe reach), fuel rider: splodes
(spreads) or plants?? (adds fuel??) or is that Magic making an exception …
i confuse myself"*. No status has an offensive and a defensive face; three
different rows share the old word, on every facet alike:

| | Row | What happens | Plants |
|---|---|---|---|
| "infuse Explosive to make it AoE" | a Heat **ride** row (or a bespoke shape use) | the hit plants Heat; once its node is past T, later hits there blast | Heat |
| "goo arrow" | a Catalyst **ride** row | Catalyst is added to the landing node, inert until a hit's element lands | Catalyst |
| "a catalysed node" | Catalyst on the node (an aspect status) | colourless until a hit carrying one element lands; then its store becomes that element 1:1, same landing | — |

Poison has the second and a third of its own ("poison on a node ticks");
the only novelty is that primed terrain reacts to *landings* where a mover
reacts to a *clock*. There is no Magic exception: an arrow planting Heat
ramps a node exactly as an infused cast does.

## Vocabulary guard (owner, 2026-11-04: *"stay mindful of concepts drifting"*)

Elements share the rider and infusion words with aspects and add terrain
that reaches, so the words are pinned here and in the matrix Glossary:

| Term | Means | Not |
|---|---|---|
| **Payload** | What a hit delivers: damage plus its riders, any status | where it lands |
| **Reach** | Where a hit's copies land, set by the node it lands on: a disc, a path, a point | anything a hit carries |
| **Load** | The amount of an infused thing a cast carries (ADR 0060's word): an aspect or element-status load | a node's stacks |
| **Rider** | Plants a status — any status, terrain and movers included (a goo arrow plants Catalyst) | a reach |
| **Use** | What an intake row's load buys: an open set (ADR 0070's `LoadUse`) — ride, a bespoke shape, cleanse … | a slot |
| **Terrain stack / Mover / State** | The roles in an element's family (table above): Heat, Cold, Charge / Frostbite / Burning, Frozen, Shocked; Catalyst is in no family | "the fire status" |
| **Primed** | A node whose terrain stack is past T (count > T, T = 2 × degree): a hit on it sets it off | a status with stacks of its own |
| **Excess** | count − T on a primed node: Burning's power, what a shatter spends | the overflow |
| **Overflow** | Stacks past the cap k × T: decay fast; deep freeze spends them | wasted |
| **Member** | A status of an element, whatever its role: Heat is a member of Fire, Frostbite of Ice; Catalyst is nobody's member; an Element Matrix row is a member row; a member keys its own facets (`heat_resistance`) (owner, 2026-11-05: *"member"*) | a facet (arrow / blade / spell) or a role |
| **Catalyst** | inert, colourless aspect status (allocated nodes only) that becomes an element 1:1 when a hit carrying it lands or its node primes: the element analogue of Greed | fuel, a family member, a reach, a go-off |
| **Volatile** | a word the owner floated for the states that go off, Burning and Shocked (owner, 2026-11-09: *"`volatile` is a better fit to describe Burning *and* Shocked"*) — not Frozen, which denies | a status |
| **Fire / Heat / Burning** | The element (its count) / its terrain stack / Heat past T | three names for one thing |

## Acquisition (owner, 2026-11-09)

**v1 sources are the aspect sources.** An element count *"is the same
sentence an aspect count already says"* (§ The count is supply), so it takes
the sources an aspect count has: a pool roll in its school's pool (Fire in
STR's, Ice in DEX's, Lightning in INT's — the reach triad; today
`procgen/pools/dexterity.tres` rolls `explosive_aspect` the same way), the
inner tree, found and stolen modifiers. **Starter count: 1 in every element
for now, 3 each for the dev sandbox's Player** (owner, 2026-11-09: *"1 in
each for now, 3 each for the dev_sandbox's Player (for instant testing)"*), a
knob. **Catalyst starts at 1 as well, 3 for the dev sandbox's Player**
(owner, 2026-11-09, picked over found-only and a ranged-only grant), the
same interim rule — *"catalyst might be Ranged's most important aspect,
almost as if it's their "clamp"?"* — so a reload mints one goo arrow from
turn one. The direction after that, owner's words: *"later i think all should
start at 0 and gains be linked to "core skilltree / inner skilltree" or core
class, or some starting modifier passed from metagame, and still some found
on the board (e.g. a bespoke skillnode inherited scene [== a Keystone] such as
one that gives "+1 Fire | but also generates 2 Heat / turn"), that kinda
content"*. `apex_inner_tree.md` is six schools × two aspects today; elements
would be a third ring or a three-spoke tree — filed against the hub.

**Generator keystones** (owner, 2026-11-09; filed as their own issue, not in
the first build): one per element, *"virtually identical in setup (analogous
fire/ice/lightning generator keystones). like they all mint e.g. +2 {element}
stacks each world tick, these also spread, and just adding those isn't a hit
so also triggers no go-off."* Heat and Cold spread by the shared flow; Charge
*"piles up, to some extent. maybe to 4T (4 × the critical threshold such that
it arcs for 2 hops …)"* — a standing Shocked trap on the keystone's node,
Charge still staying put. Minting is not a hit, so no go-off and no terrain
hit; the keystone grants its element while held.

## Open

- **Catalyst, settled and what remains** (owner, 2026-11-09). Settled in § The
  threshold model: Catalyst is one element-generic converter in no family, the
  world-tick fuse is dropped (it converts at landing, so no node holds it
  at a go-off). The rejected alternative, in the owner's words: *"either this, OR
  we add an "inert fuel-like buildup" status for Ice and Lightning too so each
  has one of them. but i think that'd just be a less comprehensible, more
  tedious and less fluent way to go about this and that getting just 1
    catalyzing status for all elements would work better."*
  - **Settled 2026-11-09 (owner quotes in § The threshold model):** supply
    is an aspect (the Explosive aspect retagged, DEX), colouring is hits plus
    priming, the trade is the whole store at 1:1 with no slice. These
    supersede ADR 0072 §3 (*"Fire is wholly an element. Fuel is Fire's
    medium; no Explosive aspect survives"*) in part and ADR 0075 §6 (Fuel the
    accelerant); ADR 0081 records it. Master artifacts to RETAG
    (explosive to catalyst), none deleted: `stats_system/defs/explosive_aspect.tres`,
    `effects/status/explosive.tres` (with its `charge` tag),
    `aspects/defs/explosive.tres`, `attack/ammo/types/explosive.tres`, the
    barrel addon `skill_node/addons/defs/explosive_barrel_addon.tscn`, the
    ring slot in `entity/ring/aspect_ring.tscn`, the `explosive_aspect` roll
    in `procgen/pools/dexterity.tres`.
  - **NOTE, fate at spec time:** `DetonateUse`/`DetonateEffect`, blade
    `vertex_charges`/`BladeVertexFill` and Firecracker's intake row with a
    `FuelUse`.
  - **For Greed's spec:** Greed must not multiply element stacks (owner's
    lean, quoted in § The threshold model).
  - Knobs: ratio 1:1, Catalyst cap k × T, Catalyst decay slow.
- **v1 spell content** (owner, 2026-11-09): `lightning_bolt` carries Charge
  (renamed, not reshaped, a Charge ride row as its innate element), and **a
  new single-target Cold spell** — *"one single target ice spell that is only
  single target (0 hops) because of its ice element load. and replacing that
  load with another element restores some hops and drastically alters the
  spell"*: its innate Ice row is the concentrate (§ Ice on a cast) eating its
  hops to 0; swap the element at the forge (ADR 0081 §7) and the hops come
  back. **Its signature is a crit condition, Thermal shock** (owner,
  2026-11-09, picked from four candidates; the ask: *"it should have some
  bonus effect that would be cool to port onto a fire/lightning setup (by
  tossing the ice load and putting fire or lightning in at the Forge). or
  has a clever crit condition. crit conditions are now even stronger and
  more important to get right: they shatter Frozen!"*): the hit crits when
  the target's terrain holds a different element than the cast carries, read
  pre-hit like every check. The Ice form quenches a Burning or Shocked node;
  with Fire in, the restored hops walk a chain that crits — and so shatters
  — every Frozen node on it, so one spell freezes the field and, after a
  forge swap, breaks it. The condition earns its keep in the ported form:
  eating 4 authored hops to 0 is worth about 24 landings on the seed
  (§ Ice on a cast's table), so the Ice form likely clears the 10% break
  threshold on damage alone, while a restored chain at base payload breaks
  ice only by its crit. "Holds a different element" reads the primed state
  (Burning, Shocked, Frozen) — the pass's reading, unconfirmed: stray stacks
  under T would make it near-always on. The spell is filed as #1789 (Needs design), which
  carries that reading and the authored hop count. Nothing else carries an innate element in v1.
- **Whip-crack, a Fire spell's crit condition** (a pass candidate for the
  Cold spell, parked by the owner for Fire, 2026-11-09: *"whip crack sounds
  like a fun fire-type spell like a fireworks -- hop hop hop (outwards) then
  *explode*"*): the hit crits on the landing where the walk ends, so only
  the chain's tips crit and their go-off copies carry it (ADR 0082 §4). Not
  v1; Firecracker is the existing fireworks spell and one candidate home.
- **A wire evens itself out** (pass idea, parked, not picked): a connected
  run of Shocked nodes shares its Charge each world turn — the one flow
  Charge could have beside staying put.
- **Arc mirror** (owner idea, 2026-11-05, parked): *"maybe when a nb tries to
  emit a lightning reach it reflects it? maybe not"*. Shocked arcs to every
  neighbour, so a Frozen neighbour is always struck; whether that arc grounds
  or bounces back onto its emitter is for Lightning's spec. A blanket reflect
  was rejected (owner, 2026-11-05: *"reflect: too powerful, esp being as
  cheap as 2 Cold on a leaf node"*).
- **Ranged's access to Catalyst and element arrows: an Element Matrix** (owner, 2026-11-04:
  *"option 1 sounds good"*), one row per family status, columns `Ammo :
  Addon : Spell : Infusion`, so the Explosive addon becomes the Catalyst
  addon cell. Still open on it: **availability** — a found addon is not
  Clamp-like (owner: *"god i hope i find an explosive addon anywhere in the
  nearest 20 hops from where i spawned"*; the fuel-arrow count *"need to get
  into 10s ASAP"*, and late-game ranged fires hundreds of arrows), so the
  Catalyst ammo cell wants a steady source (a reload grant from the count is one)
  and **a stock cap per element ammo type** (owner: *"storing 1000 heat arrows
  sounds like bad juju"*) — the `Quiver` already caps per type
  (`AmmoType.max_stock`, 999 default), so each element ammo type sets its
  own lower cap; nothing targets it, so it is a knob. Owner, 2026-11-05,
  reframing the whole question as **parity with Clamp**: *"Melee's ease of
  use of applying a temp Clamp addon (their bread & butter) is matched by
  Ranged getting some <fuel arrows> one way or another, in a similarly
  easily obtainable fashion … can we somehow arrange something like this for
  ranged?"* — tracked as #1765 (the access shape, one budget per element
  across its ammo types vs each type minting the count, the stock cap).
  **Settled 2026-11-09:** one ammo type per element answers the budget
  question (§ The forge). **The access shape is an owner call (2026-11-09,
  picked over a temp quiver addon and a starter element ammo type): the
  count is the access** — every reload mints `fire_element` fire arrows into their
  own bin, no action, nothing to find or buy (routes through
  `AmmoType.per_reload_stat_id`; the starter grant is count 1); the rejected
  alternatives: a temp quiver addon bought with a ranged resource that does
  not exist yet; a starter type with a fixed grant, two sources of one
  supply. Catalyst is an aspect, so goo arrows are budgeted by its count
  exactly as poison arrows are, and its starter count of 1 (§ Acquisition)
  answers the Clamp-parity ask from turn one. Element bins sit beside the
  plain pool, not inside its capacity, so a count adds arrows.
  **Stock cap arithmetic (pass):** the count mints that many
  element arrows per reload (1 at fire 1, 100 at fire 100), so a flat cap
  serves one end only — 50 halves a late archer's every reload, 999 is the
  hoard — the knob is a multiplier on the type's own per-reload mint, pass
  default 2 (a quiver banks one spare reload), easy to change.
- **Adversarial review, 2026-11-05** (full list in `docs/handoffs/elements.md`),
  items (a), (b) and (h) settled 2026-11-09.
  (a) **Row keys**: a row names the status it plants (owner, #1660,
  2026-10-18: *"B2: agreed"*), defaulting to its concept's only status. The
  forge budget stays keyed by concept (the one `ice_element` count budgets both
  rows) and everything else walks the rows instead of looking up a concept's
  first row — pass pick; a shape row plants no status to key on.
  (b) **The count's role**: one role for "this concept's count" —
  `StatDef.Role.ASPECT` is renamed `COUNT`, so `poison_aspect` and
  `fire_element` are the same facet of their concept and the forge budget and
  the quiver mint branch on nothing (pass pick; nothing enumerates stats by
  role). `Identity.Kind.ELEMENT` is added (owner: *"yes Kind.ELEMENT is
  surely needed"*) and stays presentation-only: every reader of `Kind` is UI.
  Facet ids key per status (#1660 A1), so a member keys on itself (`heat_`,
  `cold_`). An element is authored as its own `Element` def beside `Aspect`
  (owner: *"Elements as a class might be better for now, duck typing is also
  still a thing, and we never enumerate the whole list i think"*). A shared
  base (*"Concept with the addon/arrow/name whatever, Aspect and Element as
  children that diverge but share the same roots? hmmm"*) is not taken now;
  the shared fields keep `Aspect`'s names so it can be extracted later.
  (h) **Rider coalescing**: one summed entry per status id per landing entry;
  resistance and Greed fold once per id; a copy is its own entry, so a hit's
  rider never merges with a copy's.
  Still open: (f) **Charge** collides
  with explosive's `charge` tag and `vertex_charges` — the #1716 r2 retag (to `catalyst`, the Explosive aspect's retag) must be in the first Fire issue.
- **Knobs** (§ The threshold model): T = 2 × degree, k, the hop ladder's
  L² × T, the disc's √power × node diameter, the decay rates — tuned with
  #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- **Spike pop docs vs code**: owner, 2026-11-08, *"The existing one just pops
  the one, docs may be stale"* — `BladePopResolver`'s header describes severing past a pop while
  the code pops the one vertex and only records a `Severance` for what the
  pop left unreachable; settle header against code at the Ice spec.
