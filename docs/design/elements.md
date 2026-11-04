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
(6), a bunch of aspects (poison, curse, hex, etc etc it goes on), an elemental
composition or affinity [new]"*; 2026-11-04: *"Separate axis sounds good"*.
Elements are **not** a parent of aspects (owner, 2026-11-04: *"elements not
being parents of aspects makes sense"*), and an aspect never belongs to an
element: Hex is never "lightning-typed".

**An aspect is one status; an element is a family.** Owner, 2026-11-04, on
re-enforcing Aspect:Status as 1:1 with elements the only axis that owns a
status family: *"option 1 sounds very clean"*. The code is 1:1 today
(`aspects/aspect.gd` holds one `status`; thirteen aspects, thirteen defs);
the widening #1694 asked for was only ever for Fire's second status, and Fire
is now wholly an element, so #1694 is unneeded and a test guards the 1:1.
Poison's "does it move" idea (#1657) must therefore be a behaviour of the one
Poison status, never a second one. No Explosive aspect survives: Fuel is
Fire's medium (the ranged-access question this raises is in § Open).

## One count, a family of statuses with fixed roles (owner, 2026-11-04)

An element is one count on the entity and a short family of statuses on
nodes. Nobody points at "the" fire status; the **roles** are what you point
at. Owner: *"that table looks very good, should be persisted"*.

| Element | Count (entity) | Medium — terrain, side-less, gives reach | Mover — sided, hurts, spreads | State — derived, no count of its own |
|---|---|---|---|---|
| Fire | `fire` | **Fuel** (a volatile node) | **Heat** (the Metropolis diffusion locked in #1660 round 2) | none in v1; *Burning* parked |
| Ice | `ice` | **Frost** (what a pack sheds; #1444's resting stacks) | **Frostbite** (#1444's inward pack; the working name *Hypothermia* retires) | **Frozen** = Frost at or above a threshold; the "timer" is Frost decaying back under it |
| Lightning | `lightning` | **Charge** | none in v1 | none in v1; *Shocked* parked |

- **The count never ticks on anyone.** Only movers deal damage, and a mover is
  an ordinary sided status that clears with its owner like Poison does.
- **The medium is terrain.** It rests on a node regardless of owner, survives
  kills, retakes and deallocs, and leaves only by being *spent* (a blast
  spends Fuel, an arc spends Charge, a thaw spends Frost) or cleansed. The
  readability test: *if nobody owned this node, would it still make sense for
  this to be here?* Fuel on an empty node, yes; Poison on an empty node, no.
  Build note: today's `on_dealloc` has CLEAR and LINGER and a death clears
  both; a medium needs a shape that survives death too — a seam for spec time.
- **A state has no count.** It is a threshold on its medium; it does things
  (Frozen blocks travel, #1444) but holds no stacks.
- **Start with one state and no lightning mover** (owner, 2026-11-04: *"Fun
  but maybe start with just the 1"*). Parked: Shocked as Lightning's derived
  state, Burning as Fire's (owner: *"Shocked might be the derived status for
  lightning. Or perhaps burning is so too for fire? Or a sleuth of ramping up
  fire der states to blaze to inferno"*).

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
that's a stretch. 50 sounds *somewhat* reasonable for late late game …)
everything starts small. the inner-core mini skill tree, i envision, would be
one of the primary sources of adding +1..N modifiers to aspects, alongside
map-found modifiers, or stolen mods from slain enemies"*. Every rate that
reads a count is therefore an int:int affinity (ADR 0060), never "one count,
one hop".

## The hit: damage, riders, reach (owner, 2026-11-04)

A hit has three kinds of entry, and the first two are its **payload**:

| Entry | Shape | Lands as |
|---|---|---|
| **damage** | one number | HP loss |
| **riders** | status id → stacks, one entry per id (#1733 R1) | statuses planted — aspect statuses and element statuses alike |
| **reach** | one `(element, load)` | *where* the payload is copied; resolved first |

A hit also crits once, as its own fact, before any of its payload lands, and
every rider and every reach copy carries that crit (#1741, built 2026-11-04).
The reach entry does not change this: a blast copy crits iff its parent did.

An element status (Fuel, Heat, Frost, Frostbite, Charge) rides exactly as
Poison rides; it differs only in which count caps it. Owner, on the hit's
three entry kinds with one rider map: held, conditional on aspects being 1:1
(*"depends on the status cardinality maybe"*), which the section above
settles. There is no fourth entry: anything new is a number that lands
(payload) or a rule about where it lands (reach).

**Which element statuses ride.** Every counted role — medium and mover — can
be a rider row (a goo arrow plants Fuel, an ice spell plants Frost on the
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
- For arrows and blades the same formula applies with no per-cast choice: an
  element arrow or an element addon vertex carries `innate + floor(count ×
  affinity)` of its named use. One formula across the three facets.

## The reach rule (pass proposal, 2026-11-04, from the owner's atomics)

**A hit's reach is set by the element it carries plus the element resting on
the node it lands on. Its payload is copied to every node reached at one
share. A medium that gives reach is spent by the reach it gives; the hit's
own load is not.** Frost gives no reach, so a hit spends none of it: Frost
is spent only by its counters (a thaw, a shatter, the Frostbite toll of
#1444). That asymmetry is the point — a frozen chokepoint holds against every
arc and blast that lands on it, and costs its owner nothing until Fire or a
blade arrives.

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
laying Frost on a chokepoint — the player control #1716 asks for) is a `ride`
row like any rider. The shipped rule stays: a hit that plants a medium does
not trip it.

**Chain reactions** are bounded (#1733 R3): a copied hit landing on a node
that holds a medium spends it and reaches again from there, once per node per
attack, at its parent's share — a geometric cap however much Fuel is on the
board. **Ignition** (#1696, Heat meeting Fuel) is one trigger among several,
no longer the only route to a blast.

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
hops is wasted; a 0-hop spell has nothing to trade. Open: the knob's shape
(one number per spell vs the measured ladder).

## Landing resolution (pass proposal, 2026-11-04)

Three phases per landing, each a pure function of one snapshot, so no rider
order ever matters (#1733 R4, R5):

1. **Read.** Reach is computed from the hit's reach entry plus the node's
   mediums *as they were before this hit*. The Frozen check is here.
2. **Land.** Damage and every rider are added, aspect and element statuses
   alike. Nothing reacts during land.
3. **Settle.** One pure function of the node as it now stands: the Heat ×
   Frost netting, the mediums the read phase charged are spent, and the copies go
   out to the reached nodes — each running its own read, land, settle under
   the once-per-node-per-attack cap.

A hit carrying +1 Heat onto a 5-Frost node is read against 5, lands, and
leaves 4: it thaws for the *next* hit, never for itself. The same settle runs
after every world-turn tick, which is how #1660 already framed ignition.

**Dual reach** resolves by the read phase alone. A node holding both Charge
and Fuel, or a fire-loaded hit on a charged node: every reach source present
at read time fires, each spends its own medium, the hit's load spends
nothing; a node inside the disc that an arc also reaches takes one copy per
reach (R3). An Ice-loaded cast landing on a charged node has no reach entry
at landing (Ice was spent on the spell's hops at cast time), so Charge arcs
as it always does.

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
| Ranged | DEX | **point** — a target is 0-dimensional | Ice | concentrate: a cast trades hops for seed payload; on the board, a hit lands on a Frozen node and never leaves it (an arc grounds, a blast sinks, a hop walk ends). A blade is the one hit that answers back: contact shatters (#1444), so melee meets Ice in the counters, not in the reach |
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

| On the node ↓ / arriving → | a Fire-loaded hit | a Lightning-loaded hit | an arc landing | a Heat rider or diffusion | a Frost rider | a Frostbite pack | a blade |
|---|---|---|---|---|---|---|---|
| **Fuel** | blast, radius from Fuel plus load | arcs from load, then blast | blast — an arc is a landing | ignition (#1696), spends min(heat, fuel) | blast, Frost copied into the disc | — | blast on contact (#1660 R2) |
| **Charge** | arcs from Charge, then the blast | arcs from Charge plus load, Charge absorbed (#1733) | arcs | arcs if a rider, nothing if diffusion | arcs, Frost copied along | — | arcs |
| **Frost under T** | lands, **no thaw** (a load is unspent, so a thaw by load would be free) | arcs from load | chain continues | nets: thaw | adds | pays the toll: Frost sheds first (#1444) | drags (#1444) |
| **Frozen** | lands, load inert | lands, load inert | grounds: lands, chain ends, no Frost spent | nets; unfreezes for the next landing | adds | toll, a free hop if deep enough | shatters (#1444) |

What the table enforces: **a hit's element load sets reach and never counts
as a counter**; the counters are movers and contacts (Heat thaws, a blade
shatters, an arc sparks), so an Ice chokepoint is answered with content,
never with a stat. A Frost arrow onto a charged or fuelled node spreads Frost
along the arcs or into the disc — Lightning carrying Ice is a feature that
needs no rule of its own.

## Cancellation: one pair (owner, 2026-11-04)

Exactly one pair nets: **Heat against Frost**, both losing `min(heat,
frost)` in every settle, order independent; Frozen ends when Frost drops
under its threshold. Everything else coexists. A load never thaws (unspent,
so it would be free). Fuel and Frost coexist: a frozen keg nobody can set
off until it is thawed. Movers never fight movers — owner: *"Heat & Cold
don't make sense together. frostBITE is an ailment"* — so Heat never touches
a Frostbite pack. Charge has no opposite; Frozen grounds an arc without
spending Frost. Rejected: Fuel damped by Frost (terrain fighting terrain with
nobody acting).

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
on it does nothing; their Ice faces are Frost ride rows. Anti-reach, not an
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
  own lower cap; whether that cap is a knob or a stat is open. **A name for
  "a status of an element"** is wanted (owner): pass proposal *member* —
  Fuel is a member of Fire, an Element Matrix row is a member row; *facet*
  (arrow / blade / spell) and *role* (medium / mover / state) stay what they
  are.
- **Landing resolution** (read / land / settle, above) and dual reach are
  pass proposals still awaiting the owner; they go to an ADR only once held.
- **Ice pricing knob**: one number per spell vs the measured ladder, above.
- **Greed under the new vocabulary** (#1659, owner 2026-11-03: the "stacks
  outlive the kill" direction is *"a lame exploit already on paper"* — kill
  for the XP, the enemy retakes, kill again at the same count). Greed is an
  aspect status, so sided; the cursed-gold feel needs a carrier. Shapes on
  the table: the stacks jump to the killing node (hot potato), spent on kill
  (as built), or ride the relic (#1662). Unpicked.
- The arc pick rule and radius-per-load numbers: #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- Shocked / Burning, and a fire ladder (blaze, inferno): parked above.
