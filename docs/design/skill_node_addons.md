---
status: settling
---

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

### Buffer

> **Discontinued indefinitely (owner, 2026-10-05); parked, not built.** Its reach is bounded by the attack it serves, not by a turn phase.

**Effect:** When composing an attack, tapping a Buffer node **temporarily allocates existing field nodes** — reaching across the *real* graph to bring an attacking node/pivot to the front (melee), claim firing stubs (ranged), or pad a casting hub's degree (magic). It does **not** spawn new vertices; it plays with the real skill-node/edge graph. After a tap the Buffer goes on **cooldown** (cannot re-tap next turn — preserves cadence). All temporarily-allocated nodes **revert when the attack they enabled resolves**.

**Universal across all colors.** Melee/ranged/magic all benefit — it is reach, not a melee-only tool.

**Interaction with `pressure_capacity`:** The entity stat `pressure_capacity` would be the **reach/budget** — how many field nodes a single tap can temporarily allocate.

**Notes:** Buffer is **utility-only — no attack of its own** (not a firing leaf, not a caster, not a blade source). Dedicating a node slot to one is a real tradeoff: without Buffers you commit your shape up front and fight with it; with them you extend mid-fight and snap back. This is a *capability* addon, not a passive bonus.

**Shelved alternative:** a "ghost extension" version that spawns *new* temporary vertices was considered and dropped — it read as a cop-out and cluttered the board. Reach plays with real nodes only.

---

### Winch

> **Determinism fork (owner, 2026-10-05):** *"cool but how are we gonna ensure that after pulling, the entirety of the graph (here as one giant spring system) has settled to pixel identical values for each peer? While also this settling ideally is just physics engine doing its thing"*. Note the Effect below is already math-only: if gameplay reads a deterministic effective distance and the spring settle is presentation, no peer needs a pixel-identical layout. Open.

**Effect:** Exerts a pull force on adjacent nodes, reducing effective euclidean distance between this node and its neighbors, as an ability that targets one selected neighbor per turn (reeling in 1 edge). Does not create or delete edges — purely a math adjustment to the distance calculation.

**Use cases:**
- Draws neutral or loot nodes (that are adjacent to this node) closer within the euclidean distance framework. Makes them easier to target with ranged attacks or bring within aura range.
- Keeps Serpent class nodes close to the core spatially despite winding hop-paths.
- Reduces penalty for Serpent class nodes that would otherwise be far euclidean from the core.

**Does not do:** create new adjacency (no new edges), delete edges, change graph topology in any way.

**Winch cap:** There must be a maximum effective euclidean reduction per node. Otherwise the Winch trivializes the Serpent's euclidean penalty and potentially makes all nodes appear geometrically adjacent to everything. Cap value TBD in playtesting.

---

### Spikes *(defensive collision model OPEN)*

**Candidate worth exploring:** spikes **damage or sever the edges/faces of an incoming phantom blade** on collision, a **physics-layer melee defense** (it only matters vs. melee, not ranged/magic). Because a phantom blade's rigidity comes from triangulation, **popping an edge can de-rigidify a braced blade into a floppy whip mid-swing.** This is thorns reframed: instead of flat counter-damage to the attacker's node HP, spikes attack the attacker's *blade structure*.

*Rejected/uncertain:* spikes damage *your own* nodes when struck. Leaning **no**.

**Open collision questions (dedicated pass, do not implement until specified):** what exactly does contact do (damage an edge's HP? sever it outright? cost the blade rigidity?), how it is balanced, and what feels right.

**Halo integration:** the Halo shell aura grants spikes, so the shell becomes a literal **spike-ring / wall against incoming melee blades.** Counterplay: a well-placed **ranged** attack can knock out a shell node and **distort the wall**. See `core_classes.md` (The Halo).
- **Proposal *(OPEN)*:** the spikes aura targets **any** node at shell distance, *including enemy-owned ones*; if an enemy allocates a node onto your ring, your aura spikes *their* node. Positional, not ownership-gated. Gate this behind the collision-model decision above.

---

### Gate *(confirmed — owner design pass 2026-09-30, #187)*

> **The addon whose unit is an edge.** A Gate spans **two endpoint nodes** and makes the edge between them switchable: **open** is a real edge in every sense, **closed** is no edge at all. Whether an edge existed there before is irrelevant; "depower an existing edge" and "create a new one" are the same flip.

**Placement — any unobstructed pair.** Owner, 2026-09-30: *"Any center to center unobstructed (by node circles or edges) node"*. The segment between the two centres must cross no node disc and no edge, and no other gate may already run there. A closed gate still occupies its span, so nothing can later route through it; that preserves planarity. **Procgen scores a pair by the chasm it bridges**: a pair already close in hops (two corners of a triangle) is a weak gate, and a pair far apart in hops but close in space is a strong one. Owner, 2026-09-30, on the sticking-out triangle: *"it's not really a chasm being bridged hence the consideration of the pair is penalized in procgen"*.

**Control — your side only.** A gate may be toggled by an entity that owns at least one endpoint, **provided the other endpoint is neutral or also its own**. A gate touching another entity's node is frozen. Owner, 2026-09-30: *"By design you can't affect enemy nodes by toggling your own held edges, can't bridge toward enemy occupied nodes (but killing that node first makes it unoccupied, free game, bridge breach."* So the **breach** needs no extra rule: kill the far node and the gate is yours to open.

**Toggling.** You can toggle a single gate (click its span), or all your gates at once (a HUD button or a hotkey), at any point in your own turn. Toggles **persist** across turn end. Each gate is also **locked or unlocked** (your own management preference, not world state): bulk actions skip locked gates, so locked-open is "always on" and locked-closed is "always off". Two keys cover the common flow: unlock all, then toggle. **Toggle-all is order-independent**: every flip applies first, then connectivity is judged once. A component that one closing gate would strand, but another opening gate in the same toggle-all reconnects, stays allocated.

**Self-cutting is allowed, behind one warning.** A flip that would strand your own nodes (a deallocation cascade) shows one warning and then goes through when you confirm. The warning only ever concerns your own territory, because the control rule means a flip can never cut anyone else. Owner, 2026-09-30: *"one warning when you try to turn off an edge that would hurt you (forcing deallocation cascade) but otherwise even that's permitted"*.

**What each use is for** (owner, 2026-09-30: *"All points are excellent"*; the weakest two are last):
- **Wormhole.** Open a gate from your node to a neutral node across a gap. The far end becomes a frontier node that you allocate at the normal SP cost: a portal, a flank, a chasm crossing.
- **Drawbridge / firebreak.** Spell propagation and blade rigidity ride edges. Closing a gate before ending your turn removes that path, which is safe only if your territory is padded with redundant connections. The warning is the tension.
- **Melee: brace, whip, and the fuse.** At launch, an open gate triangulates the blade (rigid) and a closed one leaves it a whip. Mid-swing, **timed fuses** set in the attack plan, one per gate in the blade and linked by default, flip each fused gate at its own time *t*: the blade's copy of the edge parts and the far side flies off on its own momentum (free-flight severance). The real gate flips too, and your territory cascades if it isn't padded. Owner, 2026-09-30: *"a timed fuse as part of the attack plan … user able to scrub the fuse timer along the duration the blade nodes are hot with preview matching"*. The fuse's self-cut warning is shown **at plan time**: the preview resolves the fuse, so the nodes it would strand are shown before launch, and launching is the confirmation.
- **Amputation / quarantine.** Deliberately cut off a limb carrying a status or DoT, at the cascade's cost in health and wounds. If an affliction ever spreads along edges, a closed gate is a quarantine line.
- **Ranged: gun ports** *(niche, mostly topological)*. Cut the edge across a protruding triangle and both corners become leaves, which are volley origins.
- **Magic: degree pump** *(weakest)*. Opening raises endpoint degree for degree-gated casts, but usually you just leave it open, and the only downside is spell exposure.

**The flip has a body.** Opening is a glowing rope thrown from one endpoint that latches on the far node and is pulled taut with a *thwang*, a plucked string whose pitch falls with its length. Closing snaps it: the halves whip back into their endpoints. This is presentation only; the topology flips at the logical instant (see `docs/domain/presentation-clock.md`).

**Relationship to existing systems:**
- **Edge-deletion invariant / Edgelord — not violated.** The combat doc's invariant ("no mechanic may leave a region permanently unreachable") and the Edgelord's *permanent* edge add/remove specialty (Bleeding Edge) are untouched, because a gate is always reversible. Permanent severing remains Edgelord's domain. (Mirrored in `combat_system.md` — Edge-cutting jab invariant.)
- **Buffer — distinct.** Buffer temporarily reaches across the *existing* graph for one attack; the Gate *rewires* it, persistently. Revisit if play shows the two identities blur.

**Open:** what happens to a gate when an endpoint dies, and whether removing one refunds anything or reverts its flip. This is part of the general addon-lifecycle question in Open Questions.

---

### Lifeline

> **Strong; merge candidate (owner, 2026-10-05):** *"great but strong. Could merge it with proposed (healing and or cleansing) Fountain addon perhaps"* (the Fountain is `damage_over_time.md` § Cures).

**Effect:** If any sub-graph containing nodes within N hops of this Lifeline node becomes an island (no path to the entity's core), those nodes receive a **1-turn grace period** before dissolving. During this grace period, the entity may re-establish a connection to the core — if they succeed, the island is saved and the timer cancels. If the grace period expires without reconnection, the island dissolves normally (SP Reservation fires for all nodes).

**Counter-play:** After the snipe that created the island, the chokepoint node (where the bridge used to be) is now neutral. The attacker can immediately try to allocate it — spending 1 SP to claim the chokepoint. If they succeed, the defender has no path to reconnect even within the grace period. If the defender can bridge through a different route before the attacker blocks — the island survives.

**Calibration:** The hop radius N of Lifeline's protection zone is a tuning parameter. Too large: oppressive safety net. Too small: rarely meaningful. Needs playtesting.

**Rarity:** Uncommon. Not a free safety net every entity gets — found through loot, class-specific rewards, or rare field nodes.

---

### Lifelink

> **Never procgen-rolled (owner, 2026-10-05):** *"great but VERY strong, maybe too strong. If we add it it's likely not a procgen randomly rolled one, exclusively for keystone or some mechanics for a future coreclass"*.

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

> Owner, 2026-10-05: *"Anti magic or conduit or void: needs more design"* — one open fork for this, Conduit, and a possible Void.

**Proposed concept:** A node carrying Anti-Magic adds +1 to the effective hop cost of any spell passing through it. A spell with N hops remaining that would normally propagate to neighbors with N−1 hops exits with N−2 instead — consuming one extra hop at the anti-magic node, reducing propagation depth and spread.

**Effect in play:** Anti-Magic nodes in a chokepoint form magical terrain denial — enemy spells enter with N hops and leave significantly depleted. A ring of Anti-Magic nodes around a cluster could render it effectively magic-immune.

**Branching interaction:** Fewer remaining hops reduce the spell's effective branching factor at downstream nodes (if degree-gated by remaining hops). Anti-Magic doesn't just cap range — it reduces spread as a spell penetrates deeper.

**Counterplay:** Route spells *around* anti-magic clusters via Relay chains, projecting the cast origin past the denial zone rather than through it.

**Why not negative hop costs:** The inverse direction — nodes that *restore* hops (negative edge cost) — was considered. Standard Dijkstra/BFS breaks with negative weights; nodes giving back hops would loop indefinitely through a negative-cost node to accumulate free range. Bellman-Ford handles negative weights but not negative *cycles*, and any graph loop through a negative-cost node is a negative cycle. Anti-Magic (+cost, always positive) is the clean design lever for hop-cost manipulation — no algorithmic special-casing required.

---

### Conduit *(concept — likely dropped; see note)*

**Proposed concept:** A node with 0 hop cost for spell propagation. Spells pass through it without consuming hops — a magical highway.

**Why likely dropped:** Initial spell targeting is **euclidean** (`range: euclidean casting distance, caster node to initial target` — see `spells.md`). Hop costs only matter in the **propagation phase** after hitting the first target. Since spells mostly don't propagate *through your own nodes* (no-friendly-fire default), a Conduit node in your constellation is nearly useless — it can't extend initial reach (euclidean gate), and propagation doesn't route through you. Owning one is almost purely a **liability**: enemy spells propagating into your territory get free hops passing through it.

**One surviving edge case:** neutral-territory Conduit nodes as rare field terrain that both players can exploit. Interesting in theory; complicated to balance. Revisit only if propagation-through-own-territory ever becomes a design choice.

**Naming clash:** "Conduit" is already a candidate name for **Tethers** in `lore.md` — use a different name if this ever revives.

**Interaction with Anti-Magic:** would cancel locally — 0-cost immediately adjacent to +1-cost nets neutral.

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

1. **Addons change behavior; modifiers change stats.** A Bunker node is defensively stronger because of behavior (it blocks a blade). A node with a `+3 armor` modifier is stronger because of a stat. Both contribute to the same effective armor, but through different pipeline stages.

2. **An addon should be legible from the node's visual.** Players should be able to look at a node and understand why it behaves differently. Addons need distinct visual indicators.

3. **Addons don't define node type.** A Red node with Bunker is still a Red node — it provides STR, it attacks with melee, it just also blocks blades. The color identity doesn't change.

---

## Open Questions

1. **Addon/Specialization boundary:** Does the distinction hold up in practice, or does everything collapse into one system? Could revisit after first playtests. (Also tracked in [skill_node_specializations.md](skill_node_specializations.md).)
2. **Addon transferability:** Can addons be moved from one node to another? Removed entirely? Or are they permanent once applied? If removable, they're more like equipment. If permanent, they're closer to specializations.
3. **Addon stacking:** Can a node have multiple addons simultaneously? Are there compatibility rules? (E.g., Lifeline + Lifelink = probably not, doesn't make sense.)
4. **Buffer addon vs Buffer specialization:** Resolve by playtesting whether the capability difference is meaningful enough to warrant two systems.
5. **Addon lifecycle on node death (general):** Refund / addon-breakage policy when an endpoint (Gate) or carrier node dies — does the addon drop, refund, or break? Deferred general question raised by the Gate's 2-endpoint lifecycle.
6. **Gate vs. Buffer identity:** Both are "temporary topology" utility — keep distinct (edges vs. nodes) or let one absorb part of the other's role? Revisit if play shows the identities blur.
7. **Relay damage bonus:** Is the amplification per-Relay (stacking) or a flat bonus for using any relay at all? TBD in playtesting.
8. **Relay routing cost:** Is the relay chain transparent (free origin-shift, no hop cost to traverse), or does routing through relays consume hops to reach the terminal relay? Direction: transparent (free); confirm in playtesting.
9. **Anti-Magic / Conduit classification:** +1-hop-cost and 0-hop-cost as player-applied addons or field-generated specializations? Resolve once magic propagation model is stable.
