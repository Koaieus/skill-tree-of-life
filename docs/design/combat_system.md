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

**Combined strikes apply defense once (per-attack, not per-hit).** Both the ranged **volley** (many leaves on one target) and the melee **tap** (many charge nodes in one strike) sum their contributions into a single `outgoing`, and `armor`/`resist` subtract **once** from that total.

**`damage_floor`:** replaces the old hardcoded `max(1, ...)`. Global default `1` — behavior identical for most entities. The Bulwark class starts at `damage_floor = 3` with a class path to reduce it. Below `0`, the entity heals when hit (intentional extreme-build payoff). See `entity_stat_board_prototype.md`.

**Thorns:** flat counter-damage returned on a melee hit to the attacking node, not reduced by armor. The Halo class's aura grants thorns to shell and near-shell nodes from `thorns_base`. See `skill_node_addons.md` and `core_classes.md`.

---

## Attributes, Colors & the RGBW Triangle

| Color | Attribute | Attack mode | Targeting basis | Combat character |
|---|---|---|---|---|
| **R** (Red) | STR | Melee | Adjacency | High damage, short reach. Beats Blue. |
| **G** (Green) | DEX | Ranged | **Euclidean** | Precise, moderate damage, long reach. Beats Red. |
| **B** (Blue) | INT | Graph-magic / Spells | **Spell-native (graph)** | Propagates along edges, bypasses geometry. Beats Green. |
| **W** (White) | — | None | — | XP/SP income. No attack, no triangle slot. |

**Targeting modes:**
- **Ranged (G):** euclidean distance from a firing **leaf** to the target. `attack_range` limits this. Pure geometry.
- **Magic (B):** each spell defines its own graph-native targeting (hop count, fork behavior, propagation depth), scaled by INT, **gated by owned-subgraph degree** (owned allocated neighbors only; unallocated and enemy nodes do not contribute — see Degree-gated casting). `attack_range` does **not** apply to magic. Rare drain/leech spells may explicitly count all incident edges instead.
- **Melee (R):** adjacency. You hit what you're next to.

**Triangle (R › B › G › R):** lives primarily in emergent per-color `resist_*` stats. A small hardcoded `type_advantage` baseline may backstop early-game — decide alongside armor (both edit `taken`).

**Dual-color nodes:** A R/B node picks which color it attacks with per swing. Open: free choice per attack, or inherited from source node?

**White:** No attack, no triangle slot. Provides XP/turn. Economic objective entities fight over.

---

## Perception & Fog of War

Two-layer system. Both entity-level stats. Per-node position determines coverage zone.

| Stat | Basis | What you see | Default |
|---|---|---|---|
| `sense_range` | **Hops** from any owned node | Silhouette: node exists at position X, no details | 3 |
| `vision_range` | **Euclidean** from any owned node | Full detail: node type, HP, visible modifiers | ~4 |

Beyond `sense_range`: total fog. Inside sense but outside vision: silhouette only. Inside vision: full information. A silhouette-only node can still be targeted by ranged attacks if within `attack_range`. `vision_range` belongs on the entity stat board (not on individual nodes — legacy code misplaces it).

---

## Ranged Attacks

**Firing origin: leaf nodes only.**

A **leaf** is a node of degree 1 in the entity's *own allocated subgraph*. Only leaves may fire ranged attacks; non-leaf owned nodes cannot.

**Why this is graph-native:** tendrils and stubs become firing ports. Growing ranged capability means sprouting stubs off a filament (turning an I-shape into an E-shape adds 3 firing leaves). Compact cluster builds lose ranged presence. Ring builds (zero leaves by definition) cannot fire ranged at all — they trade ranged offense for topological resilience.

**Volley model:**
- Per turn the entity fires **1 volley** by default. A second volley is a stat/class upgrade, not baseline.
- A volley = the player selects one target node; every owned leaf within euclidean range of that target fires simultaneously.
- **Damage:** contributions from all firing leaves sum into one combined hit; armor and resist apply **once** to the combined total (per-attack).
- Range is the natural volley-size cap: you cannot get 40 leaves within one target's euclidean radius. No explicit leaf cap needed.

```
outgoing  = base_ranged + Σ(DEX contribution of each firing leaf)
taken     = max(damage_floor, outgoing − armor − resist_g)
```

**Two intended outcomes:**
- Converged leaves → dismember a weak node. A comb of leaves on a low-HP target can one-shot it.
- 1–2 overextended leaves into a stronghold → won't cut it; armor absorbs the trickle.

**Leaf cooldown:** none. Leaves are always ready. The 1-volley/turn cap is the full economy — no per-leaf cooldown on top.

**Crit:** global `crit_chance` (5%) and `crit_mult` (×2) to start.

**Frontier / Pioneer class note:** since all leaves are now generic firing ports, Frontier's identity must be differentiated. Direction: Frontier *hardens* its leaves (defensive buff to degree-1 nodes), enabling a forward-push leaf playstyle rather than sit-back kiting. To be finalized in `core_classes`.

---

## Magic (Graph-Magic) — Spells

**Magic is graph-math made into a weapon.** Each spell defines its own propagation mechanism — a graph-theory primitive, not a generic attack. INT scales potency; the spell's *shape* is inherent. `attack_range` does not apply.

```
outgoing = base_magic + INT    (or spell-specific formula)
taken    = max(damage_floor, outgoing − armor − resist_b)
```

Magic's identity: it reaches targets that are geometrically far but **topologically close**. Design leans hard into this distinction from ranged.

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

### Cadence: tap-and-recover

Melee charge nodes (Buffer-addon nodes, or nodes designated melee contributors by class) are **tapped** to strike.

1. The player selects any subset of charge nodes to tap this turn.
2. The tapped nodes contribute to one combined melee strike: total power scales with tap count and the tapped nodes' STR.
3. **Same turn:** the strike fires.
4. **Next turn:** tapped nodes are in *recovery* — unavailable to act or attack.
5. **Turn after:** available again.

**The partition decision (burst vs. sustain, every turn):** tap all 20 charge nodes → maximum burst (all 20 on cooldown next turn). Tap 10 → half-strength strike with 10 still ready next turn. Staggering maintains pressure every turn at half strength; massing spikes every-other-turn at full strength.

**Recovery vulnerability:** while recovering, a tapped node carries a **defensive nerf** (increased damage taken and/or reduced armor/resist), reflecting depleted SP-force — present but not fully braced.

**Recovery duration:** default 1 turn, exposed as a stat (`pressure_recovery`, default 1) so classes can tune rhythm.

### Attack shapes (preserved)

Tap count determines magnitude; shape determines spread. Starting vocabulary: **Cone** (default jab, widens with distance), **Circle** (point-blank omnidirectional), **Line** (straight lance), **Arc/chevron** (frontal sweep), **Double-arc** (hits near and far ring, misses middle). Damage profiles: Falloff / Constant / High-then-cut.

### Edge-cutting jab (Bleeding Edge)

Some melee shapes target **edges, not nodes** — they sever a **bridge** (cut-edge). The island rule fires immediately. A tempo weapon: no HP damage, but forces a connectivity crisis.

**Invariant: no mechanic may leave a region permanently unreachable.** Any edge-deletion mechanic must be paired with edge-reintroduction. The **Relay** addon was proposed as one form of reintroduction but is **TBD**. See `skill_node_addons.md`.

**Edgelord signature:** Bleeding Edge is the natural signature weapon of the **Edgelord** core class — it can wield bridge-severing without committing the unreachable-region heresy because it can re-add edges after cutting. All other classes remain subject to the softlock invariant.

### Winch addon

Exerts pull force on adjacent nodes, reducing effective euclidean distance. Math-only: does not create or delete edges.

---

## Degree → Defense

Degree drives **both** offense (spell tier) and **defense (resilience)**, scaling differently.

### Defense: continuous, HP-based

> Effective node HP = base HP + (degree − 1)

**Degree here = total incident edges, regardless of ownership** (all neighbors: owned, neutral, enemy). This is intentionally *different* from owned-subgraph degree used for magic offense — a hub connecting to many neutral or enemy nodes is physically well-braced even without drawing spell-power from those connections.

**Design tension (open):** using total-degree for defense and owned-degree for offense creates a mild conflict for high-degree hubs — they're simultaneously elite spellcasters (from their many owned connections) *and* the tankiest nodes (from total degree). Counterplay ("silence, then grind") is the designed answer, but the degree split between offense and defense may need revisiting if alternative defense models (owned-neighbor ratio, territorial depth, local clustering) prove more interesting in practice. See Open Questions #18.

Starting calibration: **+1 HP per degree beyond 1.**
- Degree 1 (leaf): base HP (10)
- Degree 2 (connector / filament): 11
- Degree 4 (hub): 13

The *shape* is locked (monotonic, mild, continuous). Calibrate the coefficient in playtesting.

### The full degree gradient

| Degree | Role | Offense | Defense |
|---|---|---|---|
| 1 (leaf) | Ranged firing port | Fires volleys | Minimum bracing — glass |
| 2 (connector) | Filament / potential cut vertex | Limited | Soft — the classic snipe target |
| 3–4 (hub) | Magic casting station | High-tier spells | Well-braced — needs grinding |
| 5+ (major hub) | Elite casting | Ultimate spells | Tankiest nodes on the field |

### Pruning counterplay — "silence, then grind"

Killing one neighbor of a degree-4 hub drops its degree (−1 HP, −1 casting tier if it crosses a threshold). The counterplay: *prune neighbors to silence spells, then grind the now-exposed node.* Pruning doesn't collapse the hub — it disarms it. Clean two-step.

### Recovery vulnerability stacks with degree-defense

A recovering (tapped) melee node carries two independent defensive states simultaneously: structural bracing from degree (unchanged) and SP-force depletion from recovery (the nerf). Two clean sources, coherent stacking.

---

## Self-Loops

A **self-loop** is an edge from a node to itself. A rare presence in the field; occasionally produced by specific events or conditions (origin: open — see below).

**Confirmed properties:**

**+2 degree.** Convention: a self-loop adds +2 to the node's degree (both endpoints are the same vertex). This matters for degree-gated casting and degree-defense: a self-looped node with a single external neighbor has degree 3 (Major spells; 12 HP) rather than 1 (Cantrip; 10 HP). A completely isolated self-looped node has degree 2 (Minor spells; 11 HP) with no neighbors at all.

**Never a leaf.** A self-looped node has minimum degree 2, so it permanently exits the ranged-firing pool (leaf = degree 1 only). A self-loop on a formerly-firing leaf converts it from a ranged gun into a magic station — a real build tradeoff.

**Structurally durable degree.** The +2 cannot be pruned by killing a neighbor (there is no neighbor to kill for the loop's contribution). A self-loop provides a degree *floor* that enemy pruning cannot reach.

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

**Summary:** a self-looped node hits harder (better casting tier, durable degree) and takes harder (triple damage from propagating spells). Both from the same math. The ideal Blue glass cannon — and a priority target for any Blue attacker who knows what they're looking at.

### Breakout and self-loops

Self-loops are internal topology of the level. At Breakout, the entire field collapses — see Breakout section. All internal edge structure (including self-loops) dissolves in compression. Self-loops do not carry forward as live edges. They may contribute to the carry-forward stat aggregate, but not as edges.

**[OPEN] How self-loops arise.** Candidates: rare field node property (found, not created); Edgelord power (it adds edges — why not an edge-to-self?); Tech Seed fruit (rare modifier-pool result); Blue-specialist unlock. Whether the player manufactures, finds, or is occasionally cursed with them is undecided. High-priority design space; do not waste on a small effect.

**[OPEN] Self-loop degree and defense.** Does the +2 degree from a self-loop also boost the node's HP bracing via degree-defense? Almost certainly yes (the formula is `base + degree − 1`, no carve-outs), but confirm explicitly when degree-defense is finalized.

---

## Defense, Node Health & Thorns

### Node HP

Each node has its own HP pool, base **10** (see Scale Anchor), modified by degree (see Degree → Defense). When HP hits 0, node is severed → island check fires immediately.

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
- **STEAL** — applied to the player's core. Portable, permanent, full value.
- **PROLIFERATE** — copied to `proliferation_power` nearby owned nodes (RNG within range). Fixed in space; lost if those nodes are cut.
- **SKIP** — decline.

**N total picks** (proposed 3; tune in playtest). Predator BLITZ-the-core bonus: +1 STEAL pick.

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
- **Halo:** shell aura grants `thorns` to ring nodes. Shell adjustable ±1 per turn.
- **Frontier / Pioneer:** hardens its leaves (defensive buff to degree-1 nodes) → forward-push playstyle. Identity needs differentiating now that all leaves are generic firing ports.
- **Edgelord:** signature Bleeding Edge user (cut-and-restore edges); Uprooting class specialty. Likely the entity that can also *create* self-loops.
- **Ninja:** high DAP, intense short-range aura, low SP cap.
- **Hive:** Lifelink proxy cores sustain isolated pods.
- **Serpent:** dual-metric aura (hop-buff × euclid-penalty).

---

## Prototype Stat Defaults

> **Note:** `entity_stat_board_prototype.md` is a **stat-existence vocabulary** — it tracks *which* stats exist, not their calibrated values. Numeric values are a Balance-phase activity. The illustrative numbers below follow the base-10 anchor; they are not commitments. The obligation from this doc is to ensure new stats introduced here (`pressure_recovery`, and any stats implied by degree/self-loop mechanics) are registered in the vocabulary — already covered by Q9.

Allround combat prototype (illustrative, base-10 anchor):

```
STR = 10, DEX = 10, INT = 10
armor = 0, resist_r/g/b = 0, damage_floor = 1, thorns = 0
node_health = 10 (base; effective HP = 10 + degree − 1)
core_health = ~30   (placeholder — recalibrate vs base-10 node HP)
attack_range = ?    (recalibrate vs leaf-only volley model)
sense_range = 3 (hops), vision_range = ~4 (euclidean)
skill_points = 0 / 5   (5 nodes allocated, all SP in use)
sp_reservation = 0
deallocation_points = 1 / turn
pressure_recovery = 1 (turn)
```

---

## Design Tensions (Unresolved)

1. **Armor per-hit vs per-attack — *partially resolved.*** Combined fire (ranged volley, melee tap) applies armor/resist once (per-attack). Open: per-shape melee against multiple distinct target nodes — does each subtract armor separately? (Yes by the pipeline loop, but shape balance depends on confirming.)
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
14. **Thorns vs combined strikes.** Distribution when many tapped nodes contribute. (Minor.)

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
- ~~Melee charge model~~ → **Tap-and-recover.** Vulnerability in recovery phase. Shapes preserved.
- ~~Degree's role~~ → Offense (spell tier) **and** defense (node HP). "Silence, then grind" is the universal hub counterplay.
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
9. **Stat sync** — every stat above (incl. `pressure_recovery`, plus any stats degree/self-loop mechanics imply) must land in the canonical Stat Vocabulary table on the `StatDefinition` pipeline.
10. **proliferation_power** — fixed count vs. min-max range?
11. **Linear vs. steeper attribute scaling** — revisit if linear flattens build diversity.
12. **Self-loop origin** — how do self-loops arise? Class power, field node, Tech Seed, unlock?
13. **Self-loop degree and defense** — does +2 loop degree also add HP bracing? (Almost certainly yes — confirm.)
14. **Spell propagation at self-loops** — each spell must define its recursion/hop-limit rule for handling the two loop returns. No global constraint.
15. **Grace period duration** — calibrate `X` turns.
16. **Re-edging influence** — does the player ever gain say over which edges are restored?
17. **Second volley upgrade** — what grants a second ranged volley per turn?
18. **Degree-defense HP calibration** — +1 HP/degree is a starting value; calibrate vs base-10.
19. **Defense model** — current formula uses total-degree. Alternatives worth evaluating: (A) owned-neighbor count (anticorrelates with magic offense naturally — high-degree hubs connecting to neutral/enemy nodes get low defense); (B) territorial depth (hops to nearest unowned node); (C) local clustering coefficient on owned subgraph (rewards looped/dense builds, needs visual feedback, requires field to have cycles). Decision should follow first playtests of hub-heavy vs filament builds.
