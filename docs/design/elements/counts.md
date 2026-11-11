---
status: settling
---

# Elements — one count, a family of statuses

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## One count, a family of statuses with fixed roles (owner, 2026-11-04/08)

An element is one count on the entity and a short family of statuses on
nodes. Nobody points at "the" fire status; the **roles** are what you point
at (owner, 2026-11-04: *"that table looks very good, should be persisted"*).

| Element | Count (entity) | Terrain stack — side-less, inert up to T | Beside it | Primed state — past T, derived |
|---|---|---|---|---|
| Fire | `fire_element` (shown "Fire attunement") | **Heat** | none; Catalyst ([terrain.md](terrain.md) § Catalyst) sits beside every element, in no family | **Burning** |
| Ice | `ice_element` | **Cold** (owner, 2026-11-05: *"Cold i think. Frozen is a different effect, derived by Cold count (and degree) … frost sounds too "already being a DoT""*) | **Frostbite**, the mover: #1444's inward pack, sided, hurts | **Frozen** |
| Lightning | `lightning_element` | **Charge** | none in v1 (owner, 2026-11-04: *"Fun but maybe start with just the 1"*) | **Shocked**, #1733 round 3's *critical Charge* under its name |

- **The count never ticks on anyone.** A mover is an ordinary sided status
  that clears with its owner like Poison does; terrain hurts only through its
  primed state (a blast, Burning's burn).
- **Terrain is side-less.** A terrain stack rests on a node
  regardless of owner, survives kills, retakes and deallocs, and leaves by
  being *spent* (a go-off spends its own node's stacks), by decay (per-def,
  ADR 0048; [terrain.md](terrain.md) § Cooling and reading the terrain) or by a cleanse. **A holder's
  death changes nothing**: death is not a hit and terrain cannot see owners
  (owner, 2026-11-08, picked *nothing — terrain persists* over a terrain hit
  per primed node; #1660's "death blasts first" is pre-threshold history).
  The battlefield a fight built stays dangerous for whoever retakes it. Heat and Cold
  flow as one signed `t` ([terrain.md](terrain.md) § Temperature) and rest on unallocated ground; Charge
  stays put. Catalyst is not terrain: an aspect status, allocated nodes only
  ([terrain.md](terrain.md) § Catalyst). Owner, 2026-11-05, on a capped wall beside bare
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
  so a deeper-staked node holds more terrain and bare ground
  (`stake_level` 1) gives k = 3. `stake_ceiling` is 3 unless raised, so k runs 3–5; a leaf
  (T 2) holds 6–10, a degree-5 hub (T 10) 30–50, which late counts (20–50)
  can fill. The cap is soft: stacks past it are the **overflow** ([go-offs.md](go-offs.md) § Derived
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
