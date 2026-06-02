# Addons & Node Specializations — Skill Tree of Life
*v0.1.0 · New document.*
*Companion to: combat_system_design, core_classes, lore.*

---

## Two Distinct Concepts

Before listing anything, the distinction:

**Addons** are attachable components applied to a node on top of its base type. They are modular — a node can have an addon applied to it, possibly removed, possibly transferred. A node with an Armor Ring addon is still a regular node; it just has a piece of equipment attached. Multiple addons can coexist on one node (if compatible). Addons are found as loot, granted by class abilities, or produced by the Tech Seed system.

**Node Specializations** are something deeper — either a node's intrinsic nature as generated on the field, or a state a node has been transformed into through a process. A specialized node cannot have its specialization removed without destroying or fundamentally altering the node. Some specializations may be one-way: once transformed, the node is that forever. Others may be found in that state — already specialized when the player encounters them, as part of the field's procedural generation. Specializations are rarer, more impactful, and not freely applicable to arbitrary nodes.

**Designer test:** If you can apply it to any node you already own with resources, it's probably an addon. If the node has to come that way, or be forged into that state through a special act, it's probably a specialization.

This distinction is provisional and may collapse or subdivide further once both systems are playtested. Both concepts are tracked in this doc; the exact boundary is flagged as an open question.

---

## Confirmed Addons

These are established mechanics referenced consistently in the design docs.

---

### Armor Ring

**Effect:** Increases this node's damage resistance — reduces `taken` for all attack types hitting this specific node. The node-level version of the `armor` entity stat.

**Stacks with:** Entity-level `armor` stat. A node's effective armor is its share of the entity total plus any Armor Ring modifier.

**Notes:** The simplest defensive addon. Makes individual nodes harder to dislodge. A cluster of Armor Ring nodes is a fortified zone that requires sustained pressure to break through.

---

### Reinforcement

**Effect:** Increases this node's `node_health_max`. The node has more HP before being severed.

**Stacks with:** Entity-level `node_health_max`. Per-node HP is seeded from the entity total plus Reinforcement bonus.

**Notes:** The direct survivability addon. Where Armor Ring reduces damage per hit, Reinforcement increases the number of hits a node can take. Together they compound: an Armor Ring + Reinforcement node is both harder to damage and has more buffer.

---

### Buffer

**Effect:** This node can participate in the melee inhale/exhale as a charging buffer. When the entity begins charging a melee attack, the player may designate Buffer nodes to contribute pressure. Each designated node spends its action for that turn (cannot contribute to anything else). On release, each Buffer node that charged adds to the burst's power and/or shape size. The node returns to normal service after release.

**While charged:** Buffer nodes that are currently holding charge are in a vulnerable state — they contribute a defensive penalty (form TBD: flat resist reduction or flat damage-taken increase) until released. Bigger melee wind-up = more Buffer nodes charging = bigger vulnerability window.

**Interaction with `pressure_capacity`:** The entity stat `pressure_capacity` caps how many Buffer nodes can charge simultaneously for a single burst.

**Notes:** Buffer addon is what makes a node capable of participating in melee charging. Without it, a node cannot be used as a charge buffer. This is a *capability* addon, not a passive bonus.

**Design tension:** Is Buffer an addon the player applies to nodes they own, or a specialization — nodes that come pre-built with buffer capability? Leaning toward addon (applies to owned nodes through loot/crafting), but the "melee buffer node" concept (a node found already specialized for this role) is a candidate for Node Specializations. See that section.

---

### Winch

**Effect:** Exerts a pull force on adjacent nodes, reducing effective euclidean distance between this node and its neighbors. Does not create or delete edges — purely a math adjustment to the distance calculation.

**Use cases:**
- Draws neutral or loot nodes (that are adjacent to this node) closer within the euclidean distance framework. Makes them easier to target with ranged attacks or bring within aura range.
- Keeps Serpent class nodes close to the core spatially despite winding hop-paths.
- Reduces penalty for Serpent class nodes that would otherwise be far euclidean from the core.

**Does not do:** create new adjacency (no new edges), delete edges, change graph topology in any way.

**Winch cap:** There must be a maximum effective euclidean reduction per node. Otherwise the Winch trivializes the Serpent's euclidean penalty and potentially makes all nodes appear geometrically adjacent to everything. Cap value TBD in playtesting.

---

### Lifeline

**Effect:** If any sub-graph containing nodes within N hops of this Lifeline node becomes an island (no path to the entity's core), those nodes receive a **1-turn grace period** before dissolving. During this grace period, the entity may re-establish a connection to the core — if they succeed, the island is saved and the timer cancels. If the grace period expires without reconnection, the island dissolves normally (SP Reservation fires for all nodes).

**Counter-play:** After the snipe that created the island, the chokepoint node (where the bridge used to be) is now neutral. The attacker can immediately try to allocate it — spending 1 SP to claim the chokepoint. If they succeed, the defender has no path to reconnect even within the grace period. If the defender can bridge through a different route before the attacker blocks — the island survives.

**Calibration:** The hop radius N of Lifeline's protection zone is a tuning parameter. Too large: oppressive safety net. Too small: rarely meaningful. Needs playtesting.

**Rarity:** Uncommon. Not a free safety net every entity gets — found through loot, class-specific rewards, or rare field nodes.

---

### Lifelink

**Effect:** This node acts as a **proxy core for disconnection purposes only.** An island containing a Lifelink does not dissolve — the Lifelink sustains it indefinitely, as if that sub-graph had its own core for connectivity checking. The island persists as long as the Lifelink exists.

**Lifelink does not grant:**
- Core movement (cannot hop the core)
- Core aura (does not radiate buffs)
- Breakout trigger
- Any core class abilities

It is purely a topological anchor.

**Properties:**
- Has normal node HP and can be attacked like any node.
- If an enemy captures the Lifelink: the island immediately loses its anchor → island check fires against the new owner's core → island dissolves (it's not connected to the enemy's core either).
- Identifying the Lifelink node is a skill. Destroying it collapses the entire sub-graph it sustained.

**Rarity:** Very rare. 1–3 per run, possibly 0 in early levels. Should not appear until roughly halfway through total level count. The Hive core class is the designed introduction vehicle — players should understand basic island rules before encountering Lifelink in the wild.

**Interaction with Lifeline:** A Lifelink sustaining an island, while Lifeline-gated bridges protect access to the Lifelink — the concerning combo. Counter: melee pressure directly on the Lifelink node, bypassing the bridge game. Do not balance against this interaction until seen in playtesting.

---

## TBD Addons

Concepts that appeared in design discussion but have not been formally designed. Listed here for tracking. **Not confirmed mechanics.**

---

### Relay *(concept only — TBD)*

**Proposed concept:** A node carrying Relay increases the effective propagation distance or reach of Blue (graph-magic) attacks that pass through it. Acts like a signal booster in the magic propagation network.

**Why it's TBD:** Magic propagation rules are still an open design question. The exact semantics of "relay" depend on decisions not yet made:
- Does magic propagate through owned nodes only, or any traversable edge?
- Is propagation hop-count limited? If so, does Relay add to that count?
- Does magic hit terminal nodes only, or everything along the path?

Until these are decided, Relay cannot be specified. The concept is interesting — a node that makes your magic more dangerous by virtue of the path running through it — but the implementation is premature.

**Why it was mentioned in earlier docs:** Several versions of the combat design doc referenced Relay as if it were established, particularly in the context of Bleeding Edge (edge-cutting jabs paired with "edge-reintroduction via Relay"). This was premature. The Relay reference in those docs is informally flagged as TBD pending magic propagation design.

**Note:** The edge-reintroduction requirement (no mechanic may leave a region permanently unreachable) still holds. Whatever mechanism eventually provides edge-reintroduction — whether it's Relay, a core ability, reallocation bridging, or something else — needs to be designed alongside Bleeding Edge.

---

## Node Specializations

A different concept from addons. A specialization is either:
- **(A) Intrinsic:** the node was generated on the field in this state. Found-in-the-wild. Cannot be removed or changed.
- **(B) Transformed:** a player (or enemy) applied an irreversible or partially-reversible process to a normal node to create a specialized state. The process is costly, possibly destructive.

Both contrast with addons, which are applied freely (within resource constraints) to any compatible owned node.

The following are candidate specializations — design sketches, not confirmed mechanics. The concept is under exploration.

---

### Melee Buffer Node *(candidate specialization)*

**Description:** A node with unusually high `pressure_capacity` — capable of holding more melee charge than a standard node could, even with the Buffer addon applied. Provides the equivalent of multiple Buffer addons in a single node, or enables melee bursts that wouldn't be possible with standard nodes.

**How encountered:** Found on the field in a special state (type-A specialization). Visually distinct. Allocating it provides this capability immediately.

**Design tension:** Is this just a node with a boosted Buffer addon, or is it something categorically different? If it's just "Buffer addon + stat boost," it belongs in the addon system. If it allows melee behavior that no addon combination can replicate (e.g. a single node that can anchor an entire melee shape around it), it's a true specialization. To be resolved in playtesting.

---

### Corrupted Node *(candidate specialization)*

**Description:** A node with powerful modifiers but a significant downside that cannot be removed — the benefit and the cost are permanently fused. Might be encountered on the field as neutral (abandoned by a dead entity that couldn't afford the cost), or created through a process that involves trading something permanently.

**Examples (illustrative, not committed):**
- `+5 DEX / −3 armor` — ranged powerhouse, structurally fragile
- `+1 sp_per_turn / takes double damage` — economic engine with a death wish
- `damage_floor = −1 / 0.5× node_health_max` — heals slightly when hit, but dies in two hits

**How encountered:** Field-generated (type-A) primarily. Possibly also type-B: the Bulwark's floor-reduction perk path as a form of controlled self-corruption — choosing to make your floor-reduction permanent and irreversible in exchange for a stronger bonus.

**Design note:** Corrupted nodes as a category make the loot system richer. A STEAL option in the loot window that says `+5 DEX (take double damage)` is a real decision. Proliferating that modifier is especially interesting — spreading the double-damage downside across multiple nodes while spreading the DEX bonus. Whether the downside proliferates at the same rate as the bonus is a calibration question.

---

### Crystallized Node *(candidate specialization)*

**Description:** A normal node that has been locked into its current state — its modifiers are frozen permanently (cannot be upgraded, overwritten, or proliferated from). In exchange, those modifiers are permanently stronger than a normal node's equivalents. Cannot be deallocated by the owning entity (only force-deallocation by combat can remove it). Can be transferred to an adjacent position once (consuming the crystallization — the node becomes normal again at the destination).

**How created:** Type-B specialization. Triggered by a player ability or loot option — a deliberate act of trading flexibility for permanence. "I want this `+3 armor` node here, always, no matter what."

**Use case:** Locking a high-value node in a critical position. A Crystallized Lifeline node that cannot be voluntarily retreated becomes an ironclad topological anchor. A Crystallized Armor Ring node at a chokepoint is a permanent fortification.

**Cost:** Inability to dealloc it if the build changes. Potentially losing the investment if that node is killed in combat (crystalized doesn't mean unkillable — just unlockable).

---

### Anchor Node *(candidate specialization)*

**Description:** A node that resists island dissolution — when it becomes part of an island, it has N turns of built-in grace before the island dissolves (like a built-in Lifeline, but intrinsic to the node rather than an addon).

**Distinction from Lifeline addon:** Lifeline protects nodes *near* it. An Anchor node protects *itself and its sub-graph* from immediate dissolution. It's stronger per-node but applies to fewer nodes (just those in its own island).

**Notes:** Potentially the rarest field-generated node type. Might be the natural-lore explanation for why some nodes survive longer than others in ancient contested regions of the tree — they've "crystallized" through long allocation history into more resilient forms.

---

## Addon Design Principles

1. **Addons change behavior; modifiers change stats.** A node with Armor Ring is defensively stronger because of behavior (damage reduction per hit). A node with a `+3 armor` modifier is stronger because of a stat. Both contribute to the same effective armor, but through different pipeline stages.

2. **An addon should be legible from the node's visual.** Players should be able to look at a node and understand why it behaves differently. Addons need distinct visual indicators.

3. **Addons don't define node type.** A Red node with Armor Ring is still a Red node — it provides STR, it attacks with melee, it just also reduces damage to itself. The color identity doesn't change.

4. **Specializations should feel rare and meaningful.** If specializations are too common, they're just addons with extra steps. The first Crystallized node a player encounters should feel significant.

---

## Open Questions

1. **Addon/Specialization boundary:** Does the distinction hold up in practice, or does everything collapse into one system? Could revisit after first playtests.
2. **Addon transferability:** Can addons be moved from one node to another? Removed entirely? Or are they permanent once applied? If removable, they're more like equipment. If permanent, they're closer to specializations.
3. **Addon stacking:** Can a node have multiple addons simultaneously? Are there compatibility rules? (E.g., Armor Ring + Reinforcement = yes. Lifeline + Lifelink = probably not, doesn't make sense.)
4. **Relay design:** Blocked on magic propagation rules. Return to this after magic is designed.
5. **Corrupted node downside proliferation:** When a corrupted modifier is PROLIFERATED in loot resolution, does the downside also proliferate? At the same rate? This determines how dangerous a corrupted loot pick is.
6. **Crystallized node combat interaction:** Crystallized = can't be voluntarily deallocated. Does this mean it can't participate in melee reshaping (Buffer charging requires the node to spend its action, not dealloc — so probably fine)? Does Uprooting count as force-deallocation or voluntary?
7. **Buffer addon vs Buffer specialization:** Resolve by playtesting whether the capability difference is meaningful enough to warrant two systems.
