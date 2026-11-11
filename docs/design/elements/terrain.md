---
status: settling
---

# Elements — terrain: the threshold, Catalyst, cooling, temperature

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

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

## Catalyst: a converter, in no family (owner, 2026-11-09)

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
and a blast's copies land on hostile allocated nodes anyway). **Catalyst
converts the element stacks that land with it** (owner, 2026-11-11: *"On
second thought i think catalyst should not pay attention to primary
attributes and *only* consider cold heat charge stacks landing as siblings
… So just those riders or however else such a stack lands."*): when Heat,
Cold or Charge stacks land on a node holding Catalyst — a hit's or a copy's
riders, an arc's transferred Charge, however else a stack lands — the node's
whole Catalyst store converts 1:1 into them (ratio 1:1 a knob), so 3
Catalyst plus an incoming 2 Heat is 5 Heat on the node. Stacks of more than
one element split the store **pro rata** over the landing stacks, largest
remainder first, so the parts sum to the store and no stack is minted
(owner, 2026-11-11: *"And besides that exactly as option 1, good remainder
distribution setup except what if 3 catalyst (or 1) gets hit by N:N ?"*):
1 Heat + 2 Charge landing on 3 Catalyst converts it 1:2. **A tied leftover
stays Catalyst** (owner, 2026-11-11, picked *odd stack stays Catalyst*):
what divides evenly converts, and a leftover stack whose remainders tie
stays on the node as Catalyst, so 1 Catalyst hit by 1 Heat + 1 Charge
converts nothing, and 3 Catalyst hit by the same converts to 1 Heat + 1
Charge with 1 left. The converted stacks join the stacks they came with,
and only stacks that land count: a shape plants nothing ([casting.md](casting.md) § Shape and ride), so a
Fire-shaped cast riding Charge turns the store into Charge, and a hit with
no Heat, Cold or Charge rider converts nothing. The conversion happens in
the **land** phase, so [hit-resolution.md](hit-resolution.md) § Landing resolution's order stands: the converted
stacks count toward this hit's primed-ness and power. **Colouring** (owner,
2026-11-09: *"option 1. or: also when "igniting"? in
the broadest sense like when enough Heat turns into Burning (through flow,
hits already covered), or when Cold turns into Frozen, or when Charge turns
into Shocked? still element-symmetric right?"*). Owner call, 2026-11-09,
picked *hits and priming*: the store converts when element stacks land on
its node (above, land phase) and when the node primes, its stack crossing T
into Burning, Frozen or Shocked by any route, read at settle, the whole
store into that element. Flow below T never colours it: diffusion is not a
landing. Priming stays beside the pro-rata landing rule (owner, 2026-11-11,
picked *landing + priming*: a node crossing T converts its whole store into
the element it primed into; flow below T still never converts). The rule is symmetric; in practice only temperature reaches T without a hit, since Charge never flows and an arc's
copy is a hit, which is Charge's "stays put" character, not a rule. A
landing that splits the store and also primes the node (tentative, not the
owner's): the split happens at land, and the priming at settle converts the
whole store still left, a tied leftover, into the element it primed into. A goo
arrow landing on an already-primed node lands no Heat, Cold or Charge and
converts nothing: it is an ordinary trigger, the blast goes off at the node's current excess
and its copies carry the Catalyst rider over the disc (barrels laid where the
blast reached), while the Catalyst on the node itself waits for the next
element. **The trade** (owner, 2026-11-09: *"this is turning into a real
chemistry question. both options have something going for them. i think
option 1 sounds best for now. option 2 is more like the Greed's "slice"
mechanics but that was mostly needed to make multi-status payloads play nice.
and iff we decide a hit can have at 0 or 1 Element associated with it then we
don't need the "slice" part and can just consume all"*): the whole store, 1:1,
no slice, split pro rata only when stacks of several elements land. It is the
element analogue of Greed: Catalyst multiplies incoming element stacks the way
Greed multiplies aspect stacks, and Greed must not (owner, 2026-11-09: *"in
essence this is almost like what Greed is for Aspect Statuses, but for
Elements (i think Greed shouldn't multiply incoming Heat/Cold/Charge stacks,
but Catalyst may?)"*). Catalyst stays put (no flow) and decays slowly, per
world turn (owner, 2026-11-11, accepted when asked; the rate a knob);
the map's barrels are the Catalyst addon on map nodes, as the Explosive
barrel addon is today. **Catalyst is an
aspect, the Explosive aspect retagged** (owner, 2026-11-09: *"yeahhh exactly
option 1. w/visually like purple crystals or smth instead of black goo"*; the
line behind it: *"Aspects do anything else"*): one status, side-less terrain,
count `catalyst_aspect`, school DEX (where Explosive sits), facets
`catalyst_stacks_per_hit` / `catalyst_resistance`. The goo arrow plants it, a
plain arrow with a Catalyst rider (owner, 2026-11-11: *"Catalyst arrow is
just a regularly hitting arrow with catalyst rider. It plants catalyst
stack(s). Not much different from a poison arrow."*). Two volley shapes: Heat arrows
sustain, each landing adding its own stacks; Catalyst-then-Heat makes the
first Heat landing a big one (3 Catalyst plus 1 Heat on a leaf, T 2, is
Burning at once with excess 2). No node holds Catalyst at a go-off that
matters: it converts at landing (a tied leftover stays inert), so no
world-tick fuse exists.

## Cooling and reading the terrain (owner, 2026-11-08/09)

**Cooling.** Heat is terrain, so it rests on unallocated ground as Cold does;
every warm or cold node decays 1 toward zero per world turn (owner: *"if we
make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it
should eventually cool off"*), Charge likewise. That 1 is the element's rate
below its first band (owner, 2026-11-11, accepted when asked), a knob like
every decay rate; each band
above it answers its own rate ([go-offs.md](go-offs.md) § Derived states), the overflow's fast.
Catalyst decays per world turn too, slowly, its rate a knob. The
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
ground, and the flat decay cools the board (§ Cooling and reading the terrain). Frozen
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
source: the beat's one set of sums, so no timing is added). It lands on a
Frozen node too, where the arc's copy is absorbed: it moves with the spend,
before that node's admit (owner, 2026-11-10, night: *"it resolves before
right? The charge before the frozen check? Should be good so it still applies
any terrain stacks (cold heat charge)"*). Where the spent
Charge goes — the reached node, or the void — is one exported choice on
Lightning's edge go-off, transfer by default. It is Lightning's exception to
the one spend law (ADR 0081 §1, whose rejected "radiating transfer" was
weighed for Burning's disc, where it mirrors diffusion; ADR 0084 §7 records
the reversal for arcs). Consequence to tune against: an interior node
of a wire gets back what it gives, so decay and the conduct cost are what end
a wire. Pass readings, tentative: the conduct cost of a pass-through is still
voided; a transferred stack is treated exactly like the Charge rider an arc
copy lands (same commit, same primed-ness read); Burning and Frozen keep the
void.
**The arc pays for what it reaches** (owner, 2026-11-11, picked *spend
follows landings*): a level-2+ arc that stops at a ring node whose path
ends (a Frozen node that holds, say) spends and transfers Charge only for
the nodes it actually reaches. The Charge of the hops it never makes is not
spent and is not lost into the wall; it stays on the source.

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
count, minus world turns since it was last written, floored at 0). So Charge, which never flows, costs nothing per world turn (Catalyst is an aspect status row, not node state: it keeps its own decay rule, per world turn at its own slow rate). Only the Heat/Cold
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
node stays colourless until Heat, Cold or Charge lands there; a Cold hit or copy deepens the
freeze (an absorbed copy's Cold still lands, converting the store with it), a Heat hit thaws harder. Heat never touches a Frostbite
pack (owner, 2026-11-04: *"Heat & Cold don't make sense together. frostBITE
is an ailment"*). Charge has no opposite. Rejected: Catalyst damped by Cold
(terrain fighting terrain with nobody acting).
