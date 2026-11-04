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

The split of labour: **aspects feed payload, elements feed reach.** A hit
carries damage plus aspect riders (its payload) and lands somewhere (its
reach). The two never read each other.

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

What falls out: the count reads the same for an arrow, a blade vertex and a
spell hit (*"how much reach every hit I make carries"*), and a build with
zero in every element is untouched. **Planting** a medium (a goo arrow laying
Fuel, an ice spell laying Frost on a chokepoint — the player control #1716
asks for) is content: a rider that plants the medium status, like any rider.
The shipped rule stays: a hit that plants a medium does not trip it.

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

## The reach triad (pass proposal, 2026-11-04; owner asked for the shape)

Owner, 2026-11-04: *"1. Melee - STR - AoE - explosive (fuel = AoE) - fire …
2. Ranged - DEX - single target - … - …ice? … 3. Magic - INT - edge hops based
propagation (like 90% of the time) - lightning. Make sense? Canonicalize this
somehow? What shape is this here exactly?"*

The shape: **each element is one attack mode's native reach, made portable.**
There are three reaches a hit can have on a graph — a disc, a path, a point —
and each attack mode is born with one. An element lets any mode borrow it
(Fire, Lightning) or impose it on the board (Ice).

| Mode | School | Native reach | Element | What the medium does to a hit |
|---|---|---|---|---|
| Melee | STR | **disc** — a blade sweeps a hurtbox | Fire | replicate into a disc |
| Ranged | DEX | **point** — a target is 0-dimensional | Ice | insulate: a hit lands on a Frozen node and never leaves it (an arc grounds, a blast sinks, a hop walk ends). A blade is the one hit that answers back: contact shatters (#1444), so melee meets Ice in the counters, not in the reach |
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

Nine cells, no type chart. Rows are what rests on the node, columns what
arrives. A cell is one verb, and a blank cell means *nothing special*: the hit
lands and the medium sits.

| On the node ↓ / arriving → | a Fire hit (load or Heat) | a Lightning hit (load or arc) | a blade | Heat (world turn) | a Frostbite pack |
|---|---|---|---|---|---|
| **Fuel** | blast (ignition if it is Heat, #1696) | blast — an arc is a landing | blast on contact (#1660 R2) | ignition | — |
| **Charge** | arcs, then the blast | arcs, Charge absorbed into the budget (#1733) | arcs | — | — |
| **Frost / Frozen** | Heat nets against Frost and clamps at 0: thaw (#1444). The hit's own fire *load* plants nothing, so it thaws nothing | grounds: lands, chain ends, no Frost spent | shatters when Frozen; drags below the threshold (#1444) | thaw | pays the toll: Frost sheds first (#1444) |

What the table enforces: **a hit's element load sets reach and never counts
as a counter**; the counters are movers and contacts (Heat thaws, a blade
shatters, an arc sparks), so an Ice chokepoint is answered with content,
never with a stat. The one place two mediums meet on one node (Fuel and
Charge together) resolves arcs first and the blast after, each spending its
own medium — the chain cap of #1733 R3 still holds per node per attack.

## Vocabulary guard (owner, 2026-11-04: *"stay mindful of concepts drifting"*)

Riders and infusions were aspects only. An element adds a second thing a hit
can carry, so the words are pinned here and in the matrix Glossary:

| Term | Means | Not |
|---|---|---|
| **Payload** | What a hit delivers: damage plus its aspect riders | where it lands |
| **Reach** | Where a hit lands: a point, a disc, a path | how much it delivers |
| **Load** | The amount of an infused thing a cast carries (ADR 0060's word); now an aspect load *or* an element load | a node's stacks |
| **Rider** | Plants a status — any status, a medium included (a goo arrow plants Fuel) | an element on the hit |
| **Element on a hit** | Sets reach, plants nothing | a rider |
| **Medium / Mover / State** | The three roles in an element's status family (table above) | "the fire status" |

## Acquisition (owner sketches, 2026-11-03; nothing picked)

Both sources every stat already has: **permanent, slow** (an inner-tree ring
or sector, or a periodic *"+1 to <element of choice | choose 1 el out of 3
cards>"* offer) and **board-temporary** (a keystone: *"a fire keystone that
also supplies heat or fire stacks"* — the Hearth of #1716 round 2, emitting
Heat each world turn and granting fire while held). `apex_inner_tree.md` is
six schools × two aspects today; elements would be a third ring or a
three-spoke tree. Filed against the element hub, not settled here.

## Open

- **How the count becomes a load on a hit that is not a spell.** A spell
  draws from `fire` the way it draws from `poison_aspect`: as infusion supply
  (ADR 0060, load = innate + infused). The doc's line *"how much reach every
  hit I make carries"* reads as if the count were a flat per-hit load instead,
  and that is a different game: every blade vertex of a 30-hit sweep would
  blast, which is exactly the reach-per-hit grain #1733 R2 forbids. Two shapes:
  (a) **the count is supply**, and a hit carries an element only when a face
  loads it — an infusion row, an element arrow, an addon vertex — in parity with
  how an aspect reaches an arrow or a blade today; (b) **the count is the
  load**, every hit carries it, and R2's conservation has to come from the
  medium side alone. Pass lean: (a); it keeps a zero-element build and a
  zero-element *hit* both untouched, and makes "+1 fire" read as "one more to
  infuse", the same sentence an aspect point already says.
- **A hit's element against a Frozen node.** The reach rule says load plus
  medium; insulation says neither moves. Pass lean: **Frozen wins** — the load
  and any other medium on the node are inert, the payload lands once. Written
  into the pair table above; one line to strike if the owner wants a fire-loaded
  hit to thaw by itself (that would make the counter a stat, which the table
  argues against).
- **Greed under the new vocabulary** (#1659, owner 2026-11-03: the "stacks
  outlive the kill" direction is *"a lame exploit already on paper"* — kill
  for the XP, the enemy retakes, kill again at the same count). Greed is an
  aspect status, so sided; the cursed-gold feel needs a carrier. Shapes on
  the table: the stacks jump to the killing node (hot potato), spent on kill
  (as built), or ride the relic (#1662). Unpicked.
- The arc pick rule and radius-per-load numbers: #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- Shocked / Burning, and a fire ladder (blaze, inferno): parked above.
