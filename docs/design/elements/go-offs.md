---
status: settling
---

# Elements — go-offs: the trigger, the reach rule, derived states

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## The trigger and what a go-off pays (owner, 2026-11-08)

**The trigger is a hit on a primed node**, a copy included, so a chain needs
no rule of its own:

| State | A hit on it | Also |
|---|---|---|
| **Burning** | explodes: a disc, power = the excess, a little damage ∝ power, the triggering hit's payload copied over the disc | burns its holder each world turn ∝ the excess, side-blind (owner pick, 2026-11-08) |
| **Shocked** | arcs to **every** neighbour (owner: *"it will arc to *all its neighbors* each time it is hit"*) | conducts a spell walk (§ Derived states) |
| **Frozen** | denies: a copy under the break threshold (on a node with no holder, any copy that does not crit) is absorbed (no damage, no aspect riders; its terrain riders still land), a path ends (0D) — only if the node is still Frozen after those riders (owner, 2026-11-11); a direct hit lands (owner, 2026-11-09, picked *absorbed* over *lands, then stops*); a hit that breaks it lands and walks on | a blade snaps on it if it is still Frozen after the touch's riders (below) |

**What a go-off pays (owner, 2026-11-08): 1 per node it reaches.** One law
across the triad: a trigger pays 1 stack per target its reach touches —
Shocked 1 per neighbour struck (*"charge is more travel-across-edges-ey"*),
Burning 1 per node its disc covers (picked over 1 per blast, whose big disc
underpays a shock — *"at some explosion size, fire would hit basically "all
its nbs" like equalling a shock to each nb"* — and over a radiating transfer,
which mirrors the diffusion flow), Frozen the 0D case turned inward: one
target, the whole store ([frozen.md](frozen.md) § A blade on Frozen). A blast whose disc reaches no
*other* node **does not go off** — no spend (owner: *"possibly extend this rule to
make it cost 0 if it hits nobody?"*, framed as no targets, no go-off, so
every go-off still voids at least one stack — *"there should be at least 1
stack disappearing, possibly more"*). A spend pays its full cost even when
that digs under T (owner picked *dig below T* over clamping at T: a degree-4
node at 9 Charge arcs all four neighbours at cost 4 and drops to 5 — *"would
decharge more rapidly"*). **Primed-ness and power are both read after the
triggering hit's element riders land** ([hit-resolution.md](hit-resolution.md) § Landing resolution; owner,
2026-11-10, replacing the pre-hit read of 2026-11-09): the hit that tips a
node over T sets it off itself. The Heat a hit lands joins its own blast: 1-Heat arrows on a
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

**Size.** Burning's disc is Euclidean, radius = A × (√power + B) × node
radius with A = 2 and B = 1, power = the excess (owner, 2026-11-10, picked
A=2, B=1 over today's ×3, A=2 B=2 and a 1:1 fit; the form is the owner's:
*"`r(p) = A*(sqrt(p) + B) * node_radius` … edge hops have no min distance.
euclidean has. so this might help?"*). The offset keeps a small blast alive:
on 150 px spacing power 1 / 2 / 3 / 4 reaches 0.7 / 2.1 / 3.0 / 3.6 other
nodes and covers every neighbour from power 3 (`tools/disc_reach.py`). It is
one radius with three readers (owner: *"burning's go-off would be the same
AoE radius here, as burning's light source, as well as the proposed "Fire
reach" part of a spell"*): the go-off's disc, Burning's light, and a Fire
shape on a cast ([casting.md](casting.md) § Shape and ride). **Every disc is sized by the node it
originates from** (owner, 2026-11-11: *"Fire disc and burning disc are
basically one and the same. Each disk originating from a node uses that
node's radius for sizing"*): a go-off's by its own node's radius, a Fire
shape's by its seed node's. A and B are knobs, a starter feel and not
a fit to the map (owner: *"we are not here to settle on a shape based on the
procgen settings, we just want to set a good feel of an explosion size, and
if we change procgen node spacing settings later we might or might not tune
the explosion size with it"*). Today's Explosive disc keeps its ×3 until the
retag deletes it.
Shocked's hops: level
L at count > L² × T (owner: *"T = 1 hop, 4T = 2 hops, 9T = 3 hops"*). Knobs.

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
   Heat (or is a bespoke shape use, [forge.md](forge.md) § The forge): early hits warm their
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
cast-time shape (an Ice concentrate) put its mass on the cast, before any
per-landing fold — so `stacks_per_hit` never multiplies with reach (#1733
R2). A hit's copies take the hit's own target mask (the shipped bolt filters
to hostile); only a terrain hit is side-blind, so terrain is side-less but a
landing's copies are not. A copy carries its parent's crit ([hit-resolution.md](hit-resolution.md) § The hit).

**A go-off picks its nodes by shape alone, at every level** (owner,
2026-11-10: *"option 1"*, then *"so far just keep it shape blind always"*):
Burning's disc takes every node inside it and a Shocked arc every node within
its L hops, allocated or not, whoever holds them; the hit's mask then decides
who the copies hurt. So an arc's transferred Charge ([terrain.md](terrain.md), "An arc moves its Charge") lands on empty
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

## Derived states: Frozen, Burning, Shocked (owner, 2026-11-06)

A state is its terrain stack past T, remembers nothing, and is side-less like
its stack. **Shocked** is #1733 round 3's *critical Charge* (every neighbour
struck) under its name; Burning's landing verb is the blast (§ The trigger and what a go-off pays).

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
| **Frozen** | 0D, a point | a path **ends**: hops, chains and arcs stop here, unless an arrival of its generation breaks the ice ([frozen.md](frozen.md) § What breaks the ice; a Frostbite pack, #1444, is the one other exception: cold passage) | nothing |
| **Shocked** | 1D, a line | a path **conducts**: a spell walk entering a Shocked node leaves it without spending a hop — a line of Shocked nodes is a wire for anyone's magic | one Charge per pass-through |
| **Burning** | 2D, a disc | a disc **spreads**: a blast's copy landing on a Burning node sets it off in turn (the trigger) | what a go-off pays (§ The trigger and what a go-off pays) |

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
fast (the overflow band's own rate, knob) and are only stacks above a
threshold, so a state still remembers nothing. The owner's ladder (*"ramping
up fire der states to blaze to inferno"*) is Burning's power growing with the
excess, so Fire and Lightning need no overflow verb. Lead call, tentative
(no owner sentence): for them the overflow band keeps the primed band's
go-off and travel verb, and only its decay differs. Ice keeps one, **deep freeze** (owner:
*"deep-freeze stacks dealing bonus damage on breaking ice and get removed
along with it"*): the shatter spends the overflow with the rest of the excess
(§ The trigger and what a go-off pays). "Chunked for the next incoming hit" is lawful only
as the stack itself being the stored amount, as deep freeze is; a separate
charged-up bonus would be a count, not a state.

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
| Ranged | DEX | **point** — a target is 0-dimensional | Ice | Frozen denies its reach and ends its path; a blade vertex on it snaps unless its own riders thaw it ([frozen.md](frozen.md) § A blade on Frozen), so melee meets Ice in the counters; on a cast, concentrate ([casting.md](casting.md) § Ice on a cast) |
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
