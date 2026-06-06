# Addons & Node Specializations — Skill Tree of Life

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

> **Rewritten.** The old inhale/exhale charge-holding model is gone (melee no longer runs on charged Buffer nodes — it is the phantom blade, sized `STR//10+1`; see `combat_system.md`). Buffer is now a **utility** addon: the key that unlocks **battle-phase temporary reach**.

**Effect:** During the **Battle phase** (see the three-phase turn), tapping a Buffer node **temporarily allocates existing field nodes** — reaching across the *real* graph to bring an attacking node/pivot to the front (melee), claim firing stubs (ranged), or pad a casting hub's degree (magic). It does **not** spawn new vertices; it plays with the real skill-node/edge graph. After a tap the Buffer goes on **cooldown** (cannot re-tap next turn — preserves cadence). All temporarily-allocated nodes **revert at battle phase end**.

**Universal across all colors.** Melee/ranged/magic all benefit — it is reach, not a melee-only tool.

**Interaction with `pressure_capacity`:** The entity stat `pressure_capacity` is now the **reach/budget** — how many field nodes a single tap can temporarily allocate (no longer "max nodes chargeable for a melee burst").

**Notes:** Buffer is **utility-only — no attack of its own** (not a firing leaf, not a caster, not a blade source). Dedicating a node slot to one is a real tradeoff: without Buffers you commit your shape up front and fight with it; with them you extend mid-fight and snap back. This is a *capability* addon, not a passive bonus.

**Shelved alternative:** a "ghost extension" version that spawns *new* temporary vertices was considered and dropped — it read as a cop-out and cluttered the board. Reach plays with real nodes only.

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

### Clamp

**Effect:** If a node carrying the Clamp addon is used in a **phantom blade** (see melee, `combat_system.md`), its corresponding **joint becomes a clamp (a weld) instead of a free pin.** That is the *whole* effect — it locks the angles at that one joint into the blade's swing frame.

**Why it matters:** Melee rigidity is normally **emergent from triangulation** (the grip/pivot is the only default clamp; every other joint is a free pin). Clamp lets you **stiffen a chosen joint *without* a triangle**, opening crafting options triangulation can't:

- **Rigidity without a cycle** — hold an L-bend or a path stiff at a hand-picked joint; e.g. clamp a leaf-launched haft's first internal joint to turn a floppy mace into a **rigid pole-cleaver**.
- **Partial whips** — clamp the base of a chain but leave the tip free, so only the outer segment whips (a controlled flail).
- It does **not** create a face. Clamp gives **rigidity only**; **triangulation gives rigidity *and* a face (area damage)** — so the two stay distinct build verbs with distinct niches, and Clamp is no substitute for bracing when you want a pan.

**Only matters at articulating joints:** a Clamp on a blade-leaf tip or an already-braced (triangulated) node does nothing extra — it pays off on a node that sits as a degree-2 hinge in the blade.

**Notes:** A cheap, legible crafting lever. Because it's an addon (loot / class / Tech Seed), spending a slot on Clamp is a real tradeoff against triangulating the same shape with extra nodes/edges — a different cost curve to the same rigidity, minus the face.

---

### Spikes *(NEW — offensive direction confirmed; defensive model + collision OPEN)*

> Spikes unify (and physically reframe) the offensive and defensive sides of node *sharpness*. Closely related to **Thorns** — see the `FLAG` below; resolve whether they are one stat or two **before either ships.**

**Offensive *(confirmed direction)*:** Spikes raise a node's **vertex-spike** contribution when that node is part of a phantom blade. The combat doc bundles face damage as `Σ edges + Σ vertex spikes + B`; a Spikes modifier/addon raises that **vertex term** — a swung spiked node drives its spikes through whatever it sweeps (this is the "swung = offensive" half of thorns=spikes in `combat_system.md`).

**Defensive *(OPEN — the part worth real exploration)*:**
- *Rejected/uncertain candidate:* spikes damage *your own* nodes when struck. Leaning **no** / unclear.
- *Candidate worth exploring:* spikes **damage or sever the edges/faces of an incoming phantom blade** on collision — a **physics-layer melee defense** (it only matters vs. melee, not ranged/magic). Because a phantom blade's rigidity comes from triangulation, **popping an edge can de-rigidify a braced blade into a floppy whip mid-swing.**
- This is **thorns reframed**: instead of flat counter-damage to the attacker's node HP (current `thorns`), spikes attack the attacker's *blade structure*.

**`FLAG` — Thorns vs. Spikes (resolve before either ships):** are `thorns` / `thorns_base` and `spikes` the **same stat viewed two ways**, or **distinct** (HP-counter vs. structure-attack)? The current `combat_system.md` treats thorns = spikes = one stat (*sharpness*: stationary→counter-damage, swung→offensive contact). The new defensive candidate (structure-attack on the incoming blade) is a *third* behaviour that may not collapse into flat counter-damage. Decide before implementing either.

**Open collision questions (dedicated pass — do not implement until specified):** what exactly does contact do — damage an edge's HP? sever it outright? cost the blade rigidity? — how it is balanced, and what feels right.

**Halo integration *(confirmed it should still work)*:** the Halo shell aura grants spikes → the shell becomes a literal **spike-ring / wall against incoming melee blades.** Counterplay preserved: a well-placed **ranged** attack can knock out a shell node and **distort the wall** (open a gap) — ranged remains the answer to a spike ring. See `core_classes.md` (The Halo).
- **Proposal *(OPEN)*:** the spikes aura targets **any** node at shell distance, *including enemy-owned ones* — if an enemy allocates a node onto your ring, your aura spikes *their* node (intruding on the shell is self-harm). Positional, not ownership-gated. Gate this behind the collision-model decision above.

---

### Gate *(NEW — confirmed direction; a couple of sub-points OPEN)*

> **A 2-component addon** — one addon spanning **two endpoint nodes** (paired, shared), not the usual single-node attachment. Theme-perfect for an edge-centric cosmos: it is the only addon whose unit *is an edge.*

**Effect — a toggleable edge.** The Gate acts as a `gate` the owner can **toggle at will**:

- If an edge **already existed** between the endpoints → the gate can **depower** it (turn it off).
- If **no edge existed** → the gate can **create a temporary edge**.

**Placement constraints:**
- The two endpoint nodes must be within **euclidean range `X`** of each other.
- No **gate** may already run between them. (A normal edge *may* exist — the gate depowers it.)
- A **depowered** edge still renders and still counts as "present / not crossable" for placement — preserving planarity. You cannot route a new gate through the space a depowered edge occupies.

**Self-islanding is allowed.** Toggling can island (and therefore wound) your own constellation — e.g. depowering what was a bridge. The player gets a **warning** *(frequency OPEN: once vs. every time)*, then it is their call. Power with rope to hang yourself on — consistent with bridge-sniping being intended skill expression.

**Persistence *(OPEN — leaning persistent)*:** either the toggle **persists on turn end**, or it reverts (re-powers / removes the temp edge) at turn end. Leaning persistence.

**Lifecycle:**
- **On addon removal:** reverts to the original situation (re-powers a depowered edge / removes a created edge).
- **On either endpoint node's death:** the addon is removed (and thus reverts). Refund / addon-breakage policy is **deferred** (a general addon-lifecycle question — see Open Questions).

**Per-mode interactions (design hooks):**
- **Melee:** toggling an internal edge changes the induced subgraph's faces and rigidity → **reshapes the phantom blade on demand** (brace/unbrace, open/close a face).
- **Magic:** powering an edge raises the endpoints' degree → potential **cast-tier / degree-gate shift** (extra effective degree).
- **Ranged:** depowering edges manufactures **leaves** (degree-1 nodes are the firing ports) → "leaf city," more volley origins on demand.

**Relationship to existing systems (`FLAG`):**
- **Edge-deletion invariant / Edgelord — not violated.** The combat doc's invariant ("no mechanic may leave a region permanently unreachable") and the Edgelord's *permanent* edge add/remove specialty (Bleeding Edge) are **not** infringed by the Gate, because the Gate is **fully reversible** (re-power, or remove-to-revert). Permanent severing remains Edgelord's heresy-free domain; the Gate is universal *precisely because* it is reversible/toggle. The two are not redundant — distinct on permanence. (Mirrored in `combat_system.md` — Edge-cutting jab invariant.)
- **Buffer overlap — reconcile.** Buffer is "universal temporary **reach** utility" (temporarily allocate existing *nodes* for a battle-phase move); the Gate is temporary **edge** toggling. They share a "temporary topology" identity but operate on different objects (nodes vs. edges) and at different scopes (Buffer reverts at turn end and goes on cooldown; Gate leans persistent and is a placed 2-node addon). Treat them as **distinct addons** for now — Buffer reaches across the *existing* graph, the Gate *rewires* it — and revisit if play shows the identities blur.

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

**Proposed concept:** A node carrying Relay increases the effective propagation distance or reach of Blue (graph-magic) by acting as a signal booster such that a casting node can target anywhere in its own range or within the combined ranges of in-range relays. The spell would be cast as if from there, while it was in fact one or more relays away — might have been some high-degree casting tower node.

---

## Tech Seeds

A **Tech Seed** is a rare item found on the field — dropped from loot nodes, hidden in neutral clusters, or earned as a level reward. The player holds a small number of them (`tech_seed_capacity`, default 2). Planting a seed on an owned node starts a growth process that, after several turns, produces **fruits:** modifier options drawn from a weighted pool seeded by the node's type and contents.
Plant a tech seed, harvest its tech fruits — delicious.

### How it works

1. The player selects an owned node and plants a Tech Seed on it. The seed is consumed.
2. A **Tech Tree** visually grows from that node over 3–5 turns — a tiny branching structure that appears as a physical object on the field.
3. When the Tech Tree is ripe, it bears **N fruits** (N = 3–5). The player selects one.
4. The chosen fruit is a modifier that applies immediately — core-bound (travels with the core, not attached to any node).
5. The Tech Tree withers. The node returns to normal.

The node continues to function normally during growth. The Tech Tree is an extra process running on top of it.

### The modifier pool

The fruit pool is generated at plant-time from the node's type and modifier list, but the weighting is skewed toward the rarer end. The seed is how you access the *ceiling* of what a node could offer, not just what it normally provides.

### Risk and commitment

Planting a seed is an investment. The node must remain owned and alive for the full growth duration. An enemy severing access to the node before the Tech Tree fruits loses you the seed entirely. The growth timer is visible — to the opponent too. Racing to fruit before being cut off is a genuine tactical scenario.

### How seeds are found and held

Seeds are rare field items — not buyable, not craftable in v1. Finding a seed when at capacity means either discarding it or immediately planting it.

---

# Node Specializations (TODO: Move specializations to separate file)

A different concept from addons. A specialization is either:
- **(A) Intrinsic:** the node was generated on the field in this state. Found-in-the-wild. Cannot be removed or changed.
- **(B) Transformed:** a player (or enemy) applied an irreversible or partially-reversible process to a normal node to create a specialized state. The process is costly, possibly destructive.

Both contrast with addons, which are applied freely (within resource constraints) to any compatible owned node.

The following are candidate specializations — design sketches, not confirmed mechanics. The concept is under exploration.

---

### Corrupted Node *(candidate specialization)*

**Description:** A node with powerful modifiers but a significant downside that cannot be removed — the benefit and the cost are permanently fused. Might be encountered on the field as neutral (abandoned by a dead entity that couldn't afford the cost), or created through a process that involves trading something permanently.

**Examples (illustrative, not committed):**
- `+5 DEX / −3 armor` — ranged powerhouse, structurally fragile
- `+1 sp_per_turn / takes double damage` — economic engine with a death wish
- `damage_floor = −1 / 0.5× node_health_max` — heals slightly when hit, but dies in two hits

**How encountered:** Field-generated (type-A) primarily. Possibly also type-B: the Bulwark's floor-reduction perk path as a form of controlled self-corruption — choosing to make your floor-reduction permanent and irreversible in exchange for a stronger bonus.

**Design note:** Corrupted nodes as a category make the loot system richer. A STEAL option in the loot window that says `+5 DEX (take double damage)` is a real decision. Proliferating that modifier is especially interesting — under the reframed model (PROLIFERATE = remove a core-held mod, mint **N tainted copies** across a cluster you must hold; see `combat_system.md`), you'd be spreading the double-damage downside across multiple nodes while spreading the DEX bonus. Whether the downside proliferates at the same rate as the bonus is a calibration question. Note that the **N copies are tainted** — owner-independent, non-extractable, non-re-proliferable — so you can never launder a corrupted-but-juicy mod back into a clean portable core mod by round-tripping it through the field.

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
8. **Gate persistence on turn end:** does a toggle persist past turn end, or revert? Leaning persistent. (Gate addon.)
9. **Gate self-island warning frequency:** warn once, or every time a toggle would island the owner's own constellation? (Gate addon.)
10. **Addon lifecycle on node death (general):** refund / addon-breakage policy when an endpoint (Gate) or carrier node dies — does the addon drop, refund, or break? Deferred general question raised by the Gate's 2-endpoint lifecycle.
11. **Gate vs. Buffer identity:** both are "temporary topology" utility — keep distinct (edges vs. nodes) or let one absorb part of the other's role? Revisit if play shows the identities blur.
