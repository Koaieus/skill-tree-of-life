---
status: settling
---

# Elements — reach as terrain

> The design set for **elements**, the second axis beside the aspects of
> [aspect_matrix.md](aspect_matrix.md): what an element *is* and *is not*,
> and the **target model** the #1716 drop builds. Nothing elemental exists in
> code yet; what is built (hit resolution as it stands today) is in
> [../domain/hit-resolution.md](../domain/hit-resolution.md) and the domain
> docs it links. Owner calls are dated and quoted; a pass reading says so, and
> a reading a child issue carries without the owner's word is marked
> *tentative*. A `Ready` child of #1716 cites the file and lines it builds
> against; when the whole drop has landed this set is archived as one
> ([../domain/design-doc-lifecycle.md](../domain/design-doc-lifecycle.md)).

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
Poison status, never a second one. Fuel left Fire and is **Catalyst**
([elements/terrain.md](elements/terrain.md) § Catalyst), the Explosive aspect retagged.

## The set

| File | What it covers | Decisions | Built by |
|---|---|---|---|
| this page | The two axes; the word "explosive"; the vocabulary guard | [0072](../adr/0072-an-aspect-is-one-status-an-element-is-a-status-family.md) | #1716 |
| [elements/counts.md](elements/counts.md) | One count per element, the status family and its roles, the count is supply, acquisition | [0072](../adr/0072-an-aspect-is-one-status-an-element-is-a-status-family.md) | #1793, #1815 |
| [elements/terrain.md](elements/terrain.md) | The threshold model: one terrain stack per element, inert up to T, reach is terrain-only; Catalyst; cooling and the terrain bars; temperature as one flow, Charge, the world clock | [0075](../adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md), [0081](../adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md) | #1794, #1795, #1796, #1801 |
| [elements/go-offs.md](elements/go-offs.md) | The trigger, what a go-off pays, the disc's size; the reach rule and chains; derived states (bands, travel, overflow); the reach triad | [0081](../adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md), [0086](../adr/0086-every-landing-is-a-whole-hit-a-go-off-shares-at-1-and-lands-on-its-own-node-too.md), [0087](../adr/0087-terrain-lands-at-the-tip-of-every-hit-and-a-shatter-no-longer-ends-the-walk.md) | #1799, #1800, #1802, #1805, #1806 |
| [elements/frozen.md](elements/frozen.md) | A blade on Frozen, what breaks the ice, the break as a channel; pair rules (Frozen mutes and releases, thaw) | [0088](../adr/0088-a-blade-vertex-breaks-frozen-only-if-at-least-as-heavy-as-the-node-a-lighter-one-snaps-and-the-ice-holds.md), [0090](../adr/0090-a-break-of-frozen-counts-as-2-channels-and-every-blade-contact-lands-weight-decides-only-the-break.md), [0091](../adr/0091-a-frozen-node-settles-once-per-generation-over-all-its-arrivals-and-the-damage-breaker-reads-each-arrivals-raw-amount-alone.md), [0093](../adr/0093-at-the-ice-a-merged-landing-is-one-arrival-a-thawing-absorbed-copy-walks-on-and-the-trapped-go-off-releases-once-per-breaking-hit.md) | #1804, #1807, #1808 |
| [elements/hit-resolution.md](elements/hit-resolution.md) | The hit: damage and riders; landing resolution: two stages, generations, the resolver's build calls, dual reach, the whole hit | [0073](../adr/0073-a-hit-is-damage-one-rider-map-one-reach-entry-and-an-intake-row-has-a-use.md), [0074](../adr/0074-a-hit-lands-in-three-phases-cold-absorbs-reach-frozen-is-a-glass-ceiling.md), [0082](../adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md), [0083](../adr/0083-a-hit-lands-its-terrain-riders-first-then-primed-ness-and-power-are-read-from-the-result.md), [0086](../adr/0086-every-landing-is-a-whole-hit-a-go-off-shares-at-1-and-lands-on-its-own-node-too.md), [0092](../adr/0092-within-a-beat-all-damage-lands-before-any-aspect-rider-so-the-ice-reads-the-floater-and-a-depleted-node-takes-no-aspect-riders.md) | #1797, #1798, #1818 |
| [elements/forge.md](elements/forge.md) | The forge: one intake row type, its uses, the slots, the cap and the trim | [0085](../adr/0085-the-forge-has-three-kinds-of-slot-and-a-spells-point-cap-grows-with-the-caster-nodes-degree.md), [0089](../adr/0089-the-loadout-hides-no-target-a-pip-shows-overclock-potential-and-a-target-too-low-for-it-trims-it.md) | #1809, #1810, #1811, #1814 |
| [elements/casting.md](elements/casting.md) | Shape and ride: what an element does on a cast; Ice on a cast, the concentrate | [0084](../adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md) | #1789, #1812, #1813 |
| [elements/open.md](elements/open.md) | What is still open, and the knobs | — | — |

The hit's pipeline as built today, which this set changes, is ADR
[0067](../adr/0067-a-status-rider-lands-before-its-paired-hit-and-the-hits-gate-is-a-memoized-step.md)'s
and [../domain/hit-resolution.md](../domain/hit-resolution.md)'s. Corrections
owed to 0081, 0082 and older ADRs are #1816's.

## Three things wear the word "explosive" (pass clarification, 2026-11-04)

Owner: *"fuel defensive: explode (trigger aoe reach), fuel rider: splodes
(spreads) or plants?? (adds fuel??) or is that Magic making an exception …
i confuse myself"*. No status has an offensive and a defensive face; three
different rows share the old word, on every facet alike:

| | Row | What happens | Plants |
|---|---|---|---|
| "infuse Explosive to make it AoE" | a Heat **ride** row (or a bespoke shape use) | the hit plants Heat; once its node is past T, later hits there blast | Heat |
| "goo arrow" | a Catalyst **ride** row | Catalyst is added to the landing node, inert until Heat, Cold or Charge lands there or the node primes | Catalyst |
| "a catalysed node" | Catalyst on the node (an aspect status) | colourless until Heat, Cold or Charge lands; then its store becomes those stacks 1:1, pro rata over them, same landing | — |

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
| **Rider** | Plants a status — any status, terrain and movers included (a goo arrow plants Catalyst) | a reach |
| **Use** | What an intake row's load buys: an open set (ADR 0070's `LoadUse`) — ride, a bespoke shape, cleanse … | a slot |
| **Terrain stack / Mover / State** | The roles in an element's family (table above): Heat, Cold, Charge / Frostbite / Burning, Frozen, Shocked; Catalyst is in no family | "the fire status" |
| **Primed** | A node whose terrain stack is past T (count > T, T = 2 × degree): a hit on it sets it off | a status with stacks of its own |
| **Excess** | count − T on a primed node: Burning's power, what a shatter spends | the overflow |
| **Overflow** | Stacks past the cap k × T: decay fast; deep freeze spends them | wasted |
| **Member** | A status of an element, whatever its role: Heat is a member of Fire, Frostbite of Ice; Catalyst is nobody's member; an Element Matrix row is a member row; a member keys its own facets (`heat_resistance`) (owner, 2026-11-05: *"member"*) | a facet (arrow / blade / spell) or a role |
| **Catalyst** | inert, colourless aspect status (allocated nodes only) that becomes Heat, Cold or Charge 1:1 when those stacks land on its node (pro rata over them) or its node primes: the element analogue of Greed | fuel, a family member, a reach, a go-off |
| **Volatile** | a word the owner floated for the states that go off, Burning and Shocked (owner, 2026-11-09: *"`volatile` is a better fit to describe Burning *and* Shocked"*) — not Frozen, which denies | a status |
| **Fire / Heat / Burning** | The element (its count) / its terrain stack / Heat past T | three names for one thing |
