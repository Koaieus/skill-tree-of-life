# Info Gating — Skill Tree of Life

---

## The pitch

Visibility on the graph is not a boolean. A viewer can know that *a node
exists* without knowing *what it is*; can know *what archetype it is*
without knowing *who owns it*; can know *who owns it* without knowing
*what modifiers it carries*. These are independent dimensions of
information, and the game gets more interesting the more we can dial
each one separately — for the player, per enemy entity, and per
mechanic.

Today the engine has two states: **visible** (full info, clickable) and
**sensed** (a faint outline, no detail). That's a useful starting
point but it's a 2-level enum where what we actually want is a vector.
This doc captures *what the vector should look like* so the next
implementation pass on the vision system has a target to aim at, and so
mechanics in design (sensor towers, signal blockers, recon spells, the
Fairy's narration, eventual fog-of-war PvP) all reach for the same
vocabulary.

---

## The dimensions

Each is independent. A given "info level" toward a node or edge is
a tuple of which gates are open.

| Gate | Open means viewer can learn… | Closed means… |
|---|---|---|
| **Existence (node)** | "There is a node at this graph position." | Position hidden — node isn't even drawn |
| **Existence (edge)** | "There is an edge between these two nodes." | Edge hidden — topology not revealed |
| **Archetype** | The node's base type — e.g. "this is a STR node" | Outline shows but base-type colour suppressed |
| **Allocation status** | Whether the node is owned at all | Allocation = unknown |
| **Owner identity** | *Which* entity owns it (their colour / name) | Allocated, but by whom is hidden |
| **Core flag** | Whether the node is its owner's core | Core star suppressed |
| **Modifiers** | The list of `StatModifier`s the node grants | Modifier content hidden |
| **Addons** | Which addons (Armor Ring, Buffer, etc.) sit on the node | Addon visuals + tooltip suppressed |
| **Combat HP** | Current/max HP of the node | HP bar hidden |
| **Local stats** | The node's specific stat overrides | Hidden |

**Vision = all gates open.** That is the design definition of "in clear
sight" — not a separate code path, just every gate set to open. The
implementation should treat full vision as the maximum point on the
same scale as everything else, not as a distinct mode. That way new
information dimensions added later automatically extend "what does it
mean to be in vision" without rewriting the visible path.

---

## Default gate profiles

Most mechanics will fit one of a few common profiles. Profiles are *not*
the source of truth — they're shorthand for the underlying gate vector.

| Profile | Existence (node) | Existence (edge) | Archetype | Allocated? | Owner | Core | Modifiers | Addons | HP | Local stats |
|---|---|---|---|---|---|---|---|---|---|---|
| **Hidden** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Sensed** (current MVP) | ✓ | ✓ (if both endpoints reached) | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Scouted** (proposed) | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Identified** (proposed) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| **Vision** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Gaps between profiles are where mechanics live:

- A scrying spell could open **Modifiers** + **Addons** on a single
  target without opening **Existence** for any nearby nodes — "I can
  read its secrets but not see around it."
- A truesight aura could open **Owner** on every node within range
  regardless of other gates — the rumoured presence becomes a known
  enemy.
- An Anti-Recon node could *close* the Archetype gate within its
  influence — sensed-only neighbours read as featureless rings even
  to a viewer who'd normally read archetype at this range.

---

## Mechanics roster (current design pressure)

These are the mechanics that already exist in design and need this
system to land cleanly:

- **Sensor range** (engine, MVP) — opens the **Sensed** profile on
  every node within N hops of an owned node, scaled by per-node
  `sensor_range` local stat. Edges between two reached nodes open
  their existence gate. Today this is hardcoded; should become "this
  mechanic raises the gate vector to **Sensed** within its reach."
- **Sensor Tower addon** (design) — pumps `sensor_range` on its node,
  same gate vector as Sensed.
- **Signal Blocker / Anti-Recon** (design, in vision-system future
  hooks) — raises hop cost OR closes gates within influence.
- **Recon spells** (design, spells.md) — single-target gate openers
  for **Modifiers** / **Addons**. Need a way to *upgrade* a node's
  info level for the caster only, for a duration.
- **The Fairy** (design, lore) — narrative reveals can be modelled as
  the Fairy opening specific gates at story beats. Same surface.
- **PvP fog of war** (design, GDD) — each entity has its own gate
  vector toward every other node. The current single-viewer
  VisionSystem implicitly assumes the player is the one viewer; the
  general form is per-entity.

If we get the surface right once, all of these become "edit a gate
vector" rather than each one adding a new render path.

---

## Implementation sketch (not a contract)

The shape that keeps coming up: **per-viewer-per-target gate vector**,
computed by `VisionSystem` as the union of contributions from each
mechanic the viewer participates in. Roughly:

```
viewer × target → InfoLevel { existence, archetype, owner, ... }
```

- Mechanics register as "info sources" with a function
  `contribute(viewer, target) → InfoLevel`. Default is empty.
- The system unions contributions (per-gate OR — once any source
  opens a gate, it's open).
- `SkillNode` / `Edge` render against the resulting `InfoLevel` for
  the *local* viewer (single-player) or the controlling-entity viewer
  (PvP, eventually). The current `sensed: bool` becomes a derived
  view of "info level for the local viewer is sensed-or-higher."

This is sketch-level — pick a real data shape (struct vs. bitmask vs.
dictionary) when implementing, against actual mechanics that need it
rather than the speculative roster above.

### Ergonomics requirements

The thing that makes or breaks this system isn't the data model,
it's whether a designer can sit down with a new mechanic in mind and
quickly answer: *which gates does this open, how far, for whom?*
The interface should make that question reflexive.

- **Per-gate granularity** in the authoring layer. A mechanic should
  declare "I open Archetype within 3 hops" without having to also say
  anything about Owner or Modifiers — those default closed.
- **Profiles as presets, not categories.** "Sensed" is a shorthand
  designers can pick to fill in the common case; the system stores
  the underlying gate vector and a custom mechanic can deviate from
  the profile without forking it.
- **One render path per gate.** Renderers ask "is the Archetype gate
  open?" not "is the node sensed?" — so a new gate-opener mechanic
  doesn't need a render code path of its own.
- **PvP-ready from day one.** Even while we're single-player, every
  query is `(viewer, target) → InfoLevel`, never `target →
  InfoLevel`. Skipping this is the kind of choice that takes weeks
  to unwind later.

---

## Not in scope here

- The data structure that backs the gate vector — pick when there's
  a real mechanic forcing the choice.
- UI for the player to *see* info levels (e.g. a tooltip that says
  "you know X about this node but not Y"). Worth doing, but a
  separate doc.
- How info persists across turns / between sessions. Today vision is
  recomputed every frame from scratch; "discovered once, remembered"
  is a separate mechanic.

---

## Engineering companion

[../domain/vision-system.md](../domain/vision-system.md) is the current
engineering doc for the vision system. The MVP sensor/sensed
implementation lives there. When the info-gating system actually
lands, the engineering details move to a sibling
`docs/domain/info_gating.md` and this design doc stays as the *why*.
