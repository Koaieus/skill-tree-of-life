---
status: settling
---

# Elements — open questions

> Part of the elements design set; hub and file map: [../elements.md](../elements.md).
> The target model for the #1716 drop, not built: what is built is in `docs/domain/`. Owner calls are dated and quoted; a pass reading says so.

## Open

- **Catalyst, settled and what remains** (owner, 2026-11-09). Settled in [terrain.md](terrain.md)
  § Catalyst: Catalyst is one element-generic converter in no family, the
  world-tick fuse is dropped (it converts at landing, so no node holds it
  at a go-off). The rejected alternative, in the owner's words: *"either this, OR
  we add an "inert fuel-like buildup" status for Ice and Lightning too so each
  has one of them. but i think that'd just be a less comprehensible, more
  tedious and less fluent way to go about this and that getting just 1
    catalyzing status for all elements would work better."*
  - **Settled 2026-11-09 (owner quotes in [terrain.md](terrain.md) § Catalyst):** supply
    is an aspect (the Explosive aspect retagged, DEX), colouring is the
    element stacks that land plus priming, the trade is the whole store at
    1:1 with no slice. These
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
    lean, quoted in [terrain.md](terrain.md) § Catalyst).
  - Knobs: ratio 1:1, Catalyst cap k × T, Catalyst decay slow, per world
    turn.
- **v1 spell content** (owner, 2026-11-09): `lightning_bolt` carries Charge
  (not reshaped, a Charge ride row as its innate element; it keeps its name
  for now, the owner's pick of 2026-11-10), and **a
  new single-target Cold spell** — *"one single target ice spell that is only
  single target (0 hops) because of its ice element load. and replacing that
  load with another element restores some hops and drastically alters the
  spell"*: its innate Ice row is the concentrate ([casting.md](casting.md) § Ice on a cast) eating its
  hops to 0; swap the element at the forge (ADR 0081 §7) and the hops come
  back. **Its signature is a crit condition, Thermal shock** (owner,
  2026-11-09, picked from four candidates; the ask: *"it should have some
  bonus effect that would be cool to port onto a fire/lightning setup (by
  tossing the ice load and putting fire or lightning in at the Forge). or
  has a clever crit condition. crit conditions are now even stronger and
  more important to get right: they shatter Frozen!"*): the hit crits when
  the target's terrain holds a different element than the cast carries, read
  before the hit's riders land, as every crit condition is ([hit-resolution.md](hit-resolution.md) § Landing
  resolution). The Ice form quenches a Burning or Shocked node;
  with Fire in, the restored hops walk a chain that crits — and so shatters
  — every Frozen node on it, so one spell freezes the field and, after a
  forge swap, breaks it. The condition earns its keep in the ported form:
  eating 4 authored hops to 0 is worth about 24 landings on the seed
  ([casting.md](casting.md) § Ice on a cast's table), so the Ice form likely clears the 10% break
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
  question ([forge.md](forge.md) § The forge). **The access shape is an owner call (2026-11-09,
  picked over a temp quiver addon and a starter element ammo type): the
  count is the access** — every reload mints `fire_element` fire arrows into their
  own bin, no action, nothing to find or buy (routes through
  `AmmoType.per_reload_stat_id`; the starter grant is count 1); the rejected
  alternatives: a temp quiver addon bought with a ranged resource that does
  not exist yet; a starter type with a fixed grant, two sources of one
  supply. Catalyst is an aspect, so goo arrows are budgeted by its count
  exactly as poison arrows are, and its starter count of 1 ([counts.md](counts.md) § Acquisition)
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
- **Knobs** ([terrain.md](terrain.md) § The threshold model, [go-offs.md](go-offs.md) § The trigger and what a go-off pays): T = 2 × degree, k, the hop ladder's
  L² × T, the disc's A and B, the decay rates — tuned with
  #1733.
- Which inner-tree shape holds elements, and the card offer's cadence.
- **Spike pop docs vs code**: owner, 2026-11-08, *"The existing one just pops
  the one, docs may be stale"* — `BladePopResolver`'s header describes severing past a pop while
  the code pops the one vertex and only records a `Severance` for what the
  pop left unreachable; settle header against code at the Ice spec.
