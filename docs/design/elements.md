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
Poison status, never a second one. No Explosive aspect survives: Fuel is
Fire's accelerant (the ranged-access question this raises is in § Open).

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
over them (and heat stacks... should speed them up a lil?)"*). Past T the node
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
| **Frozen** | denies: arriving reach stops here, a path ends (0D) | a blade snaps on it (below) |

**What a go-off pays: open, per element.** Every trigger spends stacks from
its own node; how many is the open call. Owner, 2026-11-08: *"Maybe.. spend
½T stacks instead of 1? Or some multiple of *degree*?"*; then, of a degree-4
node (T 8) at 9 Charge: *"would zap all nbs at cost of 1? or 4? 4 being ½T.
would decharge more rapidly"*; and of Fire: *"9 heat / 1 burning it would
feel a bit off if we were to hand off heat to any node like that (charge is
more travel-across-edges-ey)"*. The two shapes: **1 per trigger** (#1733 round 3:
*"consuming 1 at a time"*; excess E fires E times, the owner's volley: *"if
you land F+1 hits on it it would explode for size(F), size(F-1), …,
size(1)"*) or **½T = degree per
trigger**, one per neighbour struck (a node full to the bare-ground cap 3T
holds excess 2T = 4 × degree, so it fires 4 times whatever its degree). Lean:
Shocked pays per neighbour (it travels edges), Burning pays 1 per blast.
Whether a spend may take the node below T rides the same call (owner: *"it
spends then however much we design it to, 1 (arriving AT `T`) or more"*). The
spend destroys stacks and hands none to the reached nodes; only the
triggering hit's riders ride the copies. **Copies carry everything**, element
stacks included, chained links flat (owner, 2026-11-08: *"everything rides
yeah, LET IT RIDE! can change that later if it becomes too much"*); the spend,
the cap and decay are the brakes.

**Size.** Burning's disc is Euclidean, radius ≈ √power × node radius, power
= the excess (owner, 2026-11-08: *"size(N) ≈ sqrt(N)×node_radius so chances
are power 1 doesn't hit any node, but that's tuning"*). Shocked's hops: level
L at count > L² × T (owner: *"T = 1 hop, 4T = 2 hops, 9T = 3 hops"*). Knobs.

**Fuel is an accelerant.** Owner: *"Fuel would only be a supportive sticky
"pre fire but would burn as such" goo … if any fire-related combustion
occurs, consume all fuel stacks too add them to the explosive power, and
leave residual heat."* Fuel never counts toward T (owner, 2026-11-08: *"fuel indeed doesnt count
towards burning"*); when its node
explodes all of it is spent, added to the power, and burns into **N = 2 Heat
per Fuel on its own node** (owner pick, 2026-11-08, over +1 Heat on every
node the disc touched, which makes Heat from nothing); flow spreads it. Heat
is spent per go-off and Fuel whole, so Heat arrows sustain and Fuel-then-Heat
bursts: two volley shapes. A Burning node holding Fuel also goes off on the
world tick (owner, 2026-11-08: *"burning holding fuel explodes"*; keeps
#1660's fuse).

**A blade on Frozen: a fragile snap.** Owner, 2026-11-08: *"if a melee blade
node has Frozen on it, if should shatter on first contact. Reduces reach
right? Any blade node popped is less sweep. And if frozen node is hit by
blade node, it.. shatters the ice … but *also* shatters the offending blade
node!"*, then *"We want to pop just the two vtx. Not too dramatic, and
remember Ice is 0D. Point like. Single target. So no splash or anything just
a fragile snap"*. First contact pops that one vertex (the spike pop, no drain
check, nothing severed) and breaks the ice; pass: the ice spends everything
above T, overflow included, into single-target damage to the frozen node's
holder; the shape is open (owner, 2026-11-08: *"idk how it uses the excess as
damage, flat increase or % or × idk yet. or differs per hit?"*).

**Cooling.** Heat is terrain, so it rests on unallocated ground as Cold does;
every warm or cold node decays 1 toward zero per world turn (owner: *"if we
make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it
should eventually cool off"*), Charge likewise, Fuel slowly — knobs. The
Metropolis step is the discrete graph-Laplacian step; its integer floor is a
dead band, and the decay clears it. Every warm node loses one, so spread heat
cools faster than a lump: no board-wide budget is needed.

**Reading it: a capacity bar on hover** (owner idea, 2026-11-08: *"neat UIs
of "element capacity" in blocks e.g. when hovering nodes. Hover leaf node and
see N*degree empty blocks for heat/cold and maybe sparkles inside for
counting blips of Charge (same threshold? Tho excess.. can make this
messy)"*). Pass proposal: **one block = degree stacks** (one go-off's cost, if the spend is per
neighbour).
With T = 2 × degree every node's bar then has the same shape: 2 inert blocks,
then 2(k − 1) primed blocks to the cap (4 on bare ground, +2 per stake), and
each lit block reads "one more blast left". On a leaf a block is one stack, so
the blips count exactly; on a hub a block fills in fractions. Heat and Cold
share one bar, filling red or blue, since they net and a node holds only one
sign; Charge gets a second bar of the same shape with sparkles; Fuel, which
never counts toward T, is a goo layer under the temperature bar. The overflow
is a few blocks past the frame that flicker and fade, so the fast decay is
visible and the bar never grows unbounded. Same thresholds for all three, so
the messiness the owner flagged stays in the overflow tail.

## One count, a family of statuses with fixed roles (owner, 2026-11-04/08)

An element is one count on the entity and a short family of statuses on
nodes. Nobody points at "the" fire status; the **roles** are what you point
at (owner, 2026-11-04: *"that table looks very good, should be persisted"*).

| Element | Count (entity) | Terrain stack — side-less, inert up to T | Beside it | Primed state — past T, derived |
|---|---|---|---|---|
| Fire | `fire` | **Heat** | **Fuel**, the accelerant: never counts toward T, spent whole when its node explodes | **Burning** |
| Ice | `ice` | **Cold** (owner, 2026-11-05: *"Cold i think. Frozen is a different effect, derived by Cold count (and degree) … frost sounds too "already being a DoT""*) | **Frostbite**, the mover: #1444's inward pack, sided, hurts | **Frozen** |
| Lightning | `lightning` | **Charge** | none in v1 (owner, 2026-11-04: *"Fun but maybe start with just the 1"*) | **Shocked**, #1733 round 3's *critical Charge* under its name |

- **The count never ticks on anyone.** A mover is an ordinary sided status
  that clears with its owner like Poison does; terrain hurts only through its
  primed state (a blast, Burning's burn).
- **Terrain is side-less.** A terrain stack, and Fuel, rests on a node
  regardless of owner, survives kills, retakes and deallocs, and leaves by
  being *spent* (a go-off spends its own node's stacks), by decay (per-def,
  ADR 0048; § The threshold model's cooling) or by a cleanse. Heat and Cold
  flow as one signed `t` (§ Temperature) and rest on unallocated ground; Fuel
  and Charge stay put. Owner, 2026-11-05, on a capped wall beside bare
  neighbours: *"something doesn't quite feel right of a 100 Cold node with
  neighbors of 0 Cold … just sits there as if perfectly isolated"*, then
  *"option 1!"* (flow): a wall sheds a fringe around it, #1444's channels for
  free. The readability test: *if nobody owned this node, would it still make
  sense for this to be here?* Fuel on an empty node, yes; Poison on an empty
  node, no. Build note: today's `on_dealloc` has CLEAR and LINGER and a death
  clears both; terrain needs a shape that survives death too — a seam for
  spec time.
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
  states). Owner, 2026-11-05, asked whether a 100-Cold wall should be nigh
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
| **riders** | status id → stacks, one entry per id (#1733 R1) | statuses planted — aspect statuses and element statuses alike |

A hit crits once, as its own fact, and its riders copy it (#1741, built
2026-11-04). Whether a go-off's *copy* also copies its parent's crit is open:
a spell blast's shrapnel draws its own crit today (`PairedDamageEffect`, no
paired lead), only a melee blast and riding landings copy. #1741's owner line
also fixes an order inside a hit — *"elemental riders first … then other
status(es), then damage(s)"* — which § Landing resolution must keep.

An element status (Fuel, Heat, Cold, Frostbite, Charge) rides exactly as
Poison rides; it differs only in which count caps it. Owner, on one rider
map: held, conditional on aspects being 1:1 (*"depends on the status
cardinality maybe"*), which § The two axes settles. There is no third entry:
anything new is a number that lands (payload); where it lands is the node's.

**Which element statuses ride.** Every counted role — terrain stack, Fuel,
mover — can be a rider row (a goo arrow plants Fuel, an ice spell plants
Cold on the chokepoint, a hot arrow plants Heat); a state never rides, it has
no count. Owner, 2026-11-04: *"if fuel is to be a fire status.. and option 2
says `fire:heat` at exactly one then how could a fuel-planting arrow exist? it
couldn't. so i guess that rules out option 2? option 1 sounds reasonable"*.
One cap per element across its whole family.

## The forge: one row type, an open set of uses (owner, 2026-11-04/08)

An intake row is the one `AspectIntake` type (ADR 0060: identity, innate,
int:int rates) plus a **use** that says what its load buys: ADR 0070's
swappable `LoadUse`, an open set. The seam exists: Firecracker's fuel row
already carries a `use` (`attack/spell/load_use/`). Owner, 2026-11-08:
*"spell infusions may also do bespoke stuff instead of simply adding riders,
we are free to design what feels useful and fun to have"*. Two uses carry
the elements so far:

| Row use | Buys | Supply cap |
|---|---|---|
| **ride** (the default) | a rider of the named status: Heat, Fuel, Cold, Charge, or any aspect status | that status's aspect or element count |
| **shape** (bespoke, per spell) | spell-specific: Firecracker's blast waves, Ice concentrate (§ Ice on a cast) | whichever count it names |

- **No use gives a hit reach.** A shape use may reshape the cast (Ice trades
  hops for seed payload before it leaves), but reach at a landing is read off
  the node alone.
- For arrows and blades the count is supply the way an aspect count is:
  it sets how many element arrows a reload mints (`AmmoType.per_reload_stat_id`)
  or how much element addon a build affords, and each arrow or vertex carries
  an *authored* innate load. A count-scaled load on every arrow would be the
  per-hit load this doc rejects. There is no int:int rate seam on an ammo type
  or an addon today; whether one is wanted is a spec-time call.

## The reach rule (owner's atomics, 2026-11-04)

**A hit landing on a primed node sets it off, and the go-off copies the
hit's payload to every node it reaches at one share** — Burning over a disc,
Shocked to every neighbour; Frozen denies. The owner's atomics (2026-11-04),
each a tiny unit of play the rule must produce, all need the node primed:

1. *"a ranged poison arrow can hit a fueled up, volatile node and have its
   poison payload be applied amongst the blast radius instead of just the one
   node"* — the node is Burning (Heat past T); the arrow is the trigger; the
   disc's power is the excess plus all the node's Fuel; the poison lands on
   the target and a share on the disc; the Fuel burns into 2 Heat per Fuel.
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
none carries any. **Planting** (a goo arrow laying Fuel, an ice spell laying
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

**A go-off with no parent hit** — a Burning node holding Fuel on the world
tick — is a **terrain hit** (owner, 2026-11-05: *"option 1"*): its copies
carry only the blast's own damage (∝ power), no riders, no crit,
side-blind, so your own Hearth beside your own keg burns your own nodes too.
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
landing's copies are not. Whether a copy copies its parent's crit stays open
(§ The hit).

**Damage type: none.** Elements change reach (through the terrain they lay),
aspects change payload, damage stays one number. Movers get
`<mover>_resistance` as any status does. If a fourth type ever earns its
place it is one word, "elemental" (owner, 2026-11-04: *"if it gets one, its
just 'elemental' (opposing physical or magic or true)"*).

## Ice on a cast: concentrate (owner, 2026-11-04/05/08; shape open)

Burning and Shocked add copies at a landing. Ice concentrate does the
opposite **at cast time**: an Ice load rewrites the spell's own hops down and
pays the seed payload up. It stays under terrain-only reach (owner,
2026-11-08: *"ice concentration should i think still be a thing just not sure
how"*); what follows is the pass's best shape, a bespoke `shape` use
(§ The forge), unconfirmed. It reads the cast, not the node, because the only
copies it can remove are the cast's own walk; an arrow or a blade has no
walk, so their Ice faces are Cold ride rows. Owner: *"a 4-hop spell could be
shrunk to a 1 hop spell at more damage (or statuses?) for the one hop. or
reduced to 0 hops even for 1 pinpoint hit. as balance against AoE euclidean
or hop based proliferation being almost strictly "more", frost could reduce
hops yet still achieve "more" somehow"*. The price must be something the
cast knows before it lands — `max_hops` and the seed load — never the
realized landing count (*"a spell beforehand doesnt know how many hits a
4-hop spell would do"*). Pure hop reduction with no bonus is out: *"a pure
nerf if it just reduces hops"*.

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
visit cap k clamps landings near k × coverage. So an Ice price reads both `max_hops` and `max_visits`, both
known at cast. Hop reach is absolute, not relative: 8 hops is ~75 nodes on
an 800-map and about the same on the aimed 2–4k map, so the number to
reason against is reach versus the *target's territory*, which grows over a
run (an entity holding 100 nodes is covered by a 6-hop fan). The first hops
are worth the most: a flat bonus per hop
removed overpays long spells and underpays short ones. **Pass lean:**
the Ice row's int:int affinity converts count to hops per spell (Venom Burst
2:1, Pestilence 4:1 — the ADR 0060 mechanism, which also absorbs counts of
20–50), and each hop removed multiplies the seed payload by a per-spell knob
near the measured ratio of the hop it removes. Surplus Ice beyond the spell's
hops is wasted; a 0-hop spell has nothing to trade.

**The price is an authored mass per spell, spent by a swappable use** (owner,
2026-11-05: *"option 1 but possibly even in this authoring one could set up
*how* it triggers exactly. some resource? like most spells -> just reduce
hops. some others -> maybe reduce max visits. something that takes the
ice-suppression value and uses it to alter the cast spell?"*). Each spell
authors what its walk is worth beyond each hop (an int per hop, or a total
with a decay), guided by the measured ladder and tuned by hand; nothing is
computed from the graph at cast. **How** the Ice load alters the cast is a
`LoadUse`-shaped resource on the Ice row (ADR 0070's open set): the common
one rewrites `max_hops` down and pays the mass beyond the new limit onto the
seed, another rewrites `max_visits`, and a spell that authors neither
(infinite hops, unbounded visits) refuses Ice until priced by hand. Rejected:
one global hops-to-multiplier curve (overpays decaying walks, underpays dense
ones), a flat per-hop addition (the first hops are worth the most).

**A concentrated seed on a primed node is a combo**, not an exploit to rule
out. The seed lands with its concentrated payload and a Burning or Shocked
node copies it at share like any payload (owner, 2026-11-05: *"hitting
Charged/Fueled nodes with ice load just proliferates whatever the ice would do
but on the defender's side (incoming hit proliferates via hops or AoE boom)
instead of on the attacker's side … and ice + fuel sounds like a combo why
not?"*). The magnitude is therefore the pricing knob's to bound: under the
ladder lean above, Pestilence concentrated from 4 hops to 0 carries ~84× a
landing's payload, and a 0.5 share of that is 42 poison per disc node, so the
knob is priced with this combo in view.

## Landing resolution (owner, 2026-11-05)

Owner, 2026-11-05, on the three phases below: *"hold it"*. Three phases per
landing. Read and settle are pure functions of one snapshot (#1733 R4);
*inside* land the shipped order stands — riders before their hit (ADR 0067)
and the owner's #1741 order, element riders, then other statuses, then
damage — so a Curse arrow still lifts its own hit. What the phases forbid is
a rider *reacting* mid-land, not an order:

1. **Read.** The node's primed states are read as they were *before this
   hit*; they are the reach. The Frozen check is here.
2. **Land.** Damage and every rider are added, aspect and element statuses
   alike. Nothing reacts during land.
3. **Settle.** One pure function of the node as it now stands: the Heat ×
   Cold netting, the go-offs the read phase found spend their stacks, and the
   copies go out to the reached nodes — each running its own read, land,
   settle under the once-per-node-per-hit cap (per arrow, per wave).

A hit carrying +1 Heat onto a 5-Cold node is read against 5, lands, and
leaves 4: it thaws for the *next* hit, never for itself. The same settle runs
after every world-turn tick.

**Dual reach** resolves by the read phase alone: every primed state present
at read fires, each spending its own stacks, so a node both Burning and
Shocked blasts and arcs. Each gathers its own target list and the lists are
**concatenated, not deduplicated**: a node inside the disc that an arc also
reaches takes one copy per reach. Owner, 2026-11-05: *"the double counting
might be a feature! tentative option 2, where union is kept as an easily
switched to option if we change our minds. after all it's just a "do you
dedupe the list or not" after gathering each reach medium's additional
targets"*. Tentative: the dedupe is one switch at the gather step, so the
build keeps it as a knob rather than a structure.

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
| **Frozen** | denies reach, ends a path; a blade vertex snaps | nets: Heat thaws it, for the next landing | cold passage: no shed (#1444) |

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
*"Burning ignites"*, picked over "any Heat ignites" of #1660 round 2): a
Burning node holding Fuel explodes on the world tick (#1696's ignition). A
leaf (T 2) lights at three Heat, a degree-5 hub needs eleven, so hubs are
hard to blow and tips burn bright. The door the owner kept open (*"a bespoke
twist or tweaked T value later for Burn. or extinguish mechanics"*) stays
open.

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
count, minus world turns since it was last written, floored at 0). So Charge
and Fuel, which never flow, cost nothing per world turn. Only the Heat/Cold
diffusion is a real pass: **one** pass over the signed `t`, over the
temperature index (nodes holding Heat or Cold, the `_lingering` registry's
shape), on packed arrays, never a walk of the graph. Worst case is a fully
hot 3k-node board at mean degree 3: ~9k integer edge updates once per world
turn, not per frame. A GDExtension only if a profile says so. The native
toolchain already exists (the XPBD solver is C++), so the cost is a C++
implementation that must stay the **only** implementation (never a GDScript
mirror), not a new build.

Everything else coexists. Fuel and Cold coexist: a frozen keg sits inert
until it is thawed and Heat takes it past T. Heat never touches a Frostbite
pack (owner, 2026-11-04: *"Heat & Cold don't make sense together. frostBITE
is an ailment"*). Charge has no opposite. Rejected: Fuel damped by Cold
(terrain fighting terrain with nobody acting).

## Three things wear the word "explosive" (pass clarification, 2026-11-04)

Owner: *"fuel defensive: explode (trigger aoe reach), fuel rider: splodes
(spreads) or plants?? (adds fuel??) or is that Magic making an exception …
i confuse myself"*. No status has an offensive and a defensive face; three
different rows share the old word, on every facet alike:

| | Row | What happens | Plants |
|---|---|---|---|
| "infuse Explosive to make it AoE" | a Heat **ride** row (or a bespoke shape use) | the hit plants Heat; once its node is past T, later hits there blast | Heat |
| "goo arrow" | a Fuel **ride** row | Fuel is added to the landing node, inert until the node is Burning | Fuel |
| "a fuelled node" | terrain on the node | while Burning, any hit blasts it and its Fuel joins the power; it also blasts on the world tick | — |

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
| **Rider** | Plants a status — any status, terrain and movers included (a goo arrow plants Fuel) | a reach |
| **Use** | What an intake row's load buys: an open set (ADR 0070's `LoadUse`) — ride, a bespoke shape, cleanse … | a slot |
| **Terrain stack / Mover / State** | The roles in an element's family (table above): Heat, Cold, Charge / Frostbite / Burning, Frozen, Shocked; Fuel is Fire's accelerant | "the fire status" |
| **Primed** | A node whose terrain stack is past T (count > T, T = 2 × degree): a hit on it sets it off | a status with stacks of its own |
| **Excess** | count − T on a primed node: Burning's power, what a shatter spends | the overflow |
| **Overflow** | Stacks past the cap k × T: decay fast; deep freeze spends them | wasted |
| **Member** | A status of an element, whatever its role: Fuel and Heat are members of Fire; an Element Matrix row is a member row; a member keys its own facets (`fuel_resistance`) (owner, 2026-11-05: *"member"*) | a facet (arrow / blade / spell) or a role |
| **Fire / Heat / Burning** | The element (its count) / its terrain stack / Heat past T | three names for one thing |

## Acquisition (owner sketches, 2026-11-03/04; nothing picked)

Both sources every stat already has: **permanent, slow** (an inner-tree ring
or sector — owner, 2026-11-04: the inner-core mini skill tree as *"one of the
primary sources of adding +1..N modifiers"* — a periodic *"+1 to <element of
choice | choose 1 el out of 3 cards>"* offer, map-found modifiers, mods stolen
from slain enemies) and **board-temporary** (a keystone: *"a fire keystone
that also supplies heat or fire stacks"* — the Hearth of #1716 round 2,
emitting Heat each world turn and granting fire while held).
`apex_inner_tree.md` is six schools × two aspects today; elements would be a
third ring or a three-spoke tree. Filed against the element hub, not settled
here.

## Open

- **What a go-off pays, per element** (§ The threshold model): 1 per
  trigger, or ½T = degree; lean: Shocked pays per neighbour, Burning pays 1.
  The same call decides whether a spend may take a node below T.
- **How a shatter turns excess into damage** (§ The threshold model): flat, a
  percentage, a multiplier, or per hit (owner, 2026-11-08). The owner's
  2026-11-05 shapes are candidates too: *"maybe %dmg like corruption stack
  triggers? … (or make it crit?!? [add +1 crit level])"*.
- **Ice concentrate's shape** (§ Ice on a cast): kept; the bespoke cast-time
  `shape` use there is the pass's best, unconfirmed.
- **Element rows in the forge**: whether element ride rows take the aspect
  slots (INT) or slots of their own, and how many elements one cast may
  carry.
- **A death blast** (#1660: a death blasts first): a holder's death is not a
  hit, so whether it sets off a primed node, spends its terrain, or does
  nothing to it.
- **Fuel's cap**: k × T caps the terrain stacks; whether Fuel, which never
  counts toward T, shares that cap.
- **Breaking Frozen by reach**: Frozen denies reach; whether a big enough
  blast or arc arriving breaks the ice instead (owner, 2026-11-05: *"maybe
  the "frozen" state sets some kind of glass ceiling for what it absorbs,
  which needs to be broken, so it blocks insufficient counts?"*). Heat, a
  blade's snap and decay break it already.
- **Frozen and Shocked on one node**: whether the ice denies the node's own
  arcs, or only reach arriving from elsewhere.
- **A wire evens itself out** (pass idea, parked, not picked): a connected
  run of Shocked nodes shares its Charge each world turn — the one flow
  Charge could have beside staying put.
- **Arc mirror** (owner idea, 2026-11-05, parked): *"maybe when a nb tries to
  emit a lightning reach it reflects it? maybe not"*. Shocked arcs to every
  neighbour, so a Frozen neighbour is always struck; whether that arc grounds
  or bounces back onto its emitter is for Lightning's spec. A blanket reflect
  was rejected (owner, 2026-11-05: *"reflect: too powerful, esp being as
  cheap as 2 Cold on a leaf node"*).
- **Ranged's access to Fuel: an Element Matrix** (owner, 2026-11-04:
  *"option 1 sounds good"*), one row per family status, columns `Ammo :
  Addon : Spell : Infusion`, so the Explosive addon becomes the Fire::Fuel
  addon cell. Still open on it: **availability** — a found addon is not
  Clamp-like (owner: *"god i hope i find an explosive addon anywhere in the
  nearest 20 hops from where i spawned"*; the fuel-arrow count *"need to get
  into 10s ASAP"*, and late-game ranged fires hundreds of arrows), so the
  Fuel ammo cell wants a steady source (a reload grant from the count is one)
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
- **Adversarial review, 2026-11-05** (full list in `docs/handoffs/elements.md`),
  the items that need an owner call before any element issue is `Ready`:
  (a) **row keys**: `Infusion.load_of` and `StatusRoster.by_concept` key on
  one concept id, so a Fuel ride row and a Heat ride row cannot both key on
  `fire` — #1660's B2 (*"intake row names which of its aspect's statuses it
  plants"*) is the fix and must be carried into the row design; (b) **facet
  ids**: `<x>_stacks_per_hit` / `<x>_resistance` key per status (#1660 A1),
  so a member keys on itself (`fuel_`, `heat_`), while the count needs a new
  `StatDef.Role` (`fire` is not `fire_aspect`); (f) **Charge** collides
  with explosive's `charge` tag and `vertex_charges` — the #1716 r2 retag to
  `fuel` is the plan and must be in the first Fire issue; (h) a rider map keyed by id merges a BEFORE rider with an AFTER copy
  of the same id — coalescing is still #1741's open NOTE, not an owner call.
- **Greed under the new vocabulary** (#1659, owner 2026-11-03: the "stacks
  outlive the kill" direction is *"a lame exploit already on paper"* — kill
  for the XP, the enemy retakes, kill again at the same count). Greed is an
  aspect status, so sided; the cursed-gold feel needs a carrier. Shapes on
  the table: the stacks jump to the killing node (hot potato), spent on kill
  (as built), or ride the relic (#1662). Unpicked.
- **Knobs** (§ The threshold model): T = 2 × degree, k, the hop ladder's
  L² × T, the disc's √power × node radius, the decay rates — tuned with
  #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- **Spike pop docs vs code**: owner, 2026-11-08, *"The existing one just pops
  the one, docs may be stale"* — `BladePopResolver`'s header and
  `docs/domain/ai-blade-rollout.md` describe severing past a pop; check
  against the code at the Ice spec.
