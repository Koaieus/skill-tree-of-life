# Combat System Design — Skill Tree of Life

---

## Philosophy

It's D&D on a skill tree. Stats and concepts join together to make combat. Two hard requirements:

1. **The rules must be legible.** A player should be able to learn how combat works. No hidden formulas the player can never reverse-engineer.
2. **Base-10 is the anchor.** See the Scale Anchor section below. Numbers stay legible and small enough to reason about; four-digit numbers are a design failure at this scale.

**Gameplay first. Numbers exist to serve smooth, interesting play.**

The two most basic laws:
- **Damage increases damage.**
- **Defense reduces damage.**

---

## Scale Anchor

**Base-10 is the anchor.**

- Default node HP: **10**
- Core attributes (STR, DEX, INT) at run start: **≈ 10 each**
- Calibration target: **3–4 unbuffed leaf volleys ≈ dismember one unbuffed node**
- Offensive and defensive buffs scale from there (e.g. +1 STR on an early skill node; +10 STR at the Apex end of the meta tree)

The goal is never to scale into the thousands and never to need e-notation. A `+10` to an attribute should feel *strong*.

**Scaling shape [OPEN]:** Linear is the baseline (50 DEX ≈ 5× ranged proficiency — legible, easy to balance). Flag for revisit if linear flattens build diversity. Not resolved; see Open Questions.

---

## The Attribute Scaling Spine — the //10 model

*Unifying rule across all three attack colors. Newer than the per-mode formulas sketched below; where they differ, this governs. All numbers illustrative — lock the concept, not the value.*

> **outgoing = base (once) + (attribute scaled by //10) × (number of graph instances)**, with defense applied **once per target node**.

The attribute sets *per-instance magnitude*; the **count of instances is always a topological quantity** the player grows. Each color weaponizes a **different graph primitive**:

| Color | Attribute | Primitive (the "instances") | Player's count lever |
|---|---|---|---|
| R | STR | swept **edges** (+ spiked nodes, + faces) of the phantom blade | blade size & composition |
| G | DEX | firing **leaves** in a volley | sprout stubs (grow degree-1 ends) |
| B | INT | spell **damage events** (initial + each hop + loop returns) | spell propagation, gated by casting-node degree |

**Ends, hubs, edges** — three colors, three primitives, one formula. This force-feeds the graph into every attack mode.

### //10 as a gear ratio (not a rounding choice)

The integer division is the **gear ratio between two economies**, deliberately decoupling them:

- **Modifier economy:** loot can hand out chunky values (`+5 STR`) that feel good and stay interesting.
- **Damage economy:** stays in single digits — legible, and tunable against health/mitigation *independently* of how generous modifiers are.

We can retune "how much STR a node grants" without it cascading into damage numbers we'd then have to rebalance HP and armor around.

### Breakpoints are a feature

Flooring the **attribute** (e.g. `STR//10`) creates stepwise power gates. A `+3 STR` node "cashes in" only when it tips you past the next multiple of 10 — and it **can't get you there without every other modifier that brought you to that threshold.** Attribute accumulation becomes a shared pool where each contribution is necessary even when individually invisible.

**Required guard — show the breakpoint.** Surface it in UI on hover (e.g. `STR 28 → 2/edge, +2 to next tier`). Visible, it is satisfying min-maxing; hidden, it is exactly the opaque formula combat must never have. Same mechanic, opposite feel, decided by the tooltip.

> **Open consideration:** whether magnitude floors *per instance* (clean breakpoints — the current choice) or floors the *summed total* (small modifiers contribute immediately). Chose **per-attribute floor** for the gear-ratio and breakpoint benefits. Revisit only if play shows small modifiers feel dead.

---

## Terminology — Cut Vertices vs. Bridges

Two distinct graph objects, kept precise throughout this document. Both are central to graph combat and come up constantly.

- **Cut vertex** (a.k.a. articulation point) — a *node* whose removal disconnects or islands part of the graph. The canonical snipe target.
- **Bridge** (a.k.a. cut-edge) — an *edge* whose removal disconnects the graph. What Bleeding Edge severs.

A cut-vertex snipe kills a node; a bridge cut deletes an edge. Different tools, different counterplay.

---

## The Damage Pipeline

Single, readable resolution order:

```
outgoing = base[attack_type] + attribute_bonus + shape/node modifiers
outgoing ×= type_advantage(attacker_color, target_color)
(roll crit) → if crit, apply crit effect

per target node:
    taken = max(damage_floor, outgoing − armor − resist[attack_color])
    target_node.health −= taken
    if attack is melee and target_node.thorns > 0:
        attacking_node.health −= target_node.thorns   ← not reduced by attacker's armor
    if target_node.health <= 0 → node severed → island check (immediate)
    if attacking_node.health <= 0 → attacking_node severed → island check (immediate)
```

**Combined strikes apply defense once (per *target*, not per-hit).** The ranged **volley** (many leaves on one target) and the melee **phantom-blade swing** (many contacts — edges + spikes + faces — on one target) sum their contributions into a single `outgoing` per target, and `armor`/`resist` subtract **once** from that total. See the scaling spine and Melee.

**`damage_floor`:** replaces the old hardcoded `max(1, ...)`. Global default `1` — behavior identical for most entities. The Bulwark class starts at `damage_floor = 3` with a class path to reduce it. Below `0`, the entity heals when hit (intentional extreme-build payoff). See `entity_stat_board_prototype.md`.

**Thorns:** flat counter-damage returned on a melee hit to the attacking node, not reduced by armor. The Halo class's aura grants thorns to shell and near-shell nodes from `thorns_base`. See `skill_node_addons.md` and `core_classes.md`.

---

## Attributes, Colors & the Attack Triangle

The roster grew to **six attributes** — three attack (prevalent), three utility (rarer) — each earning its slot via a real graph-native mechanic (the standing bar: *no stats for stats' sake*). The old "W = XP economy" role is **reassigned**: White now owns durability (CON), and XP/growth moves to a new Gold color (WIS). See the migration note below.

| Color | Attribute | Role | Attack | Notes |
|---|---|---|---|---|
| **Red** | STR | melee | Adjacency / phantom blade | Per-contact damage and blade size (`STR//10+1` nodes). Beats Blue. |
| **Green** | DEX | ranged | **Euclidean**, leaf-only | Per-leaf damage (`1/node @ 0 DEX → 2/node @ 10 DEX`). Beats Red. |
| **Blue** | INT | magic | **Spell-native (graph)** | Per-instance **potency, never reach**. Beats Green. |
| **White** | CON | durability | none | Scales node/core HP; **+weight for armor modifiers** in affix generation. No attack mode. |
| **Gold** | WIS | XP / growth | none | Wisdom ≈ accumulated experience → **XP-gain rate**. Carries the most valuable growth-oriented modifiers. |
| **Purple** | PER | perception | none | Vision + sensor range. Information *is* the weapon (spot cut-vertices/bridges early, scout). No attack needed; one may surface later. |
| **X** (Other) | — | — | — | Mystery / keystone / special nodes (rule-changers, sockets). Not yet specified — see GDD §3. |

- **RGB are most prevalent**; White/Gold/Purple are rarer utility colors.
- **PER, not WIS, owns perception.** WIS was reassigned from senses to XP-gain; PER is the dedicated senses attribute. Splitting them gives both a clean intuitive meaning.
- Illustrative gearing (Balance-phase, *pool-appropriate* — **not** the damage //10): PER → `+1 sensor_range / 10 PER` (integer, hop-based) and `+2% vision_range / PER` (smooth, euclidean); WIS → a % XP-gain multiplier; CON → HP + armor-affix weight.
- **`coolness` → non-core → prestige only.** Does nothing mechanically; tallied at end credits. Thematically the purest "**all edge, no point**" — style with no anchor — so winning a coolness build is the cardinal aesthetic heresy, and the Fairy should have opinions. Procgen-sprinkled. The joke-CHA of the set.

> **Migration note (White → CON; economy → Gold).** Older docs (this one included, plus `lore.md`, `core_classes.md`, the GDD) describe **White nodes as the XP/economy lifeblood**. Under the new roster that role belongs to **Gold (WIS)**, and **White becomes the durability color (CON)**. This is the newer intent but is *still potentially not final* — the central tables (here, `stat_system.md`, `entity_stat_board_prototype.md`, GDD §3) reflect the six-color model; per-class economy prose (Hive, Harvester, Halo interiors) still says "White" and should be read as "the economy color (Gold)" until a dedicated sweep migrates them.

### Colors are content, not a graph-coloring

The 4-color-theorem resonance (planar graphs are 4-colorable) is a **red herring to note against**: node color here is **content identity** (which attribute/role a node carries), not an adjacency-coloring. We do *not* want locally-distinct colors. Procgen should **cluster like-colors into regions** (Red territory, Blue territory) for an interesting, biome-like battlefield.

- **Affix pools: weighted-mix.** A node's extra modifiers are drawn from a **color-tilted pool with nonzero weight on everything** (subject to the Gold×Purple exclusion below). Nodes lean their color but can roll anything; off-color rolls are exciting build-pivot seeds. The weights are a per-color identity knob.
- **Hard exclusion: XP (Gold) and vision/sensor (Purple) modifiers never co-occur on one node** — growth + knowledge together is too all-powerful. Gold and Purple are mutually exclusive on a single node.
- **Whether to color nodes at all** remains open (the content still exists either way).

**Targeting modes:**
- **Ranged (G):** euclidean distance from a firing **leaf** to the target. `attack_range` limits this. Pure geometry.
- **Magic (B):** each spell defines its own graph-native targeting (hop count, fork behavior, propagation depth), scaled by INT, **gated by owned-subgraph degree** (owned allocated neighbors only; unallocated and enemy nodes do not contribute — see Degree-gated casting). `attack_range` does **not** apply to magic. Rare drain/leech spells may explicitly count all incident edges instead.
- **Melee (R):** adjacency. You hit what you're next to.

**Triangle (R › B › G › R):** lives primarily in emergent per-color `resist_*` stats. A small hardcoded `type_advantage` baseline may backstop early-game — decide alongside armor (both edit `taken`).

**Dual-color nodes:** A R/B node picks which color it attacks with per swing. Open: free choice per attack, or inherited from source node?

**Utility colors (White/Gold/Purple):** No attack, no triangle slot. **White (CON)** scales node/core HP and weights armor affixes; **Gold (WIS)** drives XP-gain and carries growth modifiers — the economic objective entities fight over; **Purple (PER)** drives vision/sensor range (information as weapon). See the roster table above.

---

## Perception & Fog of War

Two-layer system. Both entity-level stats. Per-node position determines coverage zone.

| Stat | Basis | What you see | Default |
|---|---|---|---|
| `sense_range` | **Hops** from any owned node | Silhouette: node exists at position X, no details | 3 |
| `vision_range` | **Euclidean** from any owned node | Full detail: node type, HP, visible modifiers | ~4 |

Beyond `sense_range`: total fog. Inside sense but outside vision: silhouette only. Inside vision: full information. A silhouette-only node can still be targeted by ranged attacks if within `attack_range`. `vision_range` belongs on the entity stat board (not on individual nodes — legacy code misplaces it).

---

## Turn Structure — the three-phase turn

One attack per turn is the working baseline (see Open Questions — action economy). The turn is structured in **three phases**, where *the phase an allocation happens in is itself the temp/permanent flag* — no second SP pool, no per-node tracking, no real/temp toggle. (This supersedes the flat ordered list and the rejected "temp SP" idea; full SP accounting in `entity_stat_board_prototype.md`.)

1. **Deployment** — *assess*, then spend SP and `deallocation_points` to **permanently** allocate/deallocate. Optionally deallocate first to "move" the constellation across the field. Allocating a node extends `vision_range` (euclidean, full detail) from it and makes it a `sense_range` sensor (hops, silhouette only) — peeking into the Fog of War *structurally* without revealing node contents or ownership. No need to spend all SP. Move the core up to `movement_speed` hops along owned edges.
2. **Battle** — act: **one attack** (ranged volley from leaves / magic spell from a degree-gated node / one phantom-blade melee swing). **Tap buffer nodes** to *temporarily* allocate existing field nodes for reach (bring a pivot/attacking node forward, claim firing stubs, pad a casting hub's degree). These temp allocations live **only this phase**; buffer goes on cooldown after a tap. Special abilities / items resolve here (some gated to specific points).
3. **Consolidation** — spend more SP/DP to finalize and optimize shape. Per battle-phase temp node: **promote** it (pay 1 real SP → permanent) or let it **drop**. Then end turn — enemies act.

**Why it's clean:** one SP pool; whether an allocation persists is decided by *when* (phase), not a tagged currency. **No islanding** — permanents commit only in Deployment/Consolidation, and a permanent allocation still requires a permanent neighbor, so nothing solid ever hangs off a node about to revert. **Mid-turn level-up** is a non-issue: a +1 lands in the one pool and is spendable under the current phase's rules.

NPC turns resolve by the same rules; the player sees them play out in full only inside their vision, otherwise fast-forwarded unless something happens in view.

> **Naming nit:** abbreviation for deallocation points (DP vs DAP) — cosmetic, settle in the docs. **TurnManager impact:** this is a turn-flow change (deployment → battle → consolidation), not just a stat change — see `systems/turn_manager.gd` when the combat loop is rebuilt.

*(Mirrors GDD §2. The attack count, and whether move/reshape/attack share a budget, are open — see Open Questions.)*

---

## Ranged Attacks

**Firing origin: leaf nodes only.**

A **leaf** is a node of degree 1 in the entity's *own allocated subgraph*. Only leaves may fire ranged attacks; non-leaf owned nodes cannot.

**Why this is graph-native:** tendrils and stubs become firing ports. Growing ranged capability means sprouting stubs off a filament (turning an I-shape into an E-shape adds 3 firing leaves). Compact cluster builds lose ranged presence. Ring builds (zero leaves by definition) cannot fire ranged at all — they trade ranged offense for topological resilience.

**Volley model:**
- Per turn the entity fires **1 volley** by default. A second volley is a stat/class upgrade, not baseline.
- A volley = the player selects one target node; every owned leaf within euclidean range of that target fires simultaneously.
- **Damage:** per the [scaling spine](#the-attribute-scaling-spine--the-10-model), each firing leaf contributes `DEX//10` (target feel: `1/leaf @ 0 DEX → 2/leaf @ 10 DEX`). **`base_ranged` is counted *once* per volley, not per leaf** — so a converged volley dismembers weak nodes without one-shotting healthy ones. Armor and resist apply **once** to the combined total (per-attack).
- Range is the natural volley-size cap: you cannot get 40 leaves within one target's euclidean radius. No explicit leaf cap needed.

```
outgoing  = base_ranged + (DEX//10) × (firing leaves in range)
taken     = max(damage_floor, outgoing − armor − resist_g)     ← once per target
```

**Two intended outcomes:**
- Converged leaves → dismember a weak node. A comb of leaves on a low-HP target can one-shot it.
- 1–2 overextended leaves into a stronghold → won't cut it; armor absorbs the trickle.

**Leaf cooldown:** none. Leaves are always ready. The 1-volley/turn cap is the full economy — no per-leaf cooldown on top.

**Crit:** global `crit_chance` (5%) and `crit_mult` (×2) to start.

### Ranged identity — the cut-vertex sniper *(open: GitHub #11)*

Ranged's signature role is **precision reach**: it is the only attack that can pick and delete a *specific, deep* single node, so its highlight is **sniping cut vertices to trigger island collapse.** Kill a cut vertex and the island rule severs every region on its far side from the core (1..N−1 nodes) in one cascade — worst case, an enemy with its **core on a leaf** loses its *entire body* when you snipe the core's sole neighbor. Self-balancing: a **2-connected** constellation (no cut vertices) is immune, so *"be 2-connected or get sniped apart"* is a real defensive build axis; against dense enemies ranged falls back to single-target burst. The cut vertex still has CON-scaled HP — the payoff is the **cascade when it finally drops**, not single-shot lethality. Role triangle: **melee = area, magic = topological reach, ranged = precision single-target + cut-vertex surgery.**

**Frontier / Pioneer class note:** since all leaves are now generic firing ports, Frontier's identity must be differentiated. Direction: Frontier *hardens* its leaves (defensive buff to degree-1 nodes), enabling a forward-push leaf playstyle rather than sit-back kiting. To be finalized in `core_classes`.

---

## Magic (Graph-Magic) — Spells

**Magic is graph-math made into a weapon.** Each spell defines its own propagation mechanism — a graph-theory primitive, not a generic attack. INT scales potency; the spell's *shape* is inherent. `attack_range` does not apply.

```
per damage instance:  outgoing = base_magic + INT//10    (or spell-specific formula)
                       taken    = max(damage_floor, outgoing − armor − resist_b)   ← once per target
instances            = initial hit + each hop + each self-loop return
```

Per the [scaling spine](#the-attribute-scaling-spine--the-10-model), **INT scales per-instance potency, never reach.** Buying hops with INT is rejected (it breaks board legibility; reach is the spell's identity). Reach grows only through the dedicated `bonus_hop_count` stat (below).

Magic's identity: it reaches targets that are geometrically far but **topologically close**. Design leans hard into this distinction from ranged.

### Magic — directional notes (balanced LAST)

Magic is the most calculable in advance (it's graph math — simulate total damage to derive the scaling rate) but the **combinatorics of topologies make it genuinely hard**, so it needs a set of **canonical attack situations** to pin scaling against. Expect heavy tweaking. Direction, not locks:

- **Friendly fire (lean):** **ON for propagating spells, OFF for purely targeted ones**, with a rare "discriminating" modifier to opt a spell out. Theology: a propagating spell follows *edges, not allegiances* — it flows wherever the graph leads, so casting into mixed/contested territory risks looping back into your own nodes. Makes directional casting a real spatial decision and keeps the shared graph dangerous. Confirm during magic balancing.
- **`bonus_hop_count` stat (new):** default 0. INT scales potency, never reach — reach grows only through this dedicated, **ultra-rare** stat. At most ~1–2 `+1` modifiers exist on the entire map. Ultra-powerful, a must-have chase item for wizard entities, and a **prime proliferation target** (proliferation efficiency scales inversely with rarity — see Loot Resolution — so duplicating it works but poorly).

### Degree-gated casting

A node's degree within the entity's *own allocated subgraph* determines what it can cast:

| Spell tier | Minimum degree required |
|---|---|
| Cantrip | 1 (any node, including leaves) |
| Minor | 2 |
| Major | 3 |
| Heavy | 4 |
| Ultimate | 5+ |

*Thresholds are calibration targets, not locked values.*

**Overqualified casting (degree bonus):** casting a lower-tier spell from an overqualified node (e.g. a cantrip from a degree-4 hub) adds a bonus — increased range, damage, fork count, or penetration. The hub is a Tesla coil firing a basic bolt.

**Degree default:** degree is counted over the entity's **own intra-entity subgraph** (owned neighbors only) unless the spell states otherwise. Rare / drain-flavored spells may count *any* incident neighbor, owned or not.

### Targeting primitives (spell design space)

Each primitive can spawn several distinct spells. Open this space slowly — too many spell types at once creates incomprehensible board states.

- **Forking propagation:** follows all available edges simultaneously from the source. A lightning spell forks along the graph's branching structure, creating area damage the player predicts from topology.
- **Greedy walk:** hops N times; at each junction retargets to the neighbor with the highest (or lowest) chosen stat/attribute. Climbs or descends the field's gradient.
- **Degree-reactive:** effect or hop behavior keyed to each successive target's degree — damage that amplifies through hubs, or a chain that continues only while degrees keep rising.
- **Allocation-boundary:** targets or prefers *unallocated* nodes, or jumps along edges crossing between enemy-allocated and unallocated territory. Reads the frontier itself as targeting data.

Design principle: every spell should feel like it *is* something that happens in a graph, not something that happens *to* a graph.

---

## Melee, In Depth

> **Supersedes the old "tap-and-recover" + abstract-shape model.** Melee shapes are no longer hitboxes that come from nowhere, and Buffer nodes are no longer melee fuel (they are repurposed — see `skill_node_addons.md` and the three-phase turn). The melee weapon *is your topology.*

### The phantom blade

**You select a connected set of your owned nodes; a phantom copy of that subgraph is swung as a weapon.** The shape is 100% your topology — consistent with how ranged reads leaves and magic reads edges.

**Geometry:**

- **1:1-scale copy** of the selected nodes — true geometry, true distances. The real constellation never deforms; the blade is a copy.
- **Induced, connected subgraph.** Pick vertices; the edges *between selected vertices* come automatically (edges to unselected nodes are excluded — a selected straight line is a clean line). The selection must be connected. Induced (not hand-picked edges) because it force-feeds your real topology onto the weapon. An "edge-trim" addon could allow shaping later; not core.
- **Handle = the attacking node, full stop.** No separate handle-pick. The blade is the connected subgraph rooted at the attacking node; that node is the **pivot**, pinned at its real position while the phantom sweeps.
- **Size:** attacking node (free handle) + up to `STR//10 + 1` blade nodes. At 0 STR you still get a handle+1 dagger, so melee never fully switches off.

**Cadence:**

- **One swing per turn** (action economy, same as ranged's one volley).
- **No source-node cooldown** — the blade is a copy, nothing is spent. Melee's cost is **structural** (blade-shaped filaments are cut-vertex-ridden) and **positional** (the attacking node must be where the fight is). Cooldown remains available as a tuning throttle if melee ever needs one, but is not baseline.

**Intentional early-game weakness.** Melee is deliberately weak early — early game is a wet-noodle fight across all attack types by design. The strongest *early* melee is a **"triangle on a stick"** — `(handle)—(triangle)` — the minimal rigid, faced blade. A triangle is 3 blade nodes, which needs `STR//10+1 ≥ 3`, i.e. **~20 STR**. Below that you have a handle+1 dagger (single rigid edge) or a handle+2 path (floppy, no face). Offense in general starts soft and scales hard.

### Melee damage model

For a swing, against each target node, count **contacts** — each phantom damage-element that sweeps the target during the motion:

- **Each edge** that sweeps the target (the baseline cutting surface).
- **Each spiked node** that sweeps the target (offensive payload; see thorns=spikes).
- **Each face** whose swept area covers the target (see faces).

Each contact deals `base + STR//10`. **Sum contacts per target; apply defense once per target.** Cap each element to **one contact per target per swing** for legibility and bounding.

So STR pulls double duty — size (`//10+1` nodes) and per-contact bite (`+STR//10`) — making melee roughly **quadratic in STR investment**. Intended ("can't be hit by a giant blade for weaksauce damage"); tune down if OP. Self-limiting: geometry caps single-target damage the way range caps volley size. **Big blades pay off in breadth.** This gives a role triangle for free: **melee = area control (chip line → heavy pan), ranged = single-target burst, magic = topological reach.**

**Faces (the "pan").** A selected cycle floods into a filled face. When the phantom swings, a far-out face sweeps a wide, fast **area**, not a line.

- **Face damage = Σ(its edges) + Σ(its vertex spikes) + B**, with B a bonus (≥1). The pan lands with the weight of what built it.
- **Shared-edge double-counting across adjacent triangles is a FEATURE** — it rewards triangulation, which is exactly what tensegrity wants. The thing that makes the blade rigid also makes it bite harder.
- A big cycle (e.g. 10 edges) summing big is *exactly right* — gated by the STR budget and the specific closed topology required to field it.
- **Tame runaway with the scalars** (B, per-edge base, or sublinear B in face size), **never the counting rule.**
- **Anti-double-dip:** a node inside a swept face takes the face's *bundled* damage (which already includes that face's edges) and does **not** also eat those same edges separately; it still takes any *non-face* edges grazing it, plus standalone spikes, on top.
- Trigger the face off **cycle presence** (a graph fact, always defined) rather than a geometric filled region (no runtime planarity guarantee). Render the fill when the cycle happens to be planar.

**Thorns = spikes (one stat — *sharpness*; motion decides which way it cuts).**

- **Stationary** thorny node → defensive: an incoming melee attacker impales itself (counter-damage, unaffected by attacker armor; hits the attacker's handle/attacking node). *(This is the existing Thorns mechanic — see below.)*
- **Swung** thorny node → offensive: drives its spikes through whatever it sweeps (a spiked-node contact).
- The terms are interchangeable; they draw from one stat.

**Core-swing (emergent, no new mechanic).** Because the handle is the attacking node and every node carries its payload into the swing: if your **core is the attacking node**, you swing *from your heart* — its payload amplifies the swing and your core is now forward and exposed. Big payoff, real danger (core positioning is a real risk). A melee class that invests offense (thorns/spikes/STR) into its core gets a signature finisher and pays for it in exposure. (Bonus: hands the Halo a melee option — swing your thorny shell.)

### Tensegrity — rigidity from topology

**Rigidity is not a stat, addon, or toggle. It is a physical consequence of triangulation,** computed from the blade's graph structure.

- A **triangulated** strip holds posture through the sweep → clean **swing/jab**.
- A **line or open quad** bends and flops → **whip**. (Whip needs no separate mechanic: a floppy chain *is* a whip; coil it with a tip spike and it uncurls into a flail.)
- A **square-grid patch is floppy** — a 4-cycle is a shearing mechanism (1 internal DOF). Bracing it with a diagonal makes two triangles → rigid. The classroom-bridge lesson; **bracing edges (diagonals) are a melee-rigidity build goal.**

This unifies three things previously treated separately: rigidity, the whip, and "cycles are naturally strong." Triangulate and you get rigidity *and* faces (area damage) *and* structural robustness at once — the heavy reliable cleaver. Sparse chains are the cheap reachy whip.

**It is graph rigidity theory.** 2D generic rigidity is decidable and cheap (Laman's condition / the pebble game), so **the game auto-detects sweep vs. wobble vs. whip from topology — no player toggle.** The player provides aim (the drag); the game owns the swing kinematics (drives the handle to snap a floppy tip properly). Keep the simulation **deterministic** so the ghost-trail preview shows the true outcome (essential for legibility, especially whips). Physics for <80 edge-bones is trivial in Godot.

**Grip = clamp, not pin (the handle is a hand).** The handle (attacking/pivot node) **welds its single edge into the swing frame** — you *hold* the weapon, so the **first joint is stiff by definition of gripping**, leaf or hub pivot alike (consistent with "handle+1 = single rigid edge"). Every *other* joint is an ideal free pin; downstream rigidity is **purely emergent from triangulation** — **no per-joint stiffness, no uniform global stiffness, no player floppiness toggle.** A uniform joint stiffness would rigidify sparse chains and mute the triangulate-or-flop axis; a rigidity toggle is either never-used or breaks tensegrity. The **only** dev scalar is a **weak global damping for sim stability + legibility** (deterministic preview = real outcome), kept low enough that a sparse chain still reads as a clean whip — *"shabby = whip" is a valid weapon, not a failure.* (Settled — GitHub #10.)

**Leaves are the haft, not weak melee.** A leaf pivot can't brace its first *internal* joint (that needs pivot degree ≥2), so a leaf-launched blade = rigid haft + a (possibly braced) head hinging at one point → the **mace / axe / flail** family (the hinge becomes tip velocity, not flop-snap). A degree-≥2 (interior/hub) pivot *can* brace that joint → the **cleaver / pan** family. Melee thus gets its own **leaf↔hub gradient**, paralleling ranged-from-leaves and magic-from-hubs. The real switch is **pivot degree ≥2**, not "handle on a cycle."

**Implementation phasing:** ship an **all-rigid placeholder** as MVP; layer the bones/joints physics in when the blade system matures. Everything above stands; tensegrity only swaps "perfectly rigid" for "rigidity from triangulation."

**Rigidity scales damage delivery (the balloon principle).** Rigidity isn't only the *hit pattern* — it **scales how much of a face's potential damage actually lands.** A face is potential mass; you cash the full face-damage only if the structure is rigid enough to deliver it. A floppy cycle shears mid-swing and deflates — *an inflated balloon vs. a deflated one.*

- A **braced** cycle (a wall of triangles) delivers **full** face damage → peak. A big braced 10-cycle is peak melee.
- The **same** 10-cycle left as a floppy hoop deflates → reduced damage.
- **Whips are the dual, not a contradiction:** a deliberately floppy chain converts flop into **tip velocity**, powering its edge/spike crack. Flop is the *point* of a whip.
- The genuinely bad case — the **deflated balloon** — is floppy *and* not a real whip: no rigid face to slam, no tip to snap. Worst of both.
- Therefore **bracing (chords/diagonals → triangles) is the melee build verb.** Exact damage-vs-rigidity curve is Balance-phase; the principle is locked.

**Area-fullness is the second delivery factor (delivery = f(rigidity) × g(area-fullness)).** A balloon must be *fat* as well as *firm* — a geometrically **squished** cycle (near-collinear, ~zero enclosed area) is topologically a face but physically nothing, so it should under-deliver even on the node it grazes.

- **Base face magnitude stays topological** — `Σ(edges) + Σ(spikes) + B`, exactly as above. Area never changes the *base*; it only modulates **how much lands** (delivery), the same lever rigidity already pulls. This keeps magnitude legible and the trigger planarity-free (cycle presence is always defined).
- **Area is already rewarded once, through coverage:** a fat pan sweeps over *more enemy nodes* (breadth); a sliver grazes a line. The delivery factor adds the *per-target* half so a degenerate cycle can't cash a full pan on its one victim.
- **Compute via the shoelace (signed) area** of the cycle's 1:1 positions. A **self-crossing / twisted** face nets ≈0 signed area → low delivery, which reads correctly as "a folded pan delivers little" — so bad embeddings degrade gracefully and never hit undefined behavior.
- Exact `g(area)` curve is Balance-phase; the principle (fat **and** firm to inflate) is locked.

**The board-spanning blade — self-limiting, allowed.** A huge blade (e.g. a 16-node line at ~140 STR) is welcome because the system balances it without patches:

- A **sparse** board-spanning line is the most fragile topology in the game (every interior node a cut-vertex) **and** under tensegrity it flops into a board-spanning **whip**, not a rigid sweep.
- A **rigid** board-spanning swipe therefore requires a **dense, triangulated mesh** — paid for in enormous SP/scale, a huge target.
- Damage is **breadth, not depth** (thin contacts per enemy, board-wide chip); a swept line barely moves at the pivot and screams at the tip (only the outer arc threatens), and only the part you can **see** (a PER/vision flex).

Grid/mesh-owners earn giant cleavers; filament-owners get giant flails. A Godot **grid sandbox** ("draw a shape, swing it") is the right tool to playtest blade feel — a dev task.

> **Resolved (GitHub #10): grip = clamp.** The small-blade / leaf-pivot floppiness question is settled by the grip paragraph above — the handle is a **clamp** (you grip it), so the first joint is always stiff; all other joints are free pins with rigidity **emergent from triangulation**, with **no stiffness stat and no floppiness toggle** (the candidate low/med/hi toggle is dropped). A single edge off a leaf pivot swings for real because the grip is welded; leaf pivots specialize into haft/mace weapons rather than being weak.

### The swing — sector aim + profile *(direction; tuning awaits the playground)*

**Aim = a circular sector** anchored at the pivot: an aim direction + an angular width `θ`, radius = blade reach. `θ` may be driven by attack type / stat. **The swing animates the handle's root edge from one sector edge to the other**; the phantom blade follows via the tensegrity kinematics, and the **deterministic ghost-trail preview shows the true swept coverage** (which, for a whip, deviates from the clean sector — sector = intent, simulated sweep = truth).

**Swing and thrust are two motion primitives, not one `θ`.** *(Corrects an earlier claim that `θ→0` is a thrust — it isn't: shrinking the arc just spawns the blade forward and jiggles it sideways, no penetration.)* A strike is a **scripted trajectory of the handle through planar DOF** (rotate `θ`, translate x/y) over normalized time:

- **Swing** = drive the handle **angle** (sector `θ`), pivot ~fixed → the sweep/area motion.
- **Thrust / jab** = drive the handle **position**, translating the whole phantom **forward along the aim ray** (the pivot lunges; nothing real moves) → penetration along the blade axis.
- General case = a blend (lunge-slash). "Strike type" is therefore a small, principled set: **`(which DOF, how far) + profile`** — and the **profile/easing applies to whichever DOF the strike drives** (angle for a swing, displacement for a thrust). Whether `θ` (and thrust reach) is fixed-per-weapon or a stat-bounded player choice is an open knob.

**Mass & angular inertia drive *feel*, never base damage.** A massive node-hammer must *feel* heavy — that's the whole point; its damage is already scaled by other means (topology + STR-bite + delivery). The sim already has node masses and computes `I = Σ mᵢrᵢ²` about the pivot, so use it for **motion** only:

- **Windup, accel, follow-through** = the heavy weapon loads slowly and lumbers — feel, not numbers.
- **Achievable arc per swing ≈ torque / inertia:** STR supplies torque, blade mass/inertia resists it, so a giant cleaver either sweeps a **narrow arc** (less coverage) or demands more STR. STR thus pulls **triple duty** (size, per-contact bite, swing-power-vs-mass), giving "board-spanning blade, self-limiting" a *physical* reason instead of a hand-wave.
- **Tip velocity** (mass far from pivot → high tip speed) feeds the whip crack/resonance.
- **Base damage stays topological** — momentum never enters the magnitude, preserving legibility.

**Damage is time-modulated by a per-element speed envelope (rest → rest) — this is the anti-cheese spine.** Each contact's damage scales by **how fast the contacting element is actually moving as it crosses the target**, read from the deterministic sim and normalized to `[0,1]` (relative to that element's own stroke-peak speed — a **timing weight**, never a momentum multiplier on the topological base magnitude).

- **Weight off the *element's* velocity, not the *handle's*.** A whip has a **propagation delay**: the tip cracks (peaks) *after* the handle has already slowed — the crack lands when the handle is ~still. Pegging the envelope to the handle's easing-curve derivative would therefore **nerf the crack to ~0 at exactly its payoff moment** — the trap to avoid. Reading each element's own sim velocity makes the sweet spot **ride the real crack automatically**, wherever the delay puts it. *(For a **rigid** blade an element's speed is just `ω·r` — handle angular speed × lever arm — fully determined by the easing curve, so it stays legible/predictable; the whip is where the delay bites.)*
- A swing goes **rest → rest**, so every element's speed is **0 at both ends** — the envelope **starts and ends at 0 for free**, and the **sweet spot rides each element's own fast moment** (whip tip → the late crack; rigid sweep → a forgiving mid plateau). Generalizes to thrust (a lunge is also rest→rest, peak mid).
- **This kills the spawn-on-target cheese continuously.** Spawning a blade head on `E` (or 0.1px against it, "resting against not onto") forces the crossing into the **near-spawn, near-zero-speed** window → ~0 damage. The brittle binary "exclude spawn-overlap" rule is **superseded**: the envelope handles the 0.1px escalation that an overlap-check cannot. *Laying* the blade on an enemy is worth nothing; the **sweep** is worth everything.
- Worked cheese (triangle-on-a-stick, blade `H–T`, enemy `E` with `|HE| ≈ |HT*|`): aiming so `T` starts on `E` means `T` only grazes `E` during the dead early window before sweeping off → near-zero. To cash damage you must arrange `T` to **cross `E` at the sweet spot** — which is exactly the positioning skill we reward, not cheese.
- Stays legible: base magnitude is still topological (Σ contacts × STR-bite × delivery); the envelope is a **normalized timing weight** that only gates *that the hit lands in the live part of the stroke*, never a momentum multiplier. The ghost-trail can color the high-damage window.

**Swing profile — the velocity pattern is the way forward, but as a *choice*, never analog input.** How the handle accelerates from A→B governs whether a whip snaps, resonates, or flops worse than it had to. This genre puts all skill in **build/decision, none in execution dexterity** ("not a Wii game"), so:

- **Baseline:** the engine auto-drives a **canonical, deterministic, learnable** profile — predictable over theoretically-optimal (a hidden optimizer would feel opaque). Aim is the only live input.
- **Depth:** the profile is a **discrete, pre-committed technique** (e.g. `smooth sweep`, `crack` = late-acceleration whip-snap, `follow-through`), optionally stat/class-gated — chosen before the swing like choosing an attack, not flicked in real time.
- **Depth lands where physics asks for it:** technique transforms a **whip** (snap/resonance) but does ~nothing to a **rigid pan** (it just sweeps). So profile-choice is automatically a whip-build's decision layer and a non-issue for cleavers.

**Representation — a profile is an easing function.** Concretely a normalized angular curve `θ̂(t̂): [0,1]→[0,1]` (its derivative = angular velocity, so the curve shape *is* the snap/resonance behavior). Map cleanly to Godot:

- `smooth sweep` ≈ `TRANS_SINE`/ease-in-out; `crack` ≈ `TRANS_EXPO`/`TRANS_QUINT` ease-in; windup/follow-through/resonance ≈ `TRANS_BACK`/`TRANS_ELASTIC` (these overshoot the endpoints → literal back-swing and oscillating tail).
- Store as a **`Curve` resource** (or a `Tween` `TransitionType`+`EaseType` pair for simple presets); `@export var profile: Curve` already gives the editor curve widget. Because it's just a resource with an editor widget, **the same widget can ship at runtime** as a "technique forge"; presets are named `Curve`s.

**Open (awaits the grid/blade playground — the dev sandbox above):**
- The topology space is huge; we likely won't (and needn't) author one profile per shape. Target: **one robust default that is *sane* on every blade**, plus a handful of specialist presets, possibly with the engine **auto-scaling** the default from blade properties (rigidity / length / DOF count). Which of the three the playground confirms is TBD.
- **Reliability floor — "crafting a working blade must not be more magic than actual magic."** The contract: the default profile yields a **sane, predictable** swing for *any* blade (rigid sweeps clean; floppy at least doesn't detonate). **Non-swingable blades are allowed** (a board-spanning floppy mess is fair "you built a bad weapon"), but failure must be **graceful and visible in the preview**, never chaotic. The ghost-trail answering "will this swing?" *before* committing is the guarantee.

**Early playground findings** (from the `tools/blade_playground` sandbox; informal, pre-tuning):
- **Triangle-on-a-stick swings as a flail, not a cleaver** — the head hinges at the first internal joint (the stick→triangle node), so it underperforms as a *swing*. Tunable (joint feel / Clamp addon), but the cheaper, better default melee shape turned out to be **the bare triangle itself with one long edge**: a rigid face where the long edge does the cutting, no wasted hinge. The minimal good blade is even cheaper than thought.
- **`follow` profile at max sector lobs the head** (projectile-like) rather than reading as whippy. Real whip feel wants a **longer handle or a reinforced/clamped base** — flop needs length to develop.
- **Initial orientation is a real problem.** The blade is your *real* topology, embedded wherever the graph sits; a frontline pivot (the node nearest the enemy, which you'd naturally swing from) typically has its blade extending **behind** you, and it can bend left / right / forward / anywhere. So a swing's rest orientation is effectively arbitrary relative to the target. The playground's aim-rotation + **aim-phase** (face the target at a chosen point in the stroke — e.g. the end, for a whip snap) handle this analytically; in the final game the resolution is the **preview ghost**: telegraph the true swept path before committing so the player orients the sweep onto the target regardless of where the blade starts. (See Open Questions.)

### Edge-cutting jab (Bleeding Edge)

Some melee shapes target **edges, not nodes** — they sever a **bridge** (cut-edge). The island rule fires immediately. A tempo weapon: no HP damage, but forces a connectivity crisis.

**Invariant: no mechanic may leave a region permanently unreachable.** Any edge-deletion mechanic must be paired with edge-reintroduction. The **Relay** addon was proposed as one form of reintroduction but is **TBD**. See `skill_node_addons.md`.

**Edgelord signature:** Bleeding Edge is the natural signature weapon of the **Edgelord** core class — it can wield bridge-severing without committing the unreachable-region heresy because it can re-add edges after cutting. All other classes remain subject to the softlock invariant.

### Winch addon

Exerts pull force on adjacent nodes, reducing effective euclidean distance. Math-only: does not create or delete edges.

---

## Degree → Offense (degree-defense removed)

> **Supersedes the old degree-defense model.** Degree previously drove *both* casting tier and HP, so high-degree hubs were strictly better — offense and defense stacking the same direction. We want a trade, not a stack. **Degree-defense is cut.** Durability now lives entirely in CON (White). Node HP no longer scales with degree (see Defense, Node Health & Thorns).

The clean three-way split that replaces it:

- **Degree = offense** (cast tier; the magic count lever).
- **Connectivity = topological survival** (rings resist islanding; cut-vertices are weak points). Untouched.
- **CON = durability** (hits a node eats).

A hub becomes a **glass cannon** — powerful caster, normal HP, priority target. "Silence, then grind" survives, simplified (the hub was never extra-tanky).

### The degree gradient (offense only)

| Degree | Role | Offense |
|---|---|---|
| 1 (leaf) | Ranged firing port | Fires volleys; Cantrip casting |
| 2 (connector) | Filament / potential cut vertex | Minor spells |
| 3–4 (hub) | Magic casting station | Major / Heavy spells |
| 5+ (major hub) | Elite casting | Ultimate spells |

### Pruning counterplay — "silence, then grind"

Killing one neighbor of a degree-4 hub drops its degree (−1 casting tier if it crosses a threshold). The counterplay: *prune neighbors to silence spells, then grind the now-exposed node.* Pruning disarms the hub; CON/HP is what you grind through afterward. Clean two-step.

---

## Self-Loops

A **self-loop** is an edge from a node to itself. A rare presence in the field; occasionally produced by specific events or conditions (origin: open — see below).

**Confirmed properties:**

**+2 degree (casting tier only).** Convention: a self-loop adds +2 to the node's degree (both endpoints are the same vertex). With degree-defense cut, this matters *only* for degree-gated casting: a self-looped node with a single external neighbor has degree 3 (Major spells) rather than 1 (Cantrip). A completely isolated self-looped node has degree 2 (Minor spells) with no neighbors at all. **Degree no longer affects HP** — durability is CON.

**Never a leaf.** A self-looped node has minimum degree 2, so it permanently exits the ranged-firing pool (leaf = degree 1 only). A self-loop on a formerly-firing leaf converts it from a ranged gun into a magic station — a real build tradeoff.

**Unprunable casting-tier floor.** The +2 cannot be pruned by killing a neighbor (there is no neighbor to kill for the loop's contribution). A self-loop provides a *casting-tier* floor that enemy pruning cannot reach. It grants **no** durability floor — so the self-loop only sharpens the node's glass-cannon identity.

**No connectivity contribution.** A self-loop creates no path to any other node. It cannot help an island survive disconnection, and cannot be cut to disconnect anything. Its effects are entirely expressed through the node's degree.

### The glass cannon — triple magic damage

A propagating spell that arrives at a self-looped node follows **all** edges out — including the self-loop. A self-loop contributes +2 degree, meaning it presents **two half-edges** both returning to the same node. The spell follows both, landing back at the node twice:

```
1. Spell arrives at node          → hit 1 (initial)
2. Propagation follows loop ×1    → arrives at same node → hit 2
3. Propagation follows loop ×2    → arrives at same node → hit 3
```

**Baseline: three hits from one spell's arrival.** This is pure math — no special casing required. The self-loop is two edges; the spell follows them both.

**What happens after hits 2 and 3 is entirely spell-dependent** — no global constraint:
- A hop-limited spell decrements depth at each return; eventually bottoms out.
- A spell with visited-node protection marks the node and stops further returns.
- An amplifying spell could escalate further — the self-looped node is a resonance chamber.
- A diminishing spell tapers off gracefully.

Every spell must define its own recursion/propagation rule. The self-loop's behavior emerges from whatever rule the spell applies.

**Color-specific vulnerability.** This triple-hit only triggers on *propagating* spells (Blue magic). Ranged volleys and melee strikes hit the node once and move on — the self-loop is transparent to them. The glass cannon weakness is **Blue vs. Blue** specifically. A Red entity can walk up and punch the self-looped wizard node without triggering any resonance.

**Summary:** a self-looped node hits harder (better, unprunable casting tier) and takes harder (triple damage from propagating spells, normal HP). Both from the same math. The ideal Blue glass cannon — and a priority target for any Blue attacker who knows what they're looking at.

### Breakout and self-loops

Self-loops are internal topology of the level. At Breakout, the entire field collapses — see Breakout section. All internal edge structure (including self-loops) dissolves in compression. Self-loops do not carry forward as live edges. They may contribute to the carry-forward stat aggregate, but not as edges.

**[OPEN] How self-loops arise.** Candidates: rare field node property (found, not created); Edgelord power (it adds edges — why not an edge-to-self?); Tech Seed fruit (rare modifier-pool result); Blue-specialist unlock. Whether the player manufactures, finds, or is occasionally cursed with them is undecided. High-priority design space; do not waste on a small effect.

**[RESOLVED] Self-loop degree and defense.** Moot — degree-defense is cut. The +2 degree affects casting tier only; it grants no HP. Durability is CON.

---

## Defense, Node Health & Thorns

### Node HP

Each node has its own HP pool, base **10** (see Scale Anchor), scaled by **CON** (White) — *not* degree (degree-defense is cut). When HP hits 0, node is severed → island check fires immediately.

### Entity-level defensive stats

- `armor`: flat reduction against all attack types.
- `resist_r / resist_g / resist_b`: per-color reduction. Triangle lives here.
- `damage_floor`: minimum damage taken per hit after reductions. Default 1. Bulwark starts at 3; can go negative (heals).
- `core_health`: HP of the core node. Core death = run ends, no Breakout.

### Thorns

A melee hit on a node with `thorns > 0` deals `thorns` flat damage back to the attacking node, not reduced by armor. The Halo class aura grants it dynamically: shell nodes get `2 × thorns_base`, near-shell (±1 hop) get `1 × thorns_base`. Base `thorns` is `0` unless granted by addon or modifier.

### SP Reservation (Wounds)

Force-deallocation (a node destroyed in combat) creates a **Reservation**:
```
effective_max_sp = skill_points_max − sp_reservation
```
Healing removes reservations 1:1. Node transfers do not create reservations (BLITZ; Uprooting where available — Uprooting is an Edgelord class specialty, not a universal power).

**Tutorial enemy example:**
```
Before:    SP = 0 / 5   (5 nodes, 0 spare)
Attack:    cut-vertex snipe + 2 island deaths = 3 force-deallocations
After:     SP = 0 / 2   [3 reserved] — stuck, can't reallocate
```

SP Reservation is also a **mid-fight suppression tool**: sustained damage shrinks the enemy's effective options in real time.

---

## Uprooting *(class specialty — removed from universal kit)*

Uprooting severs **all** edges of a target node. No longer a universal core power — too footgun-y for general use (risks self-islanding or orphaning the core).

**Status:** demoted to Edgelord class specialty. Tech Seed is the build-tool portability path; Uprooting is a tactical weapon (destroy a cut vertex in an enemy's path).

---

## Island Rule

**Default: immediate death.**

When a sub-graph has no path back to the entity's core (or Lifelink proxy core), it dissolves immediately. All nodes become unallocated; SP Reservation fires for each.

See `skill_node_addons.md` for **Lifeline** (1-turn grace) and **Lifelink** (indefinite proxy core).

**Lifeline + Lifelink combo:** concerning but undesigned. Flag, don't balance against until seen in play.

---

## Killing Blow Resolution

When the killing blow drops an entity's core HP to 0:

### 1. XP Reward (universal)
XP proportional to the dead entity's level. Converts to SP through the normal leveling pipeline.

### 2. DAP Bonus (universal)
The attacker gains **+N `deallocation_points` this turn** (N proposed: 2; calibrate in playtest). Universal: every class, every kill type.

### 3. BLITZ (Predator class only)
If the Predator had at least one node adjacent to any dying entity node at the moment of the kill: steal one adjacent enemy-owned node directly, no SP cost.
- Player chooses which adjacent enemy-owned node to steal.
- If BLITZ claims the Relic Node: loot resolution triggers immediately with +1 STEAL pick.

### 4. Relic Node
The dead core becomes a **Relic Node** — fused with core modifiers, sits indefinitely (provisional; no expiry until playtesting argues for one). All remaining enemy-owned nodes become neutral immediately.

---

## Node Ownership Staining

Each node tracks `last_owner: EntityRef`. Set on allocation; cleared when a different entity allocates it.

**Loot pool rules (A/B/C/D):**
- **(A) Unallocated:** not in draft.
- **(B) Owned by enemy at death:** in full pool. STEAL or PROLIFERATE.
- **(C) Now owned by player (captured mid-fight):** PROLIFERATE only.
- **(D) Now owned by a third entity:** not in draft.

---

## Loot Resolution

Triggered when the player **allocates the Relic Node**.

Each modifier can be:
- **STEAL** — applied to the player's core. Portable, permanent, full value. (Loot/extraction is **field → core**: consolidate, make permanent/portable.)
- **PROLIFERATE** — see below. (**core → field ×N**: multiply, expose.)
- **SKIP** — decline.

**N total picks** (proposed 3; tune in playtest). Predator BLITZ-the-core bonus: +1 STEAL pick.

### Proliferation — a core→field trade

> **Supersedes the old RNG "copy a modifier to nearby owned nodes."** Proliferation is now a deliberate trade, the **inverse of loot/extraction** (one pulls in, one pushes out).

- **The act:** pick a modifier **held by your core**, remove it (**−1 permanent**), and **+N copies appear on the battlefield** across a cluster you then fight to hold.
- **Cost that bites:** you trade *safe-permanent-portable-1×* for *vulnerable-fixed-non-portable-N×*. If your cluster is sniped you've strictly downgraded (core −1 *and* copies gone). That downside brakes the otherwise win-more nature.
- **Loop-break (essential): intrinsic, owner-independent, non-extractable taint** (PoE Mirror precedent). Proliferated copies can never be extracted or re-proliferated *by anyone* — even an enemy who captures one can only use it in place. This kills extract→proliferate→extract dead. Field→core paths stay few and gated; if a standalone "extraction" exists it is the main loop vector and the taint is load-bearing.
- **Throttle:** the input (proliferation-worthy core mods) is scarce because loot is scarce — that gates how often you can do this, so the act can be very strong.
- **Rarity-scaled efficiency:** proliferation works **less effectively on rarer modifiers** — duplicating something like the ultra-rare `+1 bonus_hop_count` succeeds but yields fewer copies / costs more. The rarest, most build-defining mods stay valid targets without letting you trivially mint a board-nuke.
- **Discipline preserved (Slay the Spire "stay lean"):** the restraint moved from *which cards to draft* to *how much to commit to the field.* Greedy players over-proliferate into territory they can't hold and eat the punish.

The `proliferation_power` stat now reads as the **N** (copy count, rarity-scaled), not an RNG radius. See `entity_stat_board_prototype.md`.

---

## Boss Progression

| Stage | Guardian form | Topological property |
|---|---|---|
| Early levels | Non-ring, thin, irregular | Vulnerable to cut-vertex snipe |
| Mid levels | Single-thick ring (Ophanim) | 2-edge-connected — demands 2 cuts |
| Late / pre-Apex | Larger single-thick rings | Same property, more nodes to grind |
| Apex (final) | Multi-row thick ring (Ophanim) | Cannot be topologically dismantled — attrit arc by arc |

The Apex Ophanim is fought at the end of every run. Subsequent runs face a tougher Apex. See `metagame.md`.

---

## Breakout

*(Combat-relevant summary. Full narrative version in `lore.md`.)*

**Condition (both required):**
1. All Tethers destroyed.
2. Level guardian (boss) defeated.

**Grace period:** once both conditions are met, `X` turns begin (TBD). During grace: no XP; player may reallocate freely; stat carry-forward computed from nodes owned at **end of grace**.

**The collapse:** when grace ends, the **entire field** — your constellation, all enemy constellations, the wall, every node and edge — collapses inward and compresses into a single node. This is graph-literal: the level was always a vertex in the graph above; destroying its Tethers severed all of that vertex's edges. An isolated vertex collapses, and that collapsed point is your new starting node at the next, larger level. All internal topology (including any self-loops) dissolves in compression. What carries forward is stat and modifier, not edge structure.

Enemy entities that were alive when Breakout fires also compress — they become pre-allocated neutral hostile nodes on the new field, seeding a stronger enemy entity one level up.

---

## Starter Node Re-edging

After Breakout the new starting node arrives with **zero edges** (every Tether was severed). At minimum 1 edge is always automatically restored (softlock invariant). Re-edging is partly random — a designed source of starting-position variance. See `lore.md` for narrative framing (the Lord of Edge's immune response).

**[OPEN]** Whether the player ever gains influence over re-edging is undecided.

---

## Core Classes (summary reference)

Full class entries in `core_classes.md`. Combat-relevant highlights:

- **Predator:** BLITZ on killing blow. XP ×0.5.
- **Bulwark:** `damage_floor = 3` starting; floor-reduction perk path to 0 and below.
- **Halo:** shell aura grants `thorns` to ring nodes. Shell adjustable ±1 per turn. Now also has a **melee option** — swing the thorny shell as a phantom blade (thorns = swung spikes; see Melee).
- **Frontier / Pioneer:** hardens its leaves (defensive buff to degree-1 nodes) → forward-push playstyle. Identity needs differentiating now that all leaves are generic firing ports.
- **Edgelord:** signature Bleeding Edge user (cut-and-restore edges); Uprooting class specialty. Likely the entity that can also *create* self-loops.
- **Ninja:** high DAP, intense short-range aura, low SP cap.
- **Hive:** Lifelink proxy cores sustain isolated pods.
- **Serpent:** dual-metric aura (hop-buff × euclid-penalty).

---

## Prototype Stat Defaults

> **Note:** `entity_stat_board_prototype.md` is a **stat-existence vocabulary** — it tracks *which* stats exist, not their calibrated values. Numeric values are a Balance-phase activity. The illustrative numbers below follow the base-10 anchor; they are not commitments. The obligation from this doc is to ensure new stats introduced here (`constitution`, `wisdom`, `perception`, `coolness`, `bonus_hop_count`) are registered in the vocabulary — and that obsolete ones (`pressure_recovery`, from the dropped tap-and-recover model) are retired.

Allround combat prototype (illustrative, base-10 anchor):

```
STR = 10, DEX = 10, INT = 10
CON = 10, WIS = 10, PER = 10        ← utility attributes (White/Gold/Purple)
armor = 0, resist_r/g/b = 0, damage_floor = 1, thorns = 0
node_health = 10 (base; scaled by CON — NOT by degree)
core_health = ~30   (placeholder — recalibrate vs base-10 node HP)
attack_range = ?    (recalibrate vs leaf-only volley model)
sense_range = 3 (hops), vision_range = ~4 (euclidean)   ← scaled by PER
bonus_hop_count = 0                  ← ultra-rare; INT scales potency, this scales reach
skill_points = 0 / 5   (5 nodes allocated, all SP in use)
sp_reservation = 0
deallocation_points = 1 / turn
```

---

## Design Tensions (Unresolved)

1. **Armor per-hit vs per-attack — *resolved for the blade.*** A phantom-blade swing sums all contacts (edges + spikes + faces) per target and applies armor/resist **once per target node** (multiple distinct targets each subtract armor separately). Combined ranged volleys likewise apply defense once. Consistent with the scaling spine.
2. **Crit: global vs per-type.** Leaning global to start.
3. **Triangle: emergent resist vs hardcoded baseline.** Decide alongside armor.
4. **Dual-color attack timing.** Free per attack, or source-node-inherited?
5. **Lifeline + Lifelink combo.** Don't design around until seen in play.
6. **Relic Node expiry.** Indefinite provisional.
7. **Loot picks N.** Fixed 3, or entity-level-derived?
8. **BLITZ bonus form.** +1 STEAL pick is the proposal.
9. **proliferation_power distribution.** Fixed count or min-max range?
10. **Magic propagation rules.** Owned nodes only? Any traversable edge? Relay through allies? Node-type-gated? AoE vs terminal?
11. **vision_range calibration.** Verify against editor node spacing.
12. **DAP from killing blow N.** Proposed 2.
13. **Thorns ceiling.** At what `thorns_base` does Halo shell deter all melee?
14. **Thorns=spikes — *resolved.*** One stat (*sharpness*); stationary = counter-damage, swung = offensive contact. (Was: thorns distribution across tapped nodes — moot under the phantom blade.)

---

## Resolved

- ~~Death condition~~ → Core node loss = death. No Breakout.
- ~~Island grace timer~~ → No default grace. Lifeline addon grants it.
- ~~Ghost pool~~ → Dropped. Stain tracking handles mid-fight captures.
- ~~Bargain sale~~ → Dropped.
- ~~Ranged firing origin~~ → **Leaf nodes only.** One volley per turn; armor/resist once per volley (per-attack).
- ~~Magic targeting~~ → Spell-native, graph-based, **degree-gated**. `attack_range` does not apply.
- ~~Triangle direction~~ → R › B › G › R.
- ~~Scale~~ → **Base-10 anchor.** Linear scaling baseline.
- ~~"Bridge node" terminology~~ → **Cut vertex** (node) vs. **bridge** (cut-edge). Locked.
- ~~Melee charge model (tap-and-recover)~~ → **Phantom blade.** Swing a 1:1 induced-connected copy of owned nodes; size `STR//10+1`; one swing/turn; damage = contacts (edges + spikes + faces) × `(base+STR//10)`, defense once per target; rigidity from triangulation (tensegrity). Buffer nodes repurposed.
- ~~Melee grip / floppy-first-joint (leaf melee)~~ → **Grip = clamp** (#10). Handle welds its edge into the swing frame, so the first joint is always stiff (leaf or hub); other joints free pins, rigidity emergent from triangulation — no stiffness stat, no floppiness toggle; only a weak global damping for legibility. Leaf pivot = haft (mace/axe/flail); degree-≥2 pivot = cleaver/pan. Switch is pivot degree ≥2, not "handle on a cycle."
- ~~Degree's role (offense + defense)~~ → **Offense only.** Degree gates cast tier; degree-defense is cut. Durability = CON. Connectivity still governs topological survival. Hubs are glass cannons; "silence, then grind" survives, simplified.
- ~~Attribute roster~~ → **Six:** R/STR, G/DEX, B/INT (attack) + White/CON, Gold/WIS, Purple/PER (utility). Plus non-mechanical `coolness`. White→CON and economy→Gold supersede the old "W = XP."
- ~~Attribute → damage scaling~~ → **The //10 spine:** `base (once) + attribute//10 × instances`, defense once per target. Floors per-attribute (breakpoints, surfaced in UI). Gear-ratio decouples modifier economy from damage economy.
- ~~Proliferation~~ → **core→field ×N trade** (remove a core mod, spread N tainted copies). Intrinsic non-extractable taint breaks the extract→proliferate loop. Rarity-scaled efficiency.
- ~~Turn structure~~ → **Three phases:** Deployment (permanent) → Battle (act + temp buffer reach) → Consolidation (promote/drop temps). Phase = the temp/permanent flag; one SP pool.
- ~~Self-loop propagation model~~ → Triple-hit baseline (initial + 2 loop returns). Spell-dependent further behavior. No global rule.
- ~~Claim bonus → BLITZ~~ → BLITZ Predator-only. Universal: XP + DAP.
- ~~Killing blow → direct +1 SP~~ → XP reward (pipeline) + universal DAP bonus.
- ~~Node staining~~ → Confirmed. `last_owner` field. A/B/C/D loot pool logic.
- ~~damage_floor hardcoded~~ → Now a stat. Default 1. Bulwark 3; can go negative.
- ~~Relay as confirmed~~ → TBD. See `skill_node_addons.md`.
- ~~Uprooting as universal~~ → Removed. Edgelord specialty.
- ~~Breakout condition~~ → Tethers + boss, then grace window. Entire field collapses → 1 node.
- ~~Breakout scope~~ → **Entire field** (all constellations + wall) collapses to 1 node. Internal topology (incl. self-loops) dissolves.

---

## Open Questions

1. **Magic propagation rules** — propagation path, relay, node-type gating, AoE vs. terminal.
2. **Edge integrity & softlock safeguard** — how are bridges re-introduced after Bleeding Edge? Relay TBD.
3. **Melee shape data model** — designer-authorable representation.
4. **Movement vs. combat DAP economy** — shared pool?
5. **Lifeline radius N** — calibrate to playtest.
6. **Dual-color attack timing** — free per attack or source-node-inherited?
7. **Relic Node expiry** — keep indefinite?
8. **Loot picks N** — fixed at 3?
9. **Stat sync** — every stat above (the six attributes `constitution`/`wisdom`/`perception` + `coolness` + `bonus_hop_count`; retire obsolete `pressure_recovery`) must land in the canonical Stat Vocabulary table on the `StatDefinition` pipeline.
10. **proliferation_power** — fixed count vs. min-max range?
11. **Linear vs. steeper attribute scaling** — revisit if linear flattens build diversity.
12. **Self-loop origin** — how do self-loops arise? Class power, field node, Tech Seed, unlock?
13. ~~**Self-loop degree and defense**~~ — *resolved:* degree-defense cut, so +2 loop degree affects casting tier only, never HP.
14. **Spell propagation at self-loops** — each spell must define its recursion/hop-limit rule for handling the two loop returns. No global constraint.
15. **Grace period duration** — calibrate `X` turns.
16. **Re-edging influence** — does the player ever gain say over which edges are restored?
17. **Second volley upgrade** — what grants a second ranged volley per turn?
18. ~~**Degree-defense HP calibration**~~ — *resolved:* degree-defense removed. Node HP scales with CON; calibrate the CON→HP curve vs base-10 in Balance phase.
19. ~~**Defense model (degree-based vs alternatives)**~~ — *resolved:* durability lives in **CON**, decoupled from degree entirely. Degree is offense-only.
23. **Magic canonical situations** — magic is balanced LAST; needs a set of canonical attack topologies to pin per-instance `INT//10` scaling against. Friendly-fire lean: ON for propagating, OFF for targeted, rare opt-out — confirm during magic balancing.
24. **`bonus_hop_count` rarity & proliferation curve** — ~1–2 on the whole map; rarity-scaled proliferation efficiency needs a curve.
25. **Proliferation taint** — confirm the intrinsic, owner-independent, non-extractable taint as the loop-break (recommended yes).
26. ~~**Small-blade melee feel**~~ — *resolved (#10):* grip = clamp; rigidity emergent from triangulation, no stiffness stat, no floppiness toggle; leaf pivot = haft. See Tensegrity.
27. **Color nodes at all?** — content (attribute/role) exists regardless; whether to render node color is a presentation question. Procgen should cluster like-colors into biome-like regions either way.
28. **DP vs DAP** — abbreviation for deallocation points (cosmetic).
20. **Action economy** — one attack per turn, an `action_points` stat (default 1), or one of each attack type per turn? Affects tempo heavily. (GDD §5.)
21. **Triangle weight** — is type-advantage a *primary* combat axis or a *situational tiebreaker*? GDD §5 leans situational (positioning, topology, and target defense matter more than color); this doc currently treats the triangle as load-bearing. Reconcile — likely "situational, backstopped by a small baseline" so color never feels absent but rarely decides a fight alone.
22. **Tempo target / the kill-speed anchor** — the "3–4 volleys per node" anchor is now a *tiered* target (1–2 super-effective / 3–4 regular / 5+ well-defended), leaning fast: nodes dying too quickly is preferable to too slowly (forces rerouting and adaptation; keeps the turn-based game from going static). Calibrate against worked examples — see `combat_worked_examples.md`.
29. **Ranged identity & cut-vertex surgery** — perception gating (must you *see* the articulation point?), volley concentrate-vs-spread, reach calibration to deep cut vertices, Lifeline/grace interaction with the island cascade, and whether ranged earns its keep against 2-connected (cut-vertex-free) builds. (GitHub #11 — see Ranged identity.)
30. **Swing model tuning** — the model is locked (two motion primitives swing/thrust; easing-curve profile per technique; mass/inertia → feel + achievable-arc, never base damage; rest→rest damage envelope as the anti-cheese spine). The **grid/blade playground (GitHub #12)** owns the numbers: robust default + specialist presets (or an auto-scaled default), the per-profile envelope shape, the `arc ≈ torque/inertia` curve, tip-velocity→whip-delivery coupling, the reliability floor across topologies, and whether `θ`/thrust-reach are fixed-per-weapon or stat-bounded player choices. (See *The swing — sector aim + profile*; Clamp addon in `skill_node_addons.md`.)
31. **Initial blade orientation & the preview ghost** — the blade is your real, arbitrarily-embedded topology; a frontline pivot usually has its blade *behind* it (bending left/right/forward/anywhere), so rest orientation is arbitrary relative to the enemy. Aim-rotation + **aim-phase** orient the sweep analytically; the in-game answer is a **preview ghost** that telegraphs the true swept path before commit. Settle how aim is expressed to the player (drag-to-aim, sector handle, aim-phase exposure) and how the ghost reads. (Playground #12; see *The swing*.)
