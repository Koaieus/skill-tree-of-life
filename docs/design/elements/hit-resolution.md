---
status: settling
---

# Elements — the hit and landing resolution

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## The hit: damage and riders (owner, 2026-11-04)

A hit has two kinds of entry, together its **payload**, and no reach of its
own ([terrain.md](terrain.md) § The threshold model):

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
copies and riding landings already do. A hit lands in a fixed order:
terrain riders first, then damage, then the other statuses (owner,
2026-11-11; § Landing resolution).

An element status (Heat, Cold, Frostbite, Charge) rides exactly as
Poison rides; it differs only in which count caps it. Catalyst rides too,
budgeted by its own count. Owner, on one rider
map: held, conditional on aspects being 1:1 (*"depends on the status
cardinality maybe"*), which [elements.md](../elements.md) § The two axes settles. There is no third entry:
anything new is a number that lands (payload); where it lands is the node's.

**Which element statuses ride.** Every counted role — terrain stack, Catalyst,
mover — can be a rider row (a goo arrow plants Catalyst, an ice spell plants
Cold on the chokepoint, a hot arrow plants Heat); a state never rides, it has
no count. The quote that settled the rule, owner, 2026-11-04:
*"if fuel is to be a fire status.. and option 2
says `fire:heat` at exactly one then how could a fuel-planting arrow exist? it
couldn't. so i guess that rules out option 2? option 1 sounds reasonable"*.
One cap per element across its whole family.

## Landing resolution (owner, 2026-11-05)

**Two stages per hit** (owner, 2026-11-09: *"resolve elements first which
settles the reach [as in, total set of targets] for the hit (including
cascades..?) and then resolve the remainder of the hit for each target
(riders, damage?)"*, confirmed as the two stages below; ADR 0082). The
2026-11-05 three phases (*"hold it"*) survive inside stage one, at each node;
the order inside a beat is terrain riders first (stage one), then all of the
beat's damage, then the aspect riders (owner, 2026-11-11, ~16:29: *"Maybe non
elemental riders (curse poison hex etc) land after damage after all. Might be a
simpler split. Curse riders then only take effect on the next hit, which is
fine"*, then, on the beat-scoped version: *"sounds agreeable. also if damage
kills nodes it makes no sense applying statuses after"*) — so a Curse arrow
does not lift its own hit, and a Curse takes effect from the next beat. Every read is a pure
function of one snapshot (#1733 R4); nothing reacts mid-land.

1. **Terrain: elements land, the reach is gathered.** Owner, 2026-11-10,
   replacing the 2026-11-09 pre-hit read now that a cast carries a shape and
   riders as separate things: *"first resolve terrain riders (only:
   heat/cold/charge) - then resolve hit reach + local reach"*. At the node
   the hit lands on: *admit* — an arriving copy is checked against Frozen as
   the node stood before this generation ([frozen.md](frozen.md) § What breaks the ice), and the
   answer gates only its
   damage and aspect riders, what stage two lands; a centre copy (below) is
   never asked (pass reading, tentative: the owner left the option to ask it
   unticked); *land* the element riders, absorbed or not (Catalyst
   converting as they add) and net Heat × Cold; *read* the node's
   primed states and their power from the result — together with the cast's
   shape they are the reach ([casting.md](casting.md) § Shape and ride), and the Frozen path-end and
   break check are here, against the hit's own crit and damage facts; the
   go-offs spend their stacks and name the nodes they reach. **The shatter
   is read here, with the go-offs** (owner, 2026-11-11: *"I think frozen
   shatters (≈go-offs) should ideally resolve in the Reach section along
   with other go-offs like blast or arc do"*). The placement is compelled,
   not only tidy: a shatter changes reach — its paths walk on, the break's
   two extra landings join the target set, its spend rewrites terrain — and
   stage two may not change reach (ADR 0082).
   Each reached node runs the same three steps on the copy's element riders
   under the once-per-node-per-hit cap (per arrow, per blade contact, per
   arrival of a wave), a Frozen node absorbing an under-threshold copy's
   damage and aspect riders while its element riders land; dual reaches
   concatenate (below).
   The result is the hit's whole target set with a share per entry — the
   attack record's blast table, one mark and its copies — before anything
   else lands.
2. **Payload: the remainder lands per target.** For every gathered entry the
   damage, then the aspect riders (Curse, Poison, Hex, Sunder, Wither,
   Bleeding, Marked and the rest), land at that entry's share (a
   concatenated node takes one landing per entry), beat-scoped: within a
   beat, all damage lands before any aspect rider, so every arrival of every
   generation reads the node as it stood before the beat. A node the beat's
   damage depletes (HP 0) takes none of that beat's aspect riders (owner,
   2026-11-11: *"if damage kills nodes it makes no sense applying statuses
   after"*). Nothing in this stage touches a terrain stack, so an aspect
   rider can never change reach.

   Two readings for the partition, *tentative, not the owner's*: a bare
   aspect status with no paired hit (a spell whose landing is only a status)
   counts as an aspect rider, so it lands after the beat's damage and the
   rule stays one predicate, "is it a status"; and a cracked core is not
   depleted (a core never reaches `depleted`, its overflow going to the
   owner's `health` pool), so a status landing on it still falls through to
   the entity host.

A hit carrying +1 Heat onto a 5-Cold node lands it, leaves 4, and is read
against 4: it thaws for itself. A hit carrying +1 Charge onto a node one
short of Shocked arcs from it. A Cold *copy* onto a Frozen node is absorbed
but lands its Cold, so a copy deepens a freeze as a direct hit does. The
order per target in
stage two is damage, then aspect riders (owner, 2026-11-11, ~16:29, reversing
2026-11-10's *keep riders before damage*); terrain riders keep landing first.
The same terrain
settle runs after every world-turn tick.

**Thrown and shown are one formula apart.** Frozen's damage breaker reads
the number the floater shows ([frozen.md](frozen.md) § What breaks the ice),
and between the amount a hit throws and that number sit only the steps of
landing it: the hit's stamped amount (its share in), its basis resolved to
this node's HP (a `% max HP` hit becomes HP of this node), crit multiplied
in, rounded whole once, then mitigation, `max(floor, raw − armor)`, which
TRUE damage skips. The floater and the attack record show that
post-mitigation amount. Block, resistance, Hex and Greed are not on this
path: they change how many stacks a status rider lands, never a damage
amount, so no hit shows one number and breaks the ice at another. The
stage-one read is that same chain on the arrival, against the node as it
stood before the beat, with no rider fold: within a beat no rider moves
armor or floor before the damage lands (ADR 0092 §1-§2).

**What riders after damage cost** (first hit only; every later beat is
unchanged; ADR 0092's Consequences carry Malediction, Rend on armor 0,
Shredder and Hex). Rend on an armor-8 node, its climb target: its 7 damage
under its own 7 Sunder landed 6 when riders went first and lands
`max(5, 7 − 8)` = 5 after, and its "a quarter of the armor" bonus is a
resolve-time term, untouched. Malediction keeps its point, the floor it
leaves. Poison and Bleeding lose nothing (they tick); Marked already lifted
only the hits behind its own; Curse × crit is unchanged. Curse's family role,
*every hit lands again*, holds as every *later* hit. Nothing is gutted: Rend
and Shredder lose the most, and both keep their reason to exist.

**The breaker reads it picked over** (ADR 0092 names each and the driver it
lost on; their costs, on the shipped numbers of [frozen.md](frozen.md) § The
damage breaker's arithmetic, worked):

- *The raw amount as thrown* (ADR 0091 §3): on a 100-HP node with armor 3,
  a Bolt of 12 reads 12, shatters, and floats 9 three times (27 plus the
  burst), and a hit's own Curse raised the floor after the read — the drift
  the owner called gaslighting.
- *Crit and blade only* (no damage breaker): with `crit_chance` 5% a spell
  with no crit condition breaks ice about one cast in twenty; the one
  generic counter to Frozen goes, a cheap leaf freeze grows stronger, and the
  Cold spell's Ice form no longer breaks on damage alone. The cheapest
  build, a deletion.
- *The arrival's own aspect riders land before the read*: read = floater,
  but the dearest build — stage one runs the stack fold (resistance, Hex,
  block) for floor- and armor-moving riders before mitigation, a second
  landing order at Frozen nodes only, a bounded copy of the payload →
  terrain loop the owner called spaghetti (ADR 0091) — and a sibling's Curse
  raises the floor every arrival of the generation is read at, so which
  arrival takes the break's extra landings depends on sibling riders.
- *Frozen takes damage unmitigated* (the named fallback in ADR 0092's
  revisit-when): thrown = read = landed and armor never hardens ice, a flag
  on the gathered entry to build. It favours the attacker by exactly the
  armor wherever there is armor and the defender by the floor's shortfall
  where there is none: owned ice on an armored node turns trap (the Bolt
  above breaks it and lands 3 × 12 = 36 plus the burst where the unfrozen
  node takes 9); Curse and Sunder go blind at the ice, exactly where Frozen
  + Bunker is the stack they answer; a sub-zero floor's heal is off there; a
  slow blade lands 2–3 instead of the floor's 5; the defense card has to grey
  armor and floor, and the AI pricers read the flag or misprice ice.
- *Riders first, armor and floor read from a per-beat snapshot*: the same
  balance with no reorder, but the floater disagrees with the live defense
  card mid-beat.
- *Show the thrown number at the ice* (a floater of `12 (9)`): no rule cost,
  but two numbers, and a Spark on a Cursed node still reads backwards,
  `4 (10)` and no shatter at a threshold of 10.
- *Per-landing order* (each landing's damage, then its own riders): the
  drift comes back one step over, a sibling's or an earlier generation's
  Curse moving a later floater its read never saw; hence the beat scope.

**Build shape (2026-11-09).** Stage one runs when the hit *lands*, not where
landings are compiled: ranged and blade compile every landing before the
first one lands, and only the applier mutates the world (ADR 0079), so a
compile-time resolver would need a ledger mirroring terrain. A gather owns
the once-per-node set and the entry list; a gather hit at the head of the
span is the only thing that touches terrain, and it records its terrain
changes for peers to replay (ADR 0077). Stage two has no class: the existing
compile-and-land path runs per entry. An element answers two questions and
nothing else — *admits* (does an arriving copy land here: Ice) and *go off*
(what is spent, which nodes are reached, at what share: Fire, Lightning,
and Ice's shatter). Pass reading, tentative: the shatter is the triad's 0D
go-off — it triggers on a breaking hit where Burning and Shocked go off on
any hit, spends everything above T, reaches only its own node at the break
count, and its power, the excess, sizes the burst.
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
  landing on the same beat (one wave's arrivals) start from the same
  pre-beat terrain; their element riders land as sums; the go-offs are read
  from that summed terrain and their spends committed together, summed and
  clamped at 0; the nodes reached form the next generation, settled the same
  way. A node is read once per generation, over all that generation's
  arrivals at it, and no path leaves it before that read; at a Frozen node
  that read decides the shatter for every path of the generation ([frozen.md](frozen.md) § What
  breaks the ice; owner, 2026-11-11, *the node settles first*). Pass
  reading, tentative (no owner call): a multi-hop arc (Shocked level 2 and
  up) advances one hop per generation, so a Frozen node on its first ring
  is settled before the arc goes past it. The result never depends on the walk's order, and the routine is the
  one the world-turn tick needs, whose go-offs have no order at all. The
  per-wave `detonated` scope goes. Known consequence: several same-beat
  go-offs each read a deep store at full power before the clamp. **A blade
  follows the same rule** (owner, 2026-11-10, picked *one snapshot* over
  *sequential, as today*): two contacts of one sample on one node are hits of
  one beat, both read the pre-beat store and their spends are summed, so the
  swing keeps no spend ledger; contacts of different samples read the world,
  which already carries the earlier spend.
- **One share scales the whole payload** — damage and every rider's stacks,
  rounded up per rider ([go-offs.md](go-offs.md) § The reach rule's *"at one share"*, taken as
  settled by the pass). Today's stacks-only splash scale and the separate
  shrapnel fraction collapse into one knob per go-off, default 1 since
  2026-11-10 ("Every landing is a whole hit", below), so the round-up is
  idle at the default.
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
  the `Element` def too; pass reading, tentative: Ice's shatter is a third,
  point subclass, the 0D go-off (above). Explosive is not an element, so go-off zero's disc
  rides the Explosive `Aspect` def under the same field name until the
  Catalyst retag deletes it (pass pick, tentative). Lead call, tentative:
  go-off zero keeps today's numbers until that retag, share 0.5 and no
  centre copy. The owner left interim states to the lead rather than
  picking this (2026-11-10, night: *"Tbf i don't care anything about
  intermediate state so long it's all as it should be when all issues are
  done"*).
  Following the whole hit at once instead would double the shipped blast's
  bystander damage (share 0.5 → 1) and give its centre a copy it never
  takes now, re-pointing the shipped explosive tests for an interim state.
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
build keeps it as a knob rather than a structure. **The switch acts on
collateral nodes only** (owner, 2026-11-10, night: *"Deduping: central target
takes 1 + (channels) loads, other nodes besides central take
(share\*channels) total load. Central always more than the collaterals
(reached nodes through a channel)."*): it merges a reached node's entries
and never the hit node's, so the hit node takes 1 + 1 per channel either
way (below) and always more than any collateral. **Switched off** (the
default), a node gathered by two reaches is two entries, each landing the
damage and the aspect riders (owner, 2026-11-10: *"riders twice, payload
twice. charged burning nodes sounds like a dangerous concept"*; its terrain
riders land once, stage one's cap). **Switched on**, that node takes one
landing at share × channels, summed (owner, 2026-11-11, picked *one
landing, summed*: *"If we ever tune the share (e.g. loses a fraction per
hop for Arc or set some sweet spot for AoE disks idk) we'd sum those values
anyway granted that the hits stay the same."*). Every landing is the
payload at a multiplier, its share, and the dedupe sums a node's
multipliers into one landing (the owner's framing, 2026-11-11: *"So
basically they all work on a multiplier for the load?"* — yes). So the
node's total load is unchanged and it is one hit: it can cross Frozen's
flat break threshold where each entry alone would not, and per-landing
effects fire once. Either way, if that node is itself primed its own go-off
fires **once per hit**, not once per entry (owner, 2026-11-10, picked *once
per hit*): the once-per-node set bounds every cascade by node count. **A
cast's shape and a go-off of another element are two reaches under the same
rule** (owner, 2026-11-10, picked *same as dual reach: concatenate*; the
doubt behind it: *"its close nbs might get hit twice (once by fire once by
lghtng)"*): the seed node takes the seed once, in full, plus the go-off's
centre copy (below), and a node inside both the shape's reach and the
go-off's takes one copy per reach. The one dedupe switch covers both cases.

**Two channels at different shares** reaching one node in one generation
land its terrain riders once (stage one's cap), at the larger share's
rounded-up count, `ceil(stacks × share)`, which keeps the result order-free
(*tentative, not the owner's*). At the default share 1 the case does not
arise.

**Every landing is a whole hit, and a go-off lands on its own node too**
(owner, 2026-11-10, night, picked over share ½ with the centre excluded and
over share 1 with the centre excluded: *"the hit hits *and* the blast hits,
and the arc hits, and share 1 means no rounding for rider stacks"*). The
share's default is 1, and each channel that goes off lands one more payload
on the node it goes off from, its centre copy: the hit node takes 1 + 1 per
channel, a node one channel reaches takes 1, a node both reach takes 2 — so
the target is never hit less than its bystanders (2 against 1, 3 against 2).
A centre copy carries the go-off's own damage as well as the payload, as a
reached node's copy does (owner, 2026-11-10, night, accepted when asked).
Owner on the result: *"damage doubles or triples, neat. Frozen should match
that but we can tune it to do so i guess. and crits can stack on top of
that"*, and on where it leads: *"nodes with HP in the 1000s to be taken
down — iff you debuff them properly first"*. Frozen matches by counting its
break as 2 channels ([frozen.md](frozen.md) § What breaks the ice). Terrain riders still land once
per node per hit (stage one's cap), so the extra landings carry damage and
aspect riders only and a fire does not feed itself. "No other node reached, no go-off"
stands as worded: the centre landing happens only when the go-off does, so a blade vertex's shape on an unprimed contact node adds none. The
share stays a knob per go-off and the dedupe a switch that never merges the
hit node's landings (Dual reach, above). **A cast's shape alone is not a
channel for the seed** (owner, 2026-11-10: *"the shape for
spells hmmm i think that one shouldn't count"*): a shaped cast on an
unprimed node lands once on its seed, and the extra landing comes only from
a primed node going off. A shape added into a primed node's go-off of the
same element is that node's go-off, one channel, so the seed takes 2 (owner,
2026-11-11, accepted when asked). ADR 0086 records the whole-hit landing
counts, the break channel and the dedupe; ADR 0090 the break's count of 2.
