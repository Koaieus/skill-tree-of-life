# Node Addons — Skill Tree of Life

---

## Two Distinct Concepts

**Addons** are attachable components applied to a node on top of its base type. They are modular — a node can have an addon applied to it, possibly removed, possibly transferred. Multiple addons can coexist on one node (if compatible). Addons are found as loot, granted by class abilities, or produced by the Tech Seed system.

**Node Specializations** are something deeper — either a node's intrinsic nature as generated on the field, or a state transformed into through a costly irreversible process. See [skill_node_specializations.md](skill_node_specializations.md).

**Designer test:** If you can apply it to any node you already own with resources, it's probably an addon. If the node has to come that way, or be forged into that state through a special act, it's probably a specialization.

This distinction is provisional and may collapse or subdivide further once both systems are playtested.

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

### Relay

> **Direction confirmed; damage bonus and routing cost OPEN.** The old "extends hop count" model is replaced. Relay is now an *extension of the casting origin* — a magical signal booster, not a range extender.

**Effect:** A Relay node allows a casting hub to **project its cast origin** through a chain of Relay nodes. When a spell is initiated, the player may designate any chain of Relay nodes reachable from the hub; the spell then originates from the terminal Relay — as if cast from there. The intermediate chain is transparent (does not consume hops to traverse). The hub still acts; the Relay shifts where the spell begins.

**Chain behavior:** A sequence of Relays pushes the effective origin progressively deeper — or to a high-degree position the hub itself can't reach. Like RA2 Prism Towers: each Relay rebroadcasts from its own location, with potential amplification.

**Degree at the relay:** The terminal Relay's degree determines the spell's tier and branching factor from that point. Routing to a Relay on a high-degree node unlocks higher-tier spells the hub might not access on its own — a remote casting tower.

**No downside:** No cooldown, no hop penalty for using a relay. Dedicating a node slot to Relay is the cost — a non-attacking, non-blocking slot whose value is purely positional.

**Damage bonus *(OPEN)*:** Routing through N Relays may add a damage multiplier or flat bonus (the signal concentrates as it rebroadcasts). Whether this is per-Relay (stacking) or flat for using any relay at all is unresolved; TBD in playtesting.

---

## TBD Addons

Concepts that appeared in design discussion but have not been formally designed. Listed here for tracking. **Not confirmed mechanics.**

---

### Anti-Magic *(concept — TBD)*

**Proposed concept:** A node carrying Anti-Magic adds +1 to the effective hop cost of any spell passing through it. A spell with N hops remaining that would normally propagate to neighbors with N−1 hops exits with N−2 instead — consuming one extra hop at the anti-magic node, reducing propagation depth and spread.

**Effect in play:** Anti-Magic nodes in a chokepoint form magical terrain denial — enemy spells enter with N hops and leave significantly depleted. A ring of Anti-Magic nodes around a cluster could render it effectively magic-immune.

**Branching interaction:** Fewer remaining hops reduce the spell's effective branching factor at downstream nodes (if degree-gated by remaining hops). Anti-Magic doesn't just cap range — it reduces spread as a spell penetrates deeper.

**Counterplay:** Route spells *around* anti-magic clusters via Relay chains, projecting the cast origin past the denial zone rather than through it.

**Why not negative hop costs:** The inverse direction — nodes that *restore* hops (negative edge cost) — was considered. Standard Dijkstra/BFS breaks with negative weights; nodes giving back hops would loop indefinitely through a negative-cost node to accumulate free range. Bellman-Ford handles negative weights but not negative *cycles*, and any graph loop through a negative-cost node is a negative cycle. Anti-Magic (+cost, always positive) is the clean design lever for hop-cost manipulation — no algorithmic special-casing required.

---

### Conduit *(concept — TBD; likely specialization, not addon)*

**Proposed concept:** A node with 0 hop cost for spell propagation. Spells pass through Conduit nodes without consuming hops — a magical highway. A chain of Conduit nodes allows spells to travel far with no range penalty.

**Classification question:** This reads as a field-generated intrinsic specialization more than a player-applied addon — zero-cost transit feels like rare terrain rather than equipment. Resolve alongside Anti-Magic once magic propagation is stable.

**Interaction with Anti-Magic:** An Anti-Magic node immediately downstream of a Conduit chain would consume the hops the Conduit preserved — the two effects cancel locally, which is interesting territory.

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

## Addon Design Principles

1. **Addons change behavior; modifiers change stats.** A node with Armor Ring is defensively stronger because of behavior (damage reduction per hit). A node with a `+3 armor` modifier is stronger because of a stat. Both contribute to the same effective armor, but through different pipeline stages.

2. **An addon should be legible from the node's visual.** Players should be able to look at a node and understand why it behaves differently. Addons need distinct visual indicators.

3. **Addons don't define node type.** A Red node with Armor Ring is still a Red node — it provides STR, it attacks with melee, it just also reduces damage to itself. The color identity doesn't change.

---

## Open Questions

1. **Addon/Specialization boundary:** Does the distinction hold up in practice, or does everything collapse into one system? Could revisit after first playtests. (Also tracked in [skill_node_specializations.md](skill_node_specializations.md).)
2. **Addon transferability:** Can addons be moved from one node to another? Removed entirely? Or are they permanent once applied? If removable, they're more like equipment. If permanent, they're closer to specializations.
3. **Addon stacking:** Can a node have multiple addons simultaneously? Are there compatibility rules? (E.g., Armor Ring + Reinforcement = yes. Lifeline + Lifelink = probably not, doesn't make sense.)
4. **Buffer addon vs Buffer specialization:** Resolve by playtesting whether the capability difference is meaningful enough to warrant two systems.
5. **Gate persistence on turn end:** Does a toggle persist past turn end, or revert? Leaning persistent.
6. **Gate self-island warning frequency:** Warn once, or every time a toggle would island the owner's own constellation?
7. **Addon lifecycle on node death (general):** Refund / addon-breakage policy when an endpoint (Gate) or carrier node dies — does the addon drop, refund, or break? Deferred general question raised by the Gate's 2-endpoint lifecycle.
8. **Gate vs. Buffer identity:** Both are "temporary topology" utility — keep distinct (edges vs. nodes) or let one absorb part of the other's role? Revisit if play shows the identities blur.
9. **Relay damage bonus:** Is the amplification per-Relay (stacking) or a flat bonus for using any relay at all? TBD in playtesting.
10. **Relay routing cost:** Is the relay chain transparent (free origin-shift, no hop cost to traverse), or does routing through relays consume hops to reach the terminal relay? Direction: transparent (free); confirm in playtesting.
11. **Anti-Magic / Conduit classification:** +1-hop-cost and 0-hop-cost as player-applied addons or field-generated specializations? Resolve once magic propagation model is stable.
