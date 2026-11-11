---
status: settling
---

# Elements — the forge

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

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
| **shape** (bespoke, per spell) | spell-specific: Firecracker's blast waves, Ice concentrate ([casting.md](casting.md) § Ice on a cast) | whichever count it names |

- **No use gives a hit reach.** A shape use may reshape the cast (Ice trades
  hops for payload before it leaves), but reach at a landing is read off
  the node alone.
- **A forge load and the `max_hops` ruling.** The owner, 2026-09-02, on a
  board-wide hop modifier: *"the latter one we should be very careful about,
  and possibly disable entirely until we find a proper way to tune it —
  adding max hops to a spell dramatically alters its performance"*, with the
  conclusion that any propagation tuning is per spread strategy, not a board
  stat (Trailblazer's 999 is a backstop, Cyclone's 8 a limiter). A forge load
  is outside the letter, a per-cast spend on a per-spell intake row with an
  authorable rate that a spell can refuse (as Ice does), but inside the worry:
  "+1 hop" is worth 1 to 15 or more nodes by spell. So a Lightning shape that
  added hops would need a per-spell rate and a refusal for unbounded or
  self-terminating walks; one that makes the *seed* a hop ball never touches
  `max_hops` and is the model ([casting.md](casting.md) § What a point of
  shape buys, probe `tools/disc_reach.py`).
- **A spell carries at most one element, and the forge adds to it or swaps
  it** (owner, 2026-11-09: *"the spell should carry at most one Element
  (fire/cold/lightning) and if a spell already has one, forge can add to it
  (synergy) or replace it for the cast (original cleared, your choice put
  in)"*). So the forge's elemental slot is one element field per cast, not a
  slot count: the same element as the spell's innate one adds load, a
  different one replaces it for the cast. The aspect slots are untouched. The
  owner's own caveat in the same breath: the slot loads Heat, Cold or Charge,
  *"not really things like Fuel"*. Catalyst is not on the element
  axis; it rides as its own row, an aspect ([terrain.md](terrain.md) § Catalyst). Since
  2026-11-10 this field is the cast's *shape* and a second field carries its
  terrain riders ([casting.md](casting.md) § Shape and ride, "Three kinds of slot").
- **Overqualified casting** (owner, 2026-11-10: *"we might just have found a
  mechanic for *overqualified casting*. if casting from a node of, say
  degree N, a spell has min required degree M, if N<M it cannot cast it, if
  N≥M it can cast, and the excess may be used for additional points e.g. 5
  or so per excess degree"*). A node's capacity for a spell is the spell's
  base cap plus a bonus per degree above `min_degree`, one formula; starting
  knobs base 10 (*"maybe 10 is a better starting cap"*, after a first 15)
  and 5 per degree. **The loadout gates the caster** (owner, picked over
  sorting casters by degree and over clamping the loadout to today's pick):
  a loadout of P points is a higher `min_degree` for the source, and among
  the casters that can carry it the pick stays the highest node-local
  `spell_damage`. **While no target is picked, the loadout hides no target**
  (owner, 2026-11-11: *"hiding casters also hides targets and *those* we
  don't wanna hide. But we do want to indicate potential to overclock it."*,
  and: *"And "hide no targets" mostly applies to when no target is picked
  yet (just the spell)."*): every node the spell's eligible casters reach
  stays a target whatever the loadout. **A pip on the target shows the
  overclock potential** (owner, 2026-11-11, picked *pip on targets*:
  *"Pip on target."*): each target an overqualified caster reaches shows
  "+N", its cap above base from the best caster reaching it, red when the
  loadout is above it, still pickable. This amends ADR 0085 §4
  (*"targets light up for those alone"*) and its consequence that a heavier
  loadout reaches fewer targets; ADR 0089 records it.
  **Once a target is picked** the forge knows the range of
  overqualification among the nodes that can fire at it (owner, 2026-11-11:
  *"When target is picked we know the full range of overqualification
  amongst the nodes that can fire at it."*), and the real cap is the best
  capacity among them. **A target whose best cap is below the loadout**
  trims the loadout to that cap when picked, one-shot, in the forge's trim
  order, with a notice (owner, 2026-11-11, picked *trim to its cap*). **The
  trim order is socket order** (owner, 2026-11-11, picked: *"what
  `clamp_infusion` already does today: sockets fill in the order they were
  socketed, each to what it can carry, so the last-socketed lose points
  first"*): every trim in the forge, this one and the way back below, takes
  one point off the last entry of the aspect-slot array and pops the entry
  when it reaches zero, repeating until the loadout fits the cap (owner,
  2026-11-11: *"i mean the aspect slots are just an array right? just pick
  the last element and reduce it, pop if empty"*). **The elemental slots do
  not count towards the cap** (owner, 2026-11-11: *"the Elemental slots dont
  need to count towards the cap"*), so a trim never touches the shape or the
  ride. Such a target
  looks different (owner, 2026-11-11: *"This means that
  "target" should look different too. Like secondary or muted or "not using
  your full spec""*). **A point past the source's cap**: a non-aimed spell
  re-picks its source among the casters that reach the target and can carry
  it, or the socket refuses the point (owner, 2026-11-11: *"most spells use
  no aiming step and repicking is non invasive (they weren't hand picking the
  source anyway)"*); an aimed spell refuses it, since its aim picked the
  source (owner, 2026-11-11: *"aiming does implicitly confirm the
  source"*). **An aimed cast with its aim set locks the caster** (owner,
  2026-11-11: *"In case of an *aimed* cast and the aim is set, the caster is
  locked (while aiming the projected area snaps to casters)"*). Owner idea,
  2026-11-11, not built: *"Non aimed spells don't
  confirm it as visually as they should perhaps an initial trajectory hint
  line like slightly curved upward dashes moving forward etc could help"*.
  **The way back** (owner, 2026-11-10: *"an intuitive way to scale loadout
  back to cap at 0 overqualification"*) is a one-shot trim to the base cap
  (owner, 2026-11-11, accepted when asked), the player's own reset, apart
  from the trim a picked target forces: the next socket write walks
  against the cap in force again. #744's heatmap is the neighbouring display.
  **The AI overclocks by habit** (owner, 2026-11-11, picked *overclock is a
  habit*): every tier fills a loadout to the base cap; filling past base to
  the source's cap, and preferring an overqualified caster, is a habit that
  switches on at FIGHTER and up, as the ladder's rule has it
  (`entity/controller/ai_controller.gd:74`: each rung switches habits on and
  never weighs a trick harder).

  **Two budgets, and a trim worked.** Aspects count towards the point cap
  (base 10, grows with overcast); a Fire shape and a Heat ride share one small
  budget capped by the Fire count ([casting.md](casting.md) § Shape and ride,
  "One budget per element"). The owner, 2026-11-11 18:33: *"so a Heat rider
  counts towards budget capped by fire_element (small budget), aspects e.g.
  Poison count towards the cap (10, can grow) / and for trimming: say i put 5
  poison on slot 1, 5 greed in slot 2, 4 curse in slot 3, for a +1 overcast
  the cap is 15 that's fine. if timming needs to be done, just reduce/pop ..
  slot 3? like eat last slot first until reduced to lowered cap"*. Worked: 5
  Poison + 5 Greed + 4 Curse = 14 fits a cap of 15 (base 10 plus one
  overcast step of 5). At a cap of 10 the trim eats the last slot: Curse 4
  goes to 0 and is popped, total 10. At 8 Curse is popped, then Greed 5 goes
  to 3, total 8. The shape and the ride are never trimmed by it.

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
  *too strong*"*, and the answer from [counts.md](counts.md) § The count is supply is none: the count
  is the only element stat and supply never rides an addon.
- **A blade vertex copies its source node's primed state** (owner,
  2026-11-09: *"copy a burning node and you get a burning blade node (booms).
  copy frozen node -> frozen blade node (detrimental so far, makes blade node
  fragile, but maybe we do add a damage increase to even it out?). copy
  shocked node -> get shocked blade node (zaps/arcs)"*): `BladeVertexFill`
  reads the state at fill as it reads stats; a Burning vertex casts Fire's
  disc on the node it touches, a Shocked vertex casts Lightning's arc on it,
  a Frozen vertex is brittle and snaps on first contact. Your terrain
  travels with your blade.
  - **A vertex's element is a shape on the node it hits** (owner,
    2026-11-11: *"I think it's best read as a shape. Or really it comes down
    to this: do we let *the blade node* explode, or let *the node it hits*
    explode? The latter points to a shape and is easier to do esp if a
    burning blade hitting a burning node causes a *bigger* explosion instead
    of 2 explosions"*; a Shocked vertex follows the same rule): an elemented
    vertex touching a node reads as a cast of that element's shape landing on
    the contact node. The disc is Burning's blast area (radius A × (√power +
    B) × node size, [go-offs.md](go-offs.md) § The trigger and what a go-off pays), centred on the skill node the
    vertex touches and sized by that node (every disc is sized by the node it
    originates from); a Shocked vertex's arc fans out from the touched node
    to its neighbours. Neither is centred on or sized by the blade vertex,
    and neither is the hitbox of the vertex or the node. An unprimed contact
    node takes 1 landing, the contact: a shape alone is not a channel (ADR
    0086 §4), so there is no centre landing.
  - **A Burning vertex on a contact node adds up per channel** (owner,
    2026-11-11: *"Sounds to me like a burning blade node is a similar case
    of a spell with Fire reach hitting a node, they add up per channel"*):
    a Burning vertex touching a node reads as a Fire-shaped cast landing on
    it. On a Burning node the vertex's disc and the node's own go-off add up
    as one Fire channel, one bigger explosion and never two (ADR 0086 §5),
    the same sum as a shape and a primed node of one element ([casting.md](casting.md) § Shape and
    ride). On a Frozen contact node Ice mutes the node's own go-off ([frozen.md](frozen.md) § Pair
    rules) and the vertex's shape runs alone, as a Fire shape does on a
    Frozen node ([casting.md](casting.md) § Shape and ride).
  - **A vertex's shape spends the copy, never the source** (owner,
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
  vertex's shape reads and reaches.
