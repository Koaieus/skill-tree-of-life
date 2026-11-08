---
status: settling
---

# Elements — reach as a stat and as terrain

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
Fire's medium (the ranged-access question this raises is in § Open).

## The threshold model (owner, 2026-11-08)

Owner, 2026-11-08: *"make them all inert before some threshold T is passed.
when "elemental terrain-reach stacks" (== cold/heat/charge stacks) exceed T,
then they become primed -- the derived status … this derived effect has a
"trigger" and if triggered it performs (generally) a reach-based action, and
finally, each triggering has a stack-cost … this derived status IS the reach
face of the element. without it, no reach effects"*. Where a passage below
disagrees, this section wins; the list at its end names them for deletion.

**One terrain stack per element, inert up to T.** Heat (Fire), Cold (Ice) and
Charge (Lightning) are side-less terrain, owner-blind. At or under T they
only *feel*: Cold drags a blade and Heat speeds it, one curve of the signed
`t = heat − cold` (owner: *"maybe cold stacks slowing blade nodes sweeping
over them (and heat stacks... should speed them up a lil?)"*). Past T the node
is **primed**: Burning, Frozen, Shocked. **T = 2 × graph degree**, primed at
count > T (owner: *"T = 2*graph_degree, so a leaf node fits 2 stacks of any
without any effects, the third would be 3"*), a knob. The **excess** is
count − T; the band above the cap k × T is the **overflow** (the 2026-11-06
"excess band", renamed).

**Reach is terrain-only.** A hit is damage plus riders and carries no reach of
its own. Owner, 2026-11-08: *"Think that charge settles it in favor of the
"there's 1 and its just the terrain stacks": if 1 "charge as direct arc
reach" is infused it reintroduces "which one neighbor then?" While a system
where "charge Level = 1" means you got enough to hit *all* nbs."* A Fire or
Lightning infusion is a ride row planting Heat or Charge, so an infused AoE
spell ramps: its early hits warm the ground, its later hits blow it.

**The trigger is a hit on a primed node**, a copy included, so a chain needs
no rule of its own (backdraft is this trigger):

| State | A hit on it | Also |
|---|---|---|
| **Burning** | explodes: a disc, power = the excess, a little damage ∝ power, the triggering hit's payload copied over the disc | burns its holder each world turn ∝ the excess, side-blind (owner pick, 2026-11-08) |
| **Shocked** | arcs to **every** neighbour (owner: *"it will arc to *all its neighbors* each time it is hit"*); the arc pick rule is gone | conducts a spell walk (§ Derived states) |
| **Frozen** | denies: absorbs arriving reach, ends a path (0D) | a blade snaps on it (below) |

**The cost law: a go-off pays one stack for each node it reaches**, spending
down to T at most (pass: a node at excess 1 still fires whole); Frozen pays one Cold per unit of reach it absorbs, as it
already did. Owner, 2026-11-08, on what drains a 100-hit buildup: *"Maybe..
spend ½T stacks instead of 1? Or some multiple of *degree*? … Can we boost
that?"* With T = 2 × degree, ½T *is* the degree, the count of nodes a level-1
Shocked node strikes, so both are one number. A Shocked node filled to the
bare-ground cap (3T) goes off exactly 2(k − 1) = 4 times whatever its degree
(6 at stake 2, 8 at stake 3); for Burning this holds only if its disc is a
hop ball (§ Open). **Copies carry everything**, element stacks
included (owner pick, 2026-11-08, re-affirming 2026-11-05): a 1-stack rider
on a copy breaks even with the stack its copy cost, so a go-off moves stacks
outward and never multiplies them; riders of 2+ per copy grow the primed area
about a ring per hit, paid in load and bounded by the cap and decay. On a
Shocked leaf (one copy) a stream of r-stack hits changes the node by r − 1
per hit.

**One size ladder.** Level L at count > L² × T (owner, of Charge: *"T = 1
hop, 4T = 2 hops, 9T = 3 hops"*), for all three: a radius step for Burning, a
hop for Shocked; power stays the excess. On bare ground (cap 3T) level 2
lives only in the overflow or on a staked node. Knobs.

**Fuel is an accelerant.** Owner: *"Fuel would only be a supportive sticky
"pre fire but would burn as such" goo … if any fire-related combustion
occurs, consume all fuel stacks too add them to the explosive power, and
leave residual heat."* Fuel never counts toward T (pass); when its node
explodes all of it is spent, added to the power, and burns into **N = 2 Heat
per Fuel on its own node** (owner pick, 2026-11-08, over +1 Heat on every
node the disc touched, which makes Heat from nothing); flow spreads it. Heat
is spent per copy and Fuel whole, so Heat arrows sustain and Fuel-then-Heat
bursts: two volley shapes. A Burning node holding Fuel also goes off on the
world tick (pass; keeps #1660's fuse).

**A blade on Frozen: a fragile snap.** Owner, 2026-11-08: *"if a melee blade
node has Frozen on it, if should shatter on first contact. Reduces reach
right? Any blade node popped is less sweep. And if frozen node is hit by
blade node, it.. shatters the ice … but *also* shatters the offending blade
node!"*, then *"We want to pop just the two vtx. Not too dramatic, and
remember Ice is 0D. Point like. Single target. So no splash or anything just
a fragile snap"*. First contact pops that one vertex (the spike pop, no drain
check, nothing severed) and breaks the ice; pass: the ice spends everything
above T, overflow included, as single-target damage to the frozen node's
holder. This replaces the "remove T, +1 crit tier" pane below.

**Cooling.** Heat is terrain now, so it no longer dies on unallocated ground;
every warm or cold node decays 1 toward zero per world turn (owner: *"if we
make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it
should eventually cool off"*), Charge likewise, Fuel slowly — knobs. The
Metropolis step is the discrete graph-Laplacian step; its integer floor is a
dead band, and the decay clears it. Every warm node loses one, so spread heat
cools faster than a lump: no board-wide budget is needed.

**Superseded below, for the deletion pass:** the Fire row of § One count
(Fuel as medium, Heat as a hurting mover, T = degree + 1, "only movers deal
damage"); the `reach` use and the element slot (§ The forge); § The reach
rule's reach entry, `S + SI`, Cold-under-T absorbing, one stack per landing,
the atomics' bare Fuel or Charge going off, and the planting exemption (the
owner's own volley has a Heat arrow blowing the node it lands on); dual
reach's "the hit's load spends nothing"; § Pair rules' table, the arc pick
rule and the pane; § Derived states' backdraft verb, Shocked's leaps and
Blaze and Supercharge (dropped: the overflow just decays fast, the ladder is
the inferno ramp); § Temperature's Heat sink and min(heat, fuel); the Fire
reach row of § Three things wear "explosive". ADR 0073 (the reach entry) and
0074 (absorption under T) go to ADR 0075.

## One count, a family of statuses with fixed roles (owner, 2026-11-04)

An element is one count on the entity and a short family of statuses on
nodes. Nobody points at "the" fire status; the **roles** are what you point
at. Owner: *"that table looks very good, should be persisted"*.

| Element | Count (entity) | Medium — terrain, side-less, gives reach | Mover — sided, hurts, spreads | State — derived, no count of its own |
|---|---|---|---|---|
| Fire | `fire` | **Fuel** (a volatile node) | **Heat** (the Metropolis diffusion locked in #1660 round 2) | **Burning** = Heat ≥ T (derived, no count; T as Frozen's); a keg goes off only while its node is Burning (owner, 2026-11-05); § Derived states |
| Ice | `ice` | **Cold** (what a pack sheds; #1444's resting stacks; was *Frost* — owner, 2026-11-05: *"Cold i think. Frozen is a different effect, derived by Cold count (and degree) … frost sounds too "already being a DoT""*; Cold below the threshold still drags blades, #1444) | **Frostbite** (#1444's inward pack; the working name *Hypothermia* retires) | **Frozen** = Cold at or above a threshold; the "timer" is Cold decaying back under it |
| Lightning | `lightning` | **Charge** | none in v1 | **Shocked** = Charge ≥ T — #1733 round 3's *critical Charge* (Charge > graph degree) under its name |

- **The count never ticks on anyone.** Only movers deal damage, and a mover is
  an ordinary sided status that clears with its owner like Poison does.
- **The medium is terrain.** It rests on a node regardless of owner, survives
  kills, retakes and deallocs, and leaves by being *spent* (a blast spends
  Fuel, an arc spends Charge, a thaw spends Cold), by its own decay (per-def,
  ADR 0048; Frozen's "timer") or by a cleanse. **Cold also flows**, by Heat's
  own Metropolis rule (#1660 round 2: `floor((c_i − c_j) / (max(d_i, d_j) + 1))`
  per edge, one snapshot, integer dead band). Owner, 2026-11-05, on a capped
  wall beside bare neighbours: *"something doesn't quite feel right of a 100
  Cold node with neighbors of 0 Cold … just sits there as if perfectly
  isolated"*, then *"option 1!"*. 12 Cold on a degree-3 node beside three 0s
  settles at 6 / 2 / 2 / 2 and stops: the wall stays Frozen (T 4) and a fringe
  forms around it — #1444's channels for free. Unlike Heat, Cold that flows
  onto an unallocated node rests there (cold ground) instead of being deleted;
  Fuel and Charge stay put. A death *spends*: the #1660
  owner call that a death blasts first is a spend, not a clear. The
  readability test: *if nobody owned this node, would it still make sense for
  this to be here?* Fuel on an empty node, yes; Poison on an empty node, no.
  Build note: today's `on_dealloc` has CLEAR and LINGER and a death clears
  both; a medium needs a shape that survives death too — a seam for spec time.
- **A state has no count.** It is a threshold on its medium; it does things
  (Frozen blocks travel, #1444) but holds no stacks. It is derived at every
  read, never saved: Frozen re-forms whenever Cold is back at or above T
  (owner, 2026-11-05: *"Yes, pure threshold"*).
- **A medium is capped per node at k × T**, T = graph degree + 1,
  **k = 2 + the node's `stake_level`** (owner, 2026-11-06: *"k = 2 (base
  value) + stake_level (statformula)"*) — a derived scaling rule on the node
  board (manage-stats), so a deeper-staked node holds more terrain and bare
  ground (`stake_level` 1) gives k = 3, the pass's earlier default exactly.
  Range: `stake_ceiling` is 3 unless raised, so k runs 3–5; a leaf (T 2)
  holds 6–10, a degree-5 hub (T 6) 18–30, which late counts of 20–50 can
  fill in one cast. Stacks past the cap are not wasted: they are the
  **excess band**, § Derived states. Owner, 2026-11-05, asked whether
  a 100-Cold wall should be nigh impossible to remove: *"option 1 sounds
  good"* (the cap) over proportional decay alone. One rule bounds a Cold
  wall's depth (a wall is at most k breaks deep), a Fuel blast's radius and a
  Charge node's leaps — the medium-magnitude fork of #1733 round 3.
- **No lightning mover in v1** (owner, 2026-11-04: *"Fun but maybe start
  with just the 1"*). The three derived states are § Derived states.

## The count is supply, never a load (owner, 2026-11-04)

The count is a budget a face draws from; by itself it loads nothing onto a
hit. Owner: *"this is like "how Fire/Ice/Lightning ARE you really" counter,
which likely ends up being a maximum/budget of sorts for some situation, but
in most cases doesn't load automatically (maybe some cases would arise later?
so far just none)"*. This is the same sentence an aspect count already says —
X poison means X poison arrows a reload, X of poison-costing temp addons, X
maximum poison infusion — and it keeps #1733 R2: a 30-vertex sweep is never
30 blasts, because reach per hit is paid for by a face, never granted by a
stat. A build with zero in every element is untouched, and so is a hit no
face loaded.

The counts are meant to grow well past the small ints aspects sit at today.
Owner: *"attaining 20 of it, or maybe into 50 or possibly even 100 (tho 100,
that's a stretch. 50 sounds *somewhat* reasonable for late game …)
everything starts small. the inner-core mini skill tree, i envision, would be
one of the primary sources of adding +1..N modifiers to aspects, alongside
map-found modifiers, or stolen mods from slain enemies"*. Every rate that
reads a count is therefore an int:int affinity (ADR 0060), never "one count,
one hop".

## The hit: damage, riders, reach (owner, 2026-11-04; ADR 0073)

A hit has three kinds of entry, and the first two are its **payload**:

| Entry | Shape | Lands as |
|---|---|---|
| **damage** | one number | HP loss |
| **riders** | status id → stacks, one entry per id (#1733 R1) | statuses planted — aspect statuses and element statuses alike |
| **reach** | one `(element, load)` | *where* the payload is copied; resolved first |

A hit crits once, as its own fact, and its riders copy it (#1741, built
2026-11-04). Whether a *reach copy* also copies its parent's crit is open: a
spell blast's shrapnel draws its own crit today (`PairedDamageEffect`, no
paired lead), only a melee blast and riding landings copy. #1741's owner line
also fixes an order inside a hit — *"elemental riders first … then other
status(es), then damage(s)"* — which § Landing resolution must keep.

An element status (Fuel, Heat, Cold, Frostbite, Charge) rides exactly as
Poison rides; it differs only in which count caps it. Owner, on the hit's
three entry kinds with one rider map: held, conditional on aspects being 1:1
(*"depends on the status cardinality maybe"*), which the section above
settles. There is no fourth entry: anything new is a number that lands
(payload) or a rule about where it lands (reach).

**Which element statuses ride.** Every counted role — medium and mover — can
be a rider row (a goo arrow plants Fuel, an ice spell plants Cold on the
chokepoint, a hot arrow plants Heat); a state never rides, it has no count.
Owner, 2026-11-04: *"if fuel is to be a fire status.. and option 2 says
`fire:heat` at exactly one then how could a fuel-planting arrow exist? it
couldn't. so i guess that rules out option 2? option 1 sounds reasonable"*.
One cap per element across its whole family.

## The forge: one row type, three uses (owner, 2026-11-04)

An intake row is the one `AspectIntake` type (ADR 0060: identity, innate,
int:int rates) plus a **use** that says what its load buys. The seam exists:
Firecracker's fuel row already carries a `use` (`attack/spell/load_use/`).

| Row use | Buys | Supply cap | Slot |
|---|---|---|---|
| **ride** | a rider of the named status | that status's aspect or element count | the aspect slots (INT) |
| **reach** | the cast's one element load | the element count | **the one element slot** |
| **shape** | spell-specific (Firecracker's blast waves) | whichever count it names | authored only, never infused |

- **One element slot per cast, separate from the aspect slots.** A cast
  borrows at most one reach: it is a fire cast or a lightning cast, never
  both. Owner, 2026-11-04: *"managing reach does feel like something you'd
  wanna keep separate (and whose contribution in the Payload you'd wanna
  resolve first on landing the Hit) and maybe even restrict to 1 element at
  once"*; on the slot options, *"option 1 sounds best"*. Rejected: shared
  slots (arcs-then-blast per hit becomes routine and unreadable), an N-slot
  element pool (dual-element casts nobody asked for).
- **The element slot buys reach only.** A Heat or Fuel rider is its own
  `ride` row the spell offers or the forge adds, drawing from the same count
  as a cap (owner picked this over "reach plus the family's default status"
  and over "reach only, ever"). Poison, with one status, collapses to one row,
  so nothing changes for aspects.
- Firecracker's fuel row is the element slot in disguise; once the slot
  exists it is an ordinary `reach` row and the spell gets simpler.
- For arrows and blades the count is supply the way an aspect count is:
  it sets how many element arrows a reload mints (`AmmoType.per_reload_stat_id`)
  or how much element addon a build affords, and each arrow or vertex carries
  an *authored* innate load. A count-scaled load on every arrow would be the
  per-hit load this doc rejects. There is no int:int rate seam on an ammo type
  or an addon today; whether one is wanted is a spec-time call.
- **Infusing a second element onto a spell that has one** (Firecracker's
  authored Fire): the slot is one row, so a Lightning infusion has no row to
  land in and is refused — the forge shows the slot as taken, the way an
  affinity of 0 refuses an aspect today (ADR 0060). A spell that should accept
  a swap authors a row per element it accepts, the player fills one; pass
  lean is to start without swaps and let content ask for them.

## The reach rule (pass proposal, 2026-11-04, from the owner's atomics)

**A hit's reach is set by the element it carries plus the element resting on
the node it lands on. Its payload is copied to every node reached at one
share. A medium that gives reach is spent by the reach it gives; the hit's
own load is not.** Cold gives no reach; it **absorbs** it. Owner,
2026-11-05, on a +20 Fire & Charge hit onto a leaf holding 2 Cold: *"cancels
sounds good but also possibly OP … if it just goes "poof" yeah idk if that's
right"*, then held: **Cold absorbs arriving reach one for one and is spent
doing so.** At read, each Cold stack on the landing node swallows one unit
of reach (one radius step, one arc) from every source present — the hit's
load, the node's own Fuel or Charge, an arriving arc — and melts. +20 onto 2
Cold: 18 goes out and the node thaws; +20 onto 30 Cold: nothing goes out,
10 Cold is left. A wall holds exactly as deep as it is, and late counts
(20–50) make deep walls. The load pays in reach, so a thaw by load is no
longer free; a go-off whose reach is swallowed still spends its one stack
(it went off, into the ice). Cold is side-less, so the freezer's own reach
is eaten too. What Frozen adds on top of absorption — the glass ceiling — is § Pair rules.

The owner's atomics (2026-11-04), each a tiny unit of play the rule must
produce:

1. *"a ranged poison arrow can hit a fueled up, volatile node and have its
   poison payload be applied amongst the blast radius instead of just the one
   node"* — the arrow carries no fire; Fuel on the node gives the blast; the
   poison lands on the target and a share on the disc; Fuel is spent.
2. *"take poison spell, craft an AoE effect on it by picking Explosive
   infusion, and watch each hit turn into an AoE hit"* — each hit carries fire
   at the infused load and lands on plain nodes; a blast per hit; nothing
   planted, nothing spent.
3. *"A Curse arrow hits a Charged (lightning) node and it applies curse to the
   target *and* to 1..N neighbors"* — the arrow carries no lightning; Charge N
   gives up to N arcs (the pick rule is #1733's); Charge is spent.

What falls out: the reach entry reads the same for an arrow, a blade vertex
and a spell hit. **Planting** a medium (a goo arrow laying Fuel, an ice spell
laying Cold on a chokepoint — the player control #1716 asks for) is a `ride`
row like any rider. The shipped rule stays: a hit that plants a medium does
not trip it.

**Same element, one go-off.** A hit's own load and the medium of the same
element on the node it lands on are one reach source, not two: its size is
`S_total = S + SI`, the node's stacks plus the hit's load (owner, 2026-11-04,
#1733 round 3, said of Charge: *"Incoming load: S_total = S + SI … sounds
best i think"*; confirmed for Fire and as the one rule, owner, 2026-11-05:
*"Fire load and fuel held are one and the same basically (binned, grouped,
summed). Same for charge x charge"*). #1660's *"its power is the
node's fuel"* is the same formula with a hit load of zero, since Heat
ignition carries no load. A *landing's* go-off spends **one** stack of the
node's medium (owner, #1733 round 3: *"consuming 1 at a time"*), never the
hit's load; a *Burning tick's* ignition spends min(heat, fuel) (#1660 round
2, re-affirmed 2026-11-05) — two owner lines, one per trigger, kept side by
side on purpose. Dual reach (§ Landing resolution) is only ever *across* elements.

**Chain reactions** are bounded (#1733 R3): a copied hit landing on a node
that holds a medium spends it and reaches again from there, once per node per
*hit* — per arrow, per spell wave, as `HitLanding.detonated` is today —
**carrying the payload the copy arrived with, undiminished**: the copies of a
chained go-off are `damage × s`, riders `ceil(r × s)` of the *root* hit at
every link, never `s^k`. Owner lean, 2026-11-05 (#1735 fork 1): *"I am tempted
to say: LET IT RIDE. The hit, all rider, no decay. Maybe raise you: for charge
arcs hitting charged nodes also just keep arcing (and consuming a stack ofc)
and concatenating hits."* — the raise is already the chain rule (an arc copy
landing on a charged node goes off there). Why it is bounded without decay:
every link was *planted* (a keg is Fuel somebody paid for), each node goes off
once per hit and spends a stack, so a fuse's total is ≤ s × root × the nodes
its kegs reach — linear in Fuel laid, #1733 R2's conserved pool, and the
once-per-hit cap keeps a volley at size(F), size(F−1), …. The owner's own
caveat, same message: *"Or a limited decay of terrain *planting* being
limited after all hmm. Maybe that's wise"* — whether a *medium rider* on a
copy (the re-laying of Fuel, Charge or Cold along a chain) decays per link
while damage and other riders ride flat is the one residual, § Open (d). As
built today every link blasts at `s × root` (#1735's finding), so under this
lean #1735 is not a bug and closes with a doc line. The owner's
own volley needs the per-hit scope: *"if you land F+1 hits on it it would
explode for size(F), size(F-1), …, size(1)"*. **Ignition** (#1696, Heat
meeting Fuel) is one trigger among several, no longer the only route to a
blast; it fires only while the node is Burning (§ Temperature).

**A go-off with no parent hit** — a tick's ignition, a thaw, a death blast —
is a **terrain hit** (owner, 2026-11-05: *"option 1"*): its copies carry only
the medium's own damage (`damage_per_charge` × the stacks spent, the #1733
round 2 named exception), no riders, no crit, side-blind, so your own Hearth
beside your own keg burns your own nodes too. **The attacker is the sided
party in the reaction**: the Heat's latest applier for an ignition (a
`NodeStatus` already records `applier_id`), the killer for a death blast. No
new fact lands on a side-less medium. **Sync by determinism**: a terrain
cascade has no crit and a deterministic pick, so every peer reproduces it as
it reproduces diffusion today, never a host-minted record (owner, 2026-11-05:
*"no crit on unallocated nodes doing things. but even if they did, we shouldve
found a way to sync the seed (perhap during turnmanager ticks) such that it is
deterministic anyway"*).

**A medium rides a copy.** Terrain mutators proliferate like any rider: 5 Cold
planted on a fuelled node is copied into the blast's disc at `ceil(r × s)`, a
Cold arrow onto a charged node lays Cold along the arcs (owner, 2026-11-05:
*"stuff that mutates the terrain (by adding fuel or charge or cold) i think
should be able to be proliferated just fine, throw 5 Cold on a Fueled up
volatile target node and watch it apply Cold to its surroundings in an AoE
blast"*). **A copy carries every rider, the medium its reach just spent
included.** Shown the loop this opens (a Charge rider on an arc copy replants
`ceil(r × s) ≥ 1` Charge on every node the arc reaches while the go-off spent
one, a wire that never depletes), the owner kept it — 2026-11-05: *"Leaning
2. My reasoning: if buildup is too strong we can always tune up decay
rates/mechanisms"*. So a medium's per-def decay (ADR 0048) and the k × T cap
are the only bounds on a wire or fuse that re-lays itself: **no medium ships
without a decay**, and its rate is the knob that tunes buildup. Rejected: a
copy carrying every rider except the medium its reach spent.

**A copy lands raw.** `ceil(r × s)` of the hit's payload *as cast* — after
an Ice concentrate put its mass on the seed, before any per-landing fold —
so `stacks_per_hit` never multiplies with reach (#1733 R2). A hit's copies
take the hit's own target mask (the shipped bolt filters to hostile); only a
terrain hit is side-blind, so a medium is side-less but a landing's copies
are not. Whether a reach copy copies its parent's crit stays open (§ The hit).

**Damage type: none.** Elements change reach, aspects change payload, damage
stays one number. Movers get `<mover>_resistance` as any status does. If a
fourth type ever earns its place it is one word, "elemental" (owner,
2026-11-04: *"if it gets one, its just 'elemental' (opposing physical or magic
or true)"*).

## Ice on a cast: concentrate (owner, 2026-11-04; pricing open)

Fire and Lightning add a reach at each landing. Ice does the opposite and
does it **at cast time**: an Ice load rewrites the spell's own hops down and
pays the seed payload up. Owner: *"a 4-hop spell could be shrunk to a 1 hop
spell at more damage (or statuses?) for the one hop. or reduced to 0 hops
even for 1 pinpoint hit. as balance against AoE euclidean or hop based
proliferation being almost strictly "more", frost could reduce hops yet still
achieve "more" somehow"*. The price must be something the cast knows before
it lands — `max_hops` and the seed load — never the realized landing count
(*"a spell beforehand doesnt know how many hits a 4-hop spell would do"*).
Pure hop reduction with no bonus is out: *"a pure nerf if it just reduces
hops"*.

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

**A concentrated seed on a keg is a combo**, not an exploit to rule out. The
seed lands with its concentrated payload and the node's Fuel or Charge copies
it at share like any payload (owner, 2026-11-05: *"hitting Charged/Fueled
nodes with ice load just proliferates whatever the ice would do but on the
defender's side (incoming hit proliferates via hops or AoE boom) instead of on
the attacker's side … and ice + fuel sounds like a combo why not?"*). The
magnitude is therefore the pricing knob's to bound: under the ladder lean
above, Pestilence concentrated from 4 hops to 0 carries ~84× a landing's
payload, and a 0.5 share of that is 42 poison per disc node, so the knob is
priced with this combo in view.

## Landing resolution (owner, 2026-11-05; ADR 0074)

Owner, 2026-11-05, on the three phases below: *"hold it"*. Three phases per landing. Read and settle are pure functions of one
snapshot (#1733 R4); *inside* land the shipped order stands — riders before
their hit (ADR 0067) and the owner's #1741 order, element riders, then other
statuses, then damage — so a Curse arrow still lifts its own hit. What the
phases forbid is a rider *reacting* mid-land, not an order:

1. **Read.** Reach is computed from the hit's reach entry plus the node's
   mediums *as they were before this hit*. The Frozen check is here.
2. **Land.** Damage and every rider are added, aspect and element statuses
   alike. Nothing reacts during land.
3. **Settle.** One pure function of the node as it now stands: the Heat ×
   Cold netting, the mediums the read phase charged are spent, and the copies go
   out to the reached nodes — each running its own read, land, settle under
   the once-per-node-per-hit cap (per arrow, per wave).

A hit carrying +1 Heat onto a 5-Cold node is read against 5, lands, and
leaves 4: it thaws for the *next* hit, never for itself. The same settle runs
after every world-turn tick, which is how #1660 already framed ignition.

**Dual reach** resolves by the read phase alone. A node holding both Charge
and Fuel, or a fire-loaded hit on a charged node: every reach source present
at read time fires, each spends its own medium, the hit's load spends
nothing. Each source gathers its own target list and the lists are
**concatenated, not deduplicated**: a node inside the disc that an arc also
reaches takes one copy per reach. Owner, 2026-11-05: *"the double counting
might be a feature! tentative option 2, where union is kept as an easily
switched to option if we change our minds. after all it's just a "do you
dedupe the list or not" after gathering each reach medium's additional
targets"*. Tentative: the dedupe is one switch at the gather step, so the
build keeps it as a knob rather than a structure. An Ice-loaded cast landing
on a charged node has no reach entry at landing (Ice was spent on the spell's
hops at cast time), so Charge arcs as it always does.

## The reach triad (pass proposal, 2026-11-04; owner asked for the shape)

Owner, 2026-11-04: *"1. Melee - STR - AoE - explosive (fuel = AoE) - fire …
2. Ranged - DEX - single target - … - …ice? … 3. Magic - INT - edge hops based
propagation (like 90% of the time) - lightning. Make sense? Canonicalize this
somehow? What shape is this here exactly?"*; later: *"the vibes are: fire -
AoE spread - euclidean - melee; lightning - edge-hop spread - edge-hops-based
- magic; ice - single-target - pinpoint / 0-D - ranged"*.

The shape: **each element is one attack mode's native reach, made portable.**
There are three reaches a hit can have on a graph — a disc, a path, a point —
and each attack mode is born with one. An element lets any mode borrow it
(Fire, Lightning) or impose it on the board and on a cast (Ice).

| Mode | School | Native reach | Element | What the element does to a hit |
|---|---|---|---|---|
| Melee | STR | **disc** — a blade sweeps a hurtbox | Fire | replicate into a disc |
| Ranged | DEX | **point** — a target is 0-dimensional | Ice | concentrate: a cast trades hops for seed payload; on the board, Cold eats reach one for one and a Frozen node holds whole against any reach under its threshold (§ The reach rule, § Pair rules). A blade is the one hit that answers back: contact shatters (#1444), so melee meets Ice in the counters, not in the reach |
| Magic | INT | **path** — projectiles are graph automata over edges | Lightning | conduct along edges |

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

## Pair rules (pass proposal; each pair is argued on its own issue)

Rows are what rests on the node, columns what arrives. A cell is one verb,
and a blank cell means *nothing special*: the hit lands and the medium sits.

| On the node ↓ / arriving → | a Fire-loaded hit | a Lightning-loaded hit | an arc landing | a Heat rider or diffusion | a Cold rider | a Frostbite pack | a blade |
|---|---|---|---|---|---|---|---|
| **Fuel** | one blast, radius from Fuel plus load (`S + SI`), one Fuel spent | arcs from load, then blast | blast — an arc is a landing | ignition while Burning (Heat ≥ T, #1696), spends min(heat, fuel) Fuel, Heat stays | blast, Cold copied into the disc | — | blast on contact (#1660 R2) |
| **Charge** | arcs from Charge, then the blast | arcs from Charge plus load (`S + SI`), one Charge spent | arcs | arcs if a rider, nothing if diffusion | arcs, Cold copied along | — | arcs |
| **Cold under T** | absorbs: each Cold stack eats one radius step and melts; the rest goes out | absorbs: each stack eats one arc and melts | lands; the copy's onward reach is absorbed the same way | nets: thaw | adds | pays the toll: Cold sheds first (#1444) | drags (#1444) |
| **Frozen** (Cold ≥ T, T = graph degree + 1) | reach < T: the glass holds, reach lost, no Cold spent; reach ≥ T: breaks, then absorbs 1:1 | same | same; an arc into a Frozen node grounds (mirror idea parked, § Open) | nets; unfreezes for the next landing | adds | toll, a free hop if deep enough | shatters (#1444) |

**An arc's pick is most Charge, then graph degree, then fickle.** Neighbours
usually tie on the first two (owner, 2026-11-05: *"in most cases there will
be amongst nbs: no charge diff, no health diff, possibly a degree diff (with
good chance of having ties still)"*), so the third key decides most arcs: a
**seeded random pick among the tied** — the attack's own stream for a hit's
go-off, a hash of the world-turn counter and the node's `stable_id` for a tick's, so
every peer draws the same arc. Owner, 2026-11-05: *"option 1 seems best.
zappy and unpredictable by nature"*, picked over "nearest the victim's core
by owned hops" and "furthest from the attacker's core in pixels". Rejected
by the owner: fork to every tied neighbour (*"makes a 6-hub at 1 Charge
absolutely radiant"*) and splitting a share across ties (*"would require
more duplicating or rounding rules"*).

**Frozen is a boon with two costs** (owner, 2026-11-05, asked for drawbacks
and kept exactly these): *cold passage* — a Frostbite pack crossing it pays no
shed and Afterdrop turns it into a pack aimed at its owner (#1444) — and
*brittle* — a blade contact **shatters one pane**: it removes T Cold (owner,
2026-11-05: *"melee shatter could be a similar "remove T" even?"*, picked over
spending all) and turns the T removed into damage — owner: *"does something
with the count removed to enhance damage, something that works for most
situations (low or hi max hp? maybe %dmg like corruption stack triggers?) …
shattering smth frozen with a melee attack is often a juicy crit (or make it
crit?!? [add +1 crit level])"*; pass lean: the shattering contact gains +1
crit tier (the double-crit curve, #197) and no separate damage number, so it
scales with the blade and never one-shots a defensive freeze. The list is open to more small
costs of that grain (owner: *"possibly we find more small things like what
Cold passage to add later"*) and your own spells walk less far through it.
Rejected: a Frozen node unable to launch attacks, and suspending its stat
contributions. A planting
hit onto a Frozen node is unaffected: a goo arrow carries no reach, its Fuel
lands in full and rests under the ice as an inert keg; the keg's own go-off
at a later landing is a reach, and the glass holds it like any other (owner's
question, 2026-11-05: *"fuel arrows first in a volley: those don't count as
reach or do they? (being inert still)"* — they do not).

What the table enforces: **Cold is anti-reach, priced in reach.** A load
never thaws for free — it pays one unit of reach per Cold stack it melts —
and the other counters are movers and contacts (Heat thaws, a blade
shatters), so an Ice chokepoint is answered with content or with a bigger
hit, never with a stat. **Frozen is a glass ceiling** (owner, 2026-11-05:
*"maybe the "frozen" state sets some kind of glass ceiling for what it
absorbs, which needs to be broken, so it blocks insufficient counts? like
degree-3 node freezes at 4 stacks … then needs a 3~4 reach to break?"*):
T is `graph degree + 1`, so a leaf freezes at 2 and a hub is hard to freeze;
an arriving reach under T is lost whole and melts nothing (owner: *"Glass
holds"*), one at or above T breaks the glass and is then absorbed one for one
(owner picked this over "breaks and passes whole"). Reflecting a sub-T reach
back at the attacker was rejected (owner: *"reflect: too powerful, esp being
as cheap as 2 Cold on a leaf node"*). A reach unit is one radius step, one
arc or one remaining hop, so a spell walk reads the same: its remaining hops
are the reach it brings. A Cold arrow onto a charged or fuelled node spreads
Cold along the arcs or into the disc — Lightning carrying Ice is a feature
that needs no rule of its own.

## Derived states: Frozen, Burning, Shocked (owner, 2026-11-06)

A state is Medium ≥ T, remembers nothing, is side-less like its medium, and
has five cells: what it does to reach arriving, to **travel through the
node**, on the world tick, what it costs the holder, what breaks it. Frozen
fills all five (§ Pair rules). **Shocked already existed under another
name**: #1733 round 3's *critical Charge* (Charge > graph degree) is Charge
≥ T exactly, so its landing cell — every neighbour struck plus leaps growing
with the excess — is built into the arc rule; naming it collapses two facts
into one. Burning's landing cell is ignition (§ Temperature).

**The travel cell completes the triad** (owner, 2026-11-06: *"picture A
sounds very good. also in some sense: elec - hops -> 1D (lines); fire - discs
-> 2D; cold - point -> 0D. it checks out"*). Each element is one mode's
native reach made terrain, and its state is that reach's verb on travel:

| State | Dimension | Travel verb | Spends |
|---|---|---|---|
| **Frozen** | 0D, a point | a path **ends**: hops, chains and arcs stop here (the Frostbite toll, #1444, is the one exception) | nothing; the glass is § Pair rules |
| **Shocked** | 1D, a line | a path **conducts**: a spell walk or an arc entering a Shocked node leaves it without spending a hop — a line of Shocked nodes is a wire for anyone's magic | one Charge per pass-through |
| **Burning** | 2D, a disc | a disc **re-blasts**: a blast whose disc covers a Burning node blasts again from it at the same size with no Fuel needed (backdraft) | Heat down to T − 1, so the node leaves Burning |

Leaf (T 2): wires and backdrafts are cheap along chains; a degree-5 hub
(T 6) rarely qualifies, so corridors conduct and hubs do not. Both verbs are
side-less: your own cast conducts through the enemy's wire, your own blast
backdrafts off your own Burning node. Rejected for v1 (offered as picture B):
Burning denying allocation while it burns, Shocked self-discharging on the
tick at any Charge ≥ T (the tick discharge returns, scoped to the excess
band, below).

**Burning is a light source** (owner, 2026-11-06: *"burning being a light
source does sound clever, could be one of the cells filled by burning"*): a
Burning node is visible through fog to every entity and reveals its
neighbours — a VisionSystem fact, no combat rule. A Shocked "crackle"
revealing charged nodes within leap radius is parked as minor (owner:
*"likely minor?"*, *"more related to the `sensor_range` system, just not sure
how"*).

**The excess band: a second state above the cap** (owner, 2026-11-06: *"a
2nd "post cap" state sounds good too … the excess is there but burns off
quickly. like over-limit portion either triggers some collapse / expunge
trading it for damage (or nothing if unallocated) or it spreads out, or gets
chunked for bonus damage next incoming hit … or a mix of all of these, each
fitting to the status effect"*). The cap k × T is **soft**: stacks past it
exist as the *excess*, decay fast (a per-def rate, knob), and do one thing
per element — the owner's earlier ladder (*"ramping up fire der states to
blaze to inferno"*) realised as one threshold at the cap rather than at 2T
and 3T. The excess is only stacks above a threshold, so a state still
remembers nothing. Pass proposals for the three verbs, each pairing with its
element's travel verb; the owner authored Ice's:

| Excess | Verb (pass proposal unless quoted) |
|---|---|
| **Deep freeze** (Cold past cap) | owner: *"deep-freeze stacks dealing bonus damage on breaking ice and get removed along with it"* — a shatter removes T plus the whole excess and the excess adds to the shatter's damage; overfreezing a chokepoint is the kiter's risk |
| **Blaze** (Heat past cap) | owner's direction *"excess-fire spreading faster"*: the excess portion flows to every neighbour each tick with no dead band (Metropolis without the floor), a flare that lights neighbouring leaves and settles in a tick or two; onto unallocated ground it is deleted as any Heat |
| **Supercharge** (Charge past cap) | owner: *"god knows what"* — pass: the excess arcs out on the world tick as a terrain hit, one arc per excess stack, spending the excess; Charge up to the cap is a wire you lay, past it leaks on the clock |

The "chunked for the next incoming hit" shape is lawful only as the excess
itself being the stored amount (deep freeze is exactly that); a separate
charged-up bonus would be a count, not a state.

## Temperature: Heat and Cold are one flow (owner, 2026-11-04/05)

Exactly one pair nets: **Heat against Cold**. Owner, 2026-11-05, on whether
the two enter one formula literally: *"option 1, 100%. hell yeah"*. Each
world turn every node has a signed temperature `t = heat − cold`; the
Metropolis rule of #1660 round 2 runs on `t` from one snapshot, and the
result is written back as Heat where positive and Cold where negative. A hot
node beside a frozen one exchanges along the edge and cancels on both sides,
so the netting is the diffusion itself; the per-landing `min(heat, cold)` at
settle is the same rule applied to a rider. Sinks stay per member: positive
flow onto unallocated ground is deleted (Heat dies out, #1660), negative
rests (cold ground). Frozen ends when Cold drops under T; **Burning** is its
mirror — Heat ≥ T, same T, derived, never saved — and **Burning is what
ignites**: a keg goes off only while its node is Burning (owner, 2026-11-05,
*"Burning ignites"*, picked over "any Heat ignites" of #1660 round 2 and over
"H ≥ F"). Below T a keg is warm and inert; a leaf (T 2) lights from two Heat,
a degree-5 hub needs six, so hubs are hard to blow and tips burn bright. Spend
and power stay #1660's: min(heat, fuel) Fuel is spent at the node's Fuel as
power, Heat stays, so a Burning keg goes off again next tick. The door the
owner kept open (*"a bespoke twist or tweaked T value later for Burn. or
extinguish mechanics"*) stays open.

**The world clock.** Diffusion, decay of terrain and the terrain settle run
on the world turn as built (owner, 2026-11-05: *"option 1"*) — today it fires
once every N played turn ends, N = living initiative carriers, reproduced on
every peer — over a **temperature index** of the nodes holding Heat or Cold
(the `_lingering` registry's shape), never a walk of the graph: 3k hot nodes
at mean degree 3 is ~9k integer ops a step, under a frame. Steps per world
turn is an exported knob (pass default 1). The owner wants the world turn's
own rate revisited: *"possibly revise the rate at which the world clock
ticks. like maybe speed it up with the number of entities (but not linearly?
idk)"* — pass knob: a world turn every `ceil(sqrt(N))` played turn ends
instead of every N (2 entities: every 2; 4: every 2; 9: every 3), tentative,
easy to change, and it moves the turnless hosts and lingering rows that
already ride that clock. Rejected: an initiative clock (a new seam in
TurnManager plus a resync row), per-node staggered clocks (the one-snapshot
Metropolis rule needs one snapshot).

Everything else coexists. A load never thaws for free (it pays in reach,
§ The reach rule). Fuel and Cold coexist: a frozen keg nobody can set off
until it is thawed or cracked. Movers never fight movers — owner,
2026-11-04: *"Heat & Cold don't make sense together. frostBITE is an
ailment"* — so Heat never touches a Frostbite pack. Charge has no opposite;
a reach into Cold is absorbed, not netted. Rejected: Fuel damped by Cold
(terrain fighting terrain with nobody acting).

## Three things wear the word "explosive" (pass clarification, 2026-11-04)

Owner: *"fuel defensive: explode (trigger aoe reach), fuel rider: splodes
(spreads) or plants?? (adds fuel??) or is that Magic making an exception …
i confuse myself"*. No status has an offensive and a defensive face; three
different rows share the old word, on every facet alike:

| | Row | What happens | Plants |
|---|---|---|---|
| "infuse Explosive to make it AoE" | Fire **reach** row (the element slot, or an element arrow / vertex) | the hit itself blasts at landing | nothing |
| "goo arrow" | Fuel **ride** row | Fuel is added to the landing node; the planting hit never trips it | Fuel |
| "a fuelled node" | the medium on the node | any later landing blasts it, Fuel spent | — |

Poison has the second and a third of its own ("poison on a node ticks");
the only novelty is that a medium reacts to *landings* where a mover reacts
to a *clock*. There is no Magic exception: an arrow with a Fire reach row
blasts exactly as an infused cast does.

**Why Ice reads the cast and the others read the node.** Fire and Lightning
reach by *adding* copies, and a copy needs a node to be added from, so they
are read at every landing. Ice reaches by *removing* copies, and the only
copies that exist to remove are the cast's own walk, so it is read once,
from the cast — at the seed landing's read phase (`hops_remaining`), so the
three phases still hold. An arrow or a blade has no walk, so an Ice reach row
on it does nothing; their Ice faces are Cold ride rows. Anti-reach, not an
exception.

## Vocabulary guard (owner, 2026-11-04: *"stay mindful of concepts drifting"*)

Riders and infusions were aspects only. An element adds a second thing a hit
can carry, so the words are pinned here and in the matrix Glossary:

| Term | Means | Not |
|---|---|---|
| **Payload** | What a hit delivers: damage plus its riders, any status | where it lands |
| **Reach** | Where a hit lands: a point, a disc, a path | how much it delivers |
| **Load** | The amount of an infused thing a cast carries (ADR 0060's word): an aspect load, an element-status load *or* the one reach load | a node's stacks |
| **Rider** | Plants a status — any status, a medium or mover included (a goo arrow plants Fuel) | an element on the hit |
| **Element on a hit** | The reach entry: sets reach, plants nothing | a rider |
| **Use** | What an intake row's load buys: ride, reach or shape | a slot |
| **Medium / Mover / State** | The three roles in an element's status family (table above) | "the fire status" |
| **Member** | A status of an element, whatever its role: Fuel and Heat are members of Fire; an Element Matrix row is a member row; a member keys its own facets (`fuel_resistance`) (owner, 2026-11-05: *"member"*) | a facet (arrow / blade / spell) or a role |
| **Fire / Heat / Burn** | The element (count and reach) / its mover status / at most the word for Heat ticking | three things a hit can carry |

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
- **Play-situation review, 2026-11-05** (four Sonnet lenses, rated by each
  other; full text in `docs/handoffs/elements-play-situations.md`). Items
  1–4 and 6's fold half are settled above. Still wanting a call: (5) "a
  planting hit never trips its medium" vs "read sees the pre-hit node" —
  pass lean: a hit carrying a ride row for medium X is exempt from X's
  go-off at its own landing only.
- **Adversarial review, 2026-11-05** (full list in `docs/handoffs/elements.md`),
  the items that need an owner call before any element issue is `Ready`:
  (a) **row keys**: `Infusion.load_of` and `StatusRoster.by_concept` key on
  one concept id, so a Fuel ride row, a Heat ride row and a Fire reach row
  cannot all key on `fire` — #1660's B2 (*"intake row names which of its
  aspect's statuses it plants"*) is the fix and must be carried into the
  slot design; (b) **facet ids**: `<x>_stacks_per_hit` / `<x>_resistance`
  key per status (#1660 A1), so a member keys on itself (`fuel_`, `heat_`),
  while the count needs a new `StatDef.Role` (`fire` is not `fire_aspect`);
  (c) **ADR 0073 vs 0070**: 0073 wrote the use as a closed set where 0070
  made it an open set of `LoadUse` classes, and `CleanseUse` fits none of
  its three words — a short superseding ADR, since an ADR is never edited;
  (d) closed 2026-11-08 by the cost law (pass inference from the owner's
  "everything rides"; confirm) (§ The threshold model): copies carry
  everything, chained links included, flat, and the per-copy spend is the brake,
  so #1735 fork 1 is *flat*, as built; (e) **Ice raising seed payload** strains "the slot buys reach only";
  (f) **Charge** collides with explosive's `charge` tag and `vertex_charges`
  — the #1716 r2 retag to `fuel` is the plan and must be in the first Fire
  issue; (h) a rider map keyed by id merges a BEFORE
  rider with an AFTER copy of the same id — coalescing is still #1741's open
  NOTE, not an owner call.
- **Arc mirror** (owner idea, 2026-11-05, parked): *"maybe when a nb tries
  to emit a lightning reach it reflects it? maybe not"* — an arc aimed at a
  Frozen node bouncing back onto its emitter instead of grounding. Decide at
  Lightning's spec once the pick rule exists (a Frozen + Charged node is
  already the top pick, so this would make it a trap).
- **Greed under the new vocabulary** (#1659, owner 2026-11-03: the "stacks
  outlive the kill" direction is *"a lame exploit already on paper"* — kill
  for the XP, the enemy retakes, kill again at the same count). Greed is an
  aspect status, so sided; the cursed-gold feel needs a carrier. Shapes on
  the table: the stacks jump to the killing node (hot potato), spent on kill
  (as built), or ride the relic (#1662). Unpicked.
- The arc pick rule's numbers (leap radius per excess Charge) and
  radius-per-load: #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- **Burning's disc under the cost law**: a hop ball (cost = the nodes in
  it, ≈ degree at level 1, the 4-times fact holds) or the Euclidean disc of
  § The reach triad (cost depends on local density)?
- **Ice concentrate under terrain-only reach** (§ The threshold model): is
  the cast-time hops-for-payload trade a `shape` use that survives, or does an
  Ice infusion become a Cold ride row like Fire's and Lightning's?
- **Spike pop docs vs code**: owner, 2026-11-08, *"The existing one just pops
  the one, docs may be stale"* — `BladePopResolver`'s header and
  `docs/domain/ai-blade-rollout.md` describe severing past a pop; check
  against the code at the Ice spec.
