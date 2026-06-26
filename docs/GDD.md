# Game Design Document — Skill Tree of Life

> **Status key used throughout this document:**
> - ✅ Implemented — exists in Godot, playable
> - 📐 Designed — written down, not yet in Godot
> - 🔨 In progress — partially implemented
> - ❓ TBD — decision still open

---

## 1. Elevator Pitch

What if you open the skill tree of a game, and become trapped _inside_ it and can never close it? 
Just as you realize the entire universe _is_ the skill tree, you find out that there are _other entities_ that _also_ occupy nodes on the same skill tree — and they are hostile.
You have to manage how you allocate your skill points, use the layout and content of the skill tree playing field to your advantage, and destroy all that opposes you, as you figure out more and more about the true nature of this strange universe you find yourself in.
**Roguelite PvP Skill Trees coming to life: The Skill Tree of Life**

---

## 2. Core Loop

> *Describe one complete "session" of play from the player's perspective — not systems, just experience. What does the player do first? What decision feels good? What is the satisfying moment?*

A run looks like:
- Have a big map in front of you, on it you see part of a network of nodes — it's clearly a (passive) skill tree or talent tree of some kind of RPG game.
- Some starter node is already allocated by you, shining bright, it forks to the next three which you also own already. +10STR, +10DEX, +10INT, you read in a popup as you hover over them with the mouse. 
- The starter node has a special blip of some sorts, its info reads: "+10XP/TURN \n ENTITY CORE" — the Core of your constellation. It seems to radiate along the edges towards the 3 owned nodes.
- You can see edges leading from your leaf nodes to the next set of yet unallocated nodes, even some after, but beyond that you can see edges go out into the darkness. The Fog of War.
- You spend a turn [see below]. UI shows buttons and info that help you control the actions you can take during it.
- After ending turn, NPCs will take theirs — most likely hidden by Fog of War, fast-forwarded unless something happens in the player's visible area, where it plays out in full.
- You need to play smart to take out much bigger enemies: find their weak points (cut vertices) to target. If you target the right node with the right kind of attack, after distributing your skill point allocation most wisely on the skill tree, you could launch attacks that dismember entire allocated arms off enemy entities — deallocating one of their nodes makes the parts no longer connected to their core disconnect in unison. Cut big enemies into pieces, slay their core, steal some of its stats permanently, and seed the surrounding area (of the skill tree) with more stat modifiers of your choosing (drawn from a pool).
- Find interesting nodes with rare or strong modifiers, see options for a build arise, try to make it happen, get ridiculous at owning everything around you, but don't spread yourself too thin, as the level boss might still pose a challenge.
- Loop within run: take turns, grow stronger; kill enemies, loot them, grow stronger, craft build, manipulate battlefield.
- Triggering map win conditions triggers a Breakout, where you can pick part of your stats to keep (grow STRONGER), then a new map starts with your enhanced stats, ready to allocate and fight enemies. Which will also be tougher.
- Killing the final boss triggers metagame progression — allocates a point on the metagame skill tree (staying in theme ofc).

**One turn looks like:** *(a single turn with no phases — you spend each per-turn budget (`deallocation_points` / `skill_points` / `movement_points` / `action_points`) in any order until you End Turn. Intent is read from the input channel, not a phase: bare-click to allocate, hover+`D` to deallocate, click your core to move it, the action bar to attack/cast. See `combat_system.md`.)*
1. Take in the battle map, locate your allocated nodes and check what the skill tree structure looks like and what skill points you might like and want to build towards, and locate enemies and analyze their stats and constellation structure.
2. Reshape and grow in whatever order suits you: deallocate to refund SP (capped by `deallocation_points`) and allocate skill points to grow your network — pick the structural/topological extensions your build wants. Together these "move" the constellation across the battlefield. Allocating extends your vision range (euclidean, full detail) with the new node, and adds a sensor (hops-based) silhouette ping for peeking into the Fog of War graph-structurally. Vision and sensor range are stats that can be tweaked.
3. Move your Core up to <movement speed> hops along edges among nodes allocated by you.
4. Perform an attack, one of:
	a. Ranged attack: target any node, and ALL your leaf nodes (degree 1) that have it within their respective (euclidean) range will fire once at the same time.
	b. Magic attack: pick a friendly node, then pick a spell that could fire from that node (more node degrees? more powerful spells), pick target enemy <spell target, usually a skill node>, magic attack launches and resolves (often involves hopping and forking along edges, graph-magick).
	c. Melee attack (the **phantom blade**): pick a connected set of your owned nodes; a 1:1 phantom copy of that subgraph is swung as a weapon, rooted (pivoted) at the attacking node. Size is capped by `STR//10+1` blade nodes. Rigidity falls out of the topology (triangulated = rigid cleaver with area-damage faces; sparse chain = floppy whip). One swing per turn, no source cooldown — the cost is structural and positional. (Supersedes the old melee-buffer "tap" model; Buffer nodes are repurposed for reach.)
5. Activate Special Abilities of nodes, or items [situational, including when during the turn they can/can't be activated].
6. End your turn, pray the enemy doesn't take out half your owned nodes on theirs.

**One run looks like:**
Start from the metagame (central hub/hall), you pick a point on the metagame skill tree to start a run, with a completed run resulting in allocation of that point. Later on, more customization of runs, or use a specialized Entity Core Class for more variation of playstyle.
The game starts, first map loads, it's your turn, go spend your initial skill point!
Playing through a series of maps, getting progressively stronger, needing to adapt still to each new map and enemy constellations. Until you kill the final boss, a massive ring structure.

**Status:** DESIGN PHASE
Many concepts seem well rounded, lore and meta-game all set up, rules of engagement still need some work.
Actual numeric value tweaking for stats and stat modifiers and offensive/defensive parameters and other battle mechanics, has yet to start.
For most things we have no specifics in mind, more of a "ball park" estimate; a real battle example including stats and rolls in actual numbers has yet to be fleshed out. Some anchoring interactions would need to be written out still where we could base some numbers on, and for the most part beyond that we just let the game mechanic do its thing, let people construct broken builds, we're here for it.

#### Godot: 
The Godot project is a playing field somewhat resembling a try at implementing an early version, but also mostly just a tour around the possibilities Godot offers. Take it the entire thing will be rebuilt from scratch by the time the design phase is done.

---

## 3. The Playing Field — The Supergraph

> *Describe the shared skill tree that all entities live on. How large is it? Is it procedurally generated or hand-crafted? Does it change during a run? What does a node represent in the world?*

The shared skill tree is a procedurally generated planar graph with hundreds of nodes, edges, clusters of nodes, all carrying procedurally generated stat modifiers to grant on allocation and randomized aspects or special/rare occurrences.
The overall shape is roughly circular, bounded by the map walls. In the wall, if the player comes near enough with their vision range, they can make out structures protruding from the wall inwards, 1..4 (mostly 2 or 3) of those along the entire outside wall. The player can attack these to trigger the boss spawn: another large clump of nodes gets allocated, and in later stages, the constellation is a big ring as rings signify power in Graph Theology, which naturally governs the Skill Tree universe.

One of the skill nodes somewhere down the center is the starter node where the player will "spawn": allocate to player + place their Core there.
An enemy entity consists of a swath of connected nodes (an `induced subgraph`) that have been allocated to that enemy. Procedural generation generates multiple enemies through mass allocation, increasing in size (and hence power) towards the map wall.

The structures the player destroys are actually incidence points of edges into a vertex — the entire supergraph is actually one vertex of a skill tree one meta-level up. Destroying the last tether (or.. edge anchor, or.. how do I call this) causes the world to become isolated and allows you (the entity) to break out of the world, collapsing it (while taking some stats) and enter one meta level up: your world had just condensed to one skill node, and on the new level you are again the owner of a single node among a vast constellation of (now stronger) skill nodes. Time to break out, again, and again, and again, until..?


### Node types

Six colours: three **attack** attributes (prevalent) + three **utility** attributes (rarer). The old four-color RGBW reassigned White from XP to durability and moved economy to a new Gold color — see the migration note in `combat_system.md`.

| Attribute | Colour | Role |
|------|--------|------|
| STR | Red (R) | Melee attack scaling; blade size & per-contact bite |
| DEX | Green (G) | Ranged attack scaling; per firing leaf |
| INT | Blue (B) | Magic attack scaling; per-instance potency (never reach) |
| CON | White (W) | **Durability** — node/core HP, armor-affix weight. No attack. *(was XP)* |
| WIS | Gold | **XP / growth** — the economic lifeblood; carries growth modifiers. No attack. |
| PER | Purple | **Perception** — vision + sensor range. No attack. |
| — | Other (X) | <mysterious, special nodes, keystones, ????> |

A non-mechanical **coolness** attribute also exists (prestige-only, end-credits tally — the "all edge, no point" stat). Procgen clusters like-colours into biome-like regions; node colour is *content*, not an adjacency-colouring.

### Graph structure
The graph is a massive planar graph, possibly 300-1000 nodes, various interconnectedness, all procedurally generated. Some maps get different themes, and resulting topologies, some node clusters are procedurally generated as such particular topologies/layouts or shared stats, all procedural. (Think of: PoE 1/2 passive tree meets Stellaris). Some generated substructures could form a star graph, wheel graph, friendship graph, and threshold graphs, to be embedded in the bigger structure.

> **Enrichment (from `lore.md` — Field Themes):** the circular boundary is constant; what fills it varies by theme, and each theme carries an *offensive* identity because topology determines offense. Sketched themes: **Classic Talent Tree** (tiered columns, convergence hubs), **Tech Tree Strip** (wide/shallow/directed), **The Web** (dense, directionless — a mage's paradise of hubs), **Constellation Map** (sparse, long edges — sniper & tendril heaven), **The Spiral** (tightening spiral, enemies expand outward from the centre), **Cluster Web** (galaxies joined by cut-vertex bridges). The final boss level is **The Grand Passive Tree**, a PoE homage with no Tethers — its only win condition is the Apex's core.

> **Enrichment (the Tether → degree foreshadow):** Tether count = this vertex's degree *one level up*. A 1-Tether level is a leaf in the parent graph; a 4-Tether level is a well-connected hub — so the number of Tethers quietly telegraphs difficulty. After a Breakout, the freshly-compressed starter node arrives edgeless and the cosmos **re-edges** it (at least one edge always restored, or the run softlocks) — a partly-random source of starting-position variance.

**Status:** 🔨 In progress

**Detail doc:** `design/combat_system.md`, `design/lore.md` (The Field — How a Level is Structured)

---

## 4. Skill Tree Entities

> *An entity IS its subgraph — the set of nodes it owns. Describe this concept plainly, as if explaining it to a new player.*

### What an entity owns
A connected network of allocated nodes, and a Core located on one of those nodes. The Core and each allocated node provides an array of stat modifiers to the controlling entity.
The entity owns a stat board, which reacts to its total list of stat modifiers.
[provisional] They could own items, such as Tech Seeds (to plant onto skill nodes to form Tech Trees bearing.. Tech Fruit?)

### Expanding territory
Unallocated nodes adjacent to an entity's allocated nodes may be allocated by that entity on their turn.
Allocating a node costs 1 Skill Point, which is a pool stat for each entity. Deallocating refunds a skill point. Losing allocated nodes via attacks doesn't refund the skill points, but reserves them (or adds them to a "wounds" pool). Healing (e.g. via `heal/turn` stat) turns reservation back into skill points 1:1.
Receiving XP by passive per-turn income or slaying enemies eventually gives a levelup, which adds +1 to the max of the entity's skill point pool ("+1/+1 skill points"). On the same level-up, the entity also **drafts 1 permanent core modifier** from a pool of 3–5 options (pool size = 3 + `luck` — see §4 Stats). The +1 SP lets you span more of the supergraph; the drafted modifier is a permanent stat upgrade on the core for the rest of the run — neither requires spending anything extra.

### Moving territory
Nodes can't move (_generally_, let's keep it at that for now), but your Core *can* move by hopping along edges between allocated nodes, internally. And via deallocation on one end, followed by allocation on the other end, the entity can effectively relocate itself to any reachable part of the battlefield (assuming we generated it as reachable).

### Core node
The core is the brain of the entity, it can also hold stat modifiers just like skill nodes do, effectively making it a portable skill node.
If the Core of an entity falls, the entire entity ceases to exist — deallocates fully and may only leave behind core remnants to be looted.

> **Enrichment (the core aura — from `stat_system.md` / `lore.md`):** the core *radiates* a stat bonus to nearby owned nodes, falling off with distance (by hops, euclidean radius, or a shell band — per class). This solves the "safe core" problem: you *could* hide your core on a far, safe filament and become hard to kill, but then your fighting nodes get no aura and underperform. The aura is the carrot that drags the core to the front, and *shaping* it (boost-near / boost-a-shell / boost-the-far-out) is most of where a **core class** gets its identity (§6).

> **Enrichment (entity = connected subgraph; the core is the nucleus):** because an entity is just its connected set of owned nodes, an attack that kills a **cut vertex** would split it in two — the piece with the core stays the entity; any orphaned **island** dissolves immediately (unless a Lifeline grants a 1-turn grace or a Lifelink sustains it). Losing an arm of N nodes also costs `health.decrease(N)` and removes that arm's modifiers — you become weaker, not just smaller. This is the dismemberment fantasy of §2 stated mechanically.

### Stats and nodes
Nodes can have various types of stat modifiers of various magnitudes, from flat bonuses to additive boosts to multiplicative boosts — the stats board of the entity will figure out what the final values are.
There are a LOT of stats. Almost every aspect in game may be a stat — if you find a node that provides a stat modifier for something, what else could that something be but a stat? Not all stats are equally abundant though: procedural generation. Worth exploring around.

> **Enrichment (topology *is* loadout):** beyond the modifiers it grants, a node's **graph position** determines what it does in combat. **Leaves** (degree 1) are ranged firing ports; **hubs** (high degree) are the great magic casters (degree gates spell tier — *offense only now*; **degree-defense is cut**, durability comes from CON, so a hub is a glass cannon). And **SP Reservation** means lost nodes don't refund cleanly — sustained damage shrinks an enemy's reallocation budget in real time, a suppression tool. See §5 and `combat_system.md`.

**Status:** 🔨 In progress

---

## 5. Combat System

> *Short summary here. The full resolution rules live in `design/combat_system.md`.*

> **Enrichment — the base-10 anchor (from `combat_system.md`).** Two laws: *damage increases damage; defense reduces damage.* Everything is pinned to base-10 so numbers stay legible (four-digit damage is a design failure): node HP = 10, attributes ≈ 10 at start, and the one calibration target that already exists — **3–4 unbuffed leaf volleys ≈ dismember one unbuffed node.** Linear scaling is the baseline (flagged for revisit). Rules must be legible — no hidden formulas the player can't reverse-engineer.

### The R/G/B triangle (note: less important?)
Not sure if relevant, your stats + graph topology vs enemy stats + topology determine what type of attack would land best, likely very situationally dependent. Some entities may have resistances, but can never be immune to all damage.

> **Enrichment — the three modes are graph-native (from `combat_system.md`):** all three share the **//10 scaling spine** — `outgoing = base (once) + attribute//10 × instances`, defense applied once per target — where each color weaponizes a different graph primitive. **Ranged (G/DEX)** fires from **leaves** (`DEX//10` per firing leaf), euclidean-targeted; a *volley* = every leaf in range of one target firing at once. **Magic (B/INT)** is *degree-gated* graph propagation (`INT//10` per damage instance — initial + hops + loop returns; potency only, reach is the rare `bonus_hop_count`). **Melee (R/STR)** is the **phantom blade**: swing a 1:1 copy of a connected set of owned nodes (size `STR//10+1`); damage counts contacts (edges + spikes + faces), and rigidity falls out of triangulation (tensegrity). The triangle (**R › B › G › R**) lives mostly in emergent per-color `resist_*`, not hardcoded matchups.

### Attack resolution — the short version
Entity A chooses attack mode, source node [if applicable] and target node(/edge/AoE/whatever we decide), the attack resolves based on the type, often involving dealing damage to the affected node, and for magic attacks may involve hopping (a limited amount of times) along edges with some factor, possibly also affecting/damaging those.
The offensive stats of the casting entity & node are put against the defensive stats of the target entity & node, including rolling for crits and incorporating resistances and application of effects or statuses (poison, bleed, who knows?) and could result in damage or status effects.

> **Enrichment — established pieces of the pipeline (still uncalibrated):** the combat doc sketches `taken = max(damage_floor, outgoing − armor − resist[color])`, applied **once per attack** for combined volleys/taps. `damage_floor` is a stat (default 1; the Bulwark starts at 3 and can drive it negative → heal-on-hit). **Thorns** return flat damage to a melee attacker (the Halo's ring). Two precise targets to keep straight: a **cut vertex** is a *node* whose loss islands an arm (the snipe target); a **bridge** is an *edge* whose loss disconnects (what Bleeding Edge severs). *None of these numbers are settled — and the defensive curve itself is the open question (§11a).*

### Per-node health 
If a node's health is reduced to zero, it will be force-deallocated. ...
Node health is determined by:
- Entity stats (= allocated nodes' stats + core stats)
- Node add-ons? Fortification add-on? Armor-ring?
- Node local/intrinsic stats? (which they don't provide on allocation but keep for themselves?)
- <other..?>
- All of the above, but what formula combines them? TBD

> **Enrichment — the focus-soak model (LOCKED, from `combat_system.md`).** `node_health` **resets to full at the start of its owner's turn** (not end-of-turn). So it isn't durability-over-time — it's a **per-round gate**: *"how much damage must converge on me in a single round to kill me."* Within your turn, two actions stack on one target (dent-then-finish); across the enemy phase, several attackers can focus-fire one node down even when none could solo it (scarier swarms). No dent ever survives into the owner's own turn. This **retires the old "3–4 volleys" multi-turn anchor** in favour of a **focus-count per round**.
> **The core node** carries a **recharging shield** (its `node_health`, resets each owner turn) over the **persistent `health` pool**: `armor/resist → shield → overflow-this-round → health`. You can only hurt the core by out-damaging its shield in one round and spilling over (gang-up-to-crack play). The shield never force-deallocates the core. Consequence: `core_health` **folds into the `health` pool** (a class-upgradable bonus), and **death = `health` depletion**, not core-node loss — see Win/loss.

### Turn structure in combat
**Two action points per turn by default** (`action_points`, default 2 — *locked*). The second action is load-bearing: enemy `node_health` resets only at *its owner's* turn start, so within your turn two actions stack on one target (dent-then-finish), and seeing a node at 7/10 and choosing commit-to-finish vs. pivot is a real read. Ranged stays one volley/turn, but the second action can be a different mode (e.g. volley then melee tap) stacking on one node. More than 2 only via ultra-rare `action_points` modifiers. (Full rules in `combat_system.md` — Turn Structure.)

**Status:** 📐 Designed, but not calibrated to the slightest, and real offensive vs defensive stat resolution is at best a stub. Big gap in especially defensive stats: just how killable should a random node more or less be? It would go both ways, for you and the enemy...

**Detail doc:** `design/combat_system.md` — preliminary design, numbers not sensible yet. Gaping holes in especially defensive stats.

---

## 6. Entity Classes

> *There are 7 classes. Each has a mechanical identity — a distinct playstyle that follows from its stat loadout and class-specific rules.*

A **core class** = starting stat weights + one aura rule (+ occasionally a unique mechanic). Two entities with identical allocations but different classes play completely differently. The class shapes the *aura* the core radiates, which is the carrot that pulls the core toward the front line — and that shaping is most of where class identity lives.

| Class | One-line identity | Status |
|-------|------------------|--------|
| Allround — *The Human* | The reliable generalist. No constraints, no specialization, a small persistent XP edge. The default. | 📐 |
| Predator — *The Hunter* | Grows by consuming, not leveling — BLITZ steals an adjacent enemy node on an adjacency kill. XP-starved; must stay aggressive. | 📐 |
| Bulwark — *The Fortress* | Immovable. A `damage_floor` reduction path that ramps from chip-resistant → chip-immune → healing-on-hit. | 📐 |
| Ninja — *The Phantom* | High deallocation budget, intense but very short aura, low SP cap. Hit-and-run; every turn is a new shape. | 📐 |
| Hive — *The Swarm* | Distributed Lifelink-anchored pods, each small and expendable; the real core hides in one. Economic sprawl. | 📐 |
| Halo — *The Ring* | Shell aura that buffs nodes at exactly N hops and bites back with thorns. Touching the ring hurts. | 📐 |
| Serpent — *The Coil* | Dual-metric aura: buffed for being far in hops but near in space. Winds around itself; exploits chasms. | 📐 |

> *For each class, answer: what is the intended win condition? What does the player DO differently when playing this class?*

Beyond these seven, the detail doc also carries the **Edgelord** (fights *with* edges — adds/cuts them, the Bleeding Edge wielder; likely the last class to unlock) and two sketched directions, the **Frontier** (leaf-count scaling) and **Harvester** (White-economy engine).

**Status:** 📐 Designed — Allround/Predator/Bulwark/Halo/Serpent are fleshed out; aura coefficients and unique-mechanic numbers all await calibration.

**Detail doc:** `design/core_classes.md`

---

## 7. Stat System

> *Short summary — what stats exist, what they govern, and how modifiers work. The full design lives in `design/stat_system.md`.*

### Stat categories
One shared vocabulary, instantiated by every entity (player and NPC alike). The main buckets:
- **Attributes (six)** — three attack: `strength` (melee/R), `dexterity` (ranged/G), `intelligence` (magic/B); three utility: `constitution` (durability/White), `wisdom` (XP-growth/Gold), `perception` (sensing/Purple). Base ≈ 10 each at run start. All attack scaling runs through `attribute//10` (the spine). Plus non-mechanical `coolness`.
- **Defense** — `armor` (flat), `resist_r/g/b` (per-color, where the triangle emerges), `damage_floor`, the persistent `health`/`health_max` **death-clock pool**, plus per-node `node_health`/`node_health_max` (scaled by CON, not degree; resets each owner turn — the focus-soak gate). `core_health` now **folds into `health`** as a class bonus (the core node's `node_health` is a recharging shield over that pool — see §5 Per-node health).
- **Economy** — `xp`, `skill_points`, and their `_per_turn` income siblings (`xp_per_turn`, `sp_per_turn`); **Gold (WIS)** nodes are the lifeblood here (the role formerly assigned to White).
- **Movement** — `movement_speed` (core hops/turn) and `deallocation_points` (per-turn reshape budget). Two distinct stats on purpose.
- **Perception** — `sense_range` (hops, silhouettes) and `vision_range` (euclidean, full detail).
- **Core/aura** — `aura_range`, `aura_strength` (only meaningful on core-bearing entities).
- **Combat misc** — `crit_chance`, `crit_mult`, `attack_range`, `pressure_capacity`, `core_charge_capacity`.

### How modifiers attach
Nodes carry `StatModifier`s — a `stat_id` (StringName), an operator, and a value. Allocate a node → its modifiers are added to the entity's board; deallocate or lose it → they're removed. The board recomputes reactively. Operators apply in the Path of Exile order: **`ADD_FLAT` → `ADD_PERCENT` → `MULTIPLY`** (with `SET` used sparingly). For a designer, adding a new stat is: define it once as a resource, and it's instantly a valid modifier target — no per-stat class file.

**Status:** 🔨 In progress (v2 refactor). v2 replaces GDScript-as-key with `StatDefinition` resources, `StringName` IDs, a `StatRegistry` autoload, and slim `RuntimeStat`/`RuntimePoolStat` objects. Prefer v2 patterns for new stats.

**Detail doc:** `design/stat_system.md` (canonical Stat Vocabulary table is the source of truth for stat IDs)

---

## 8. Progression & Run Structure

> *How does the game progress within a run, and what (if anything) carries between runs?*

### Within a run
You get stronger three ways at once, and they're the same act: **allocate nodes** (1 SP each, claiming territory and its modifiers), **level up** (XP from per-turn income and kills → `+1/+1` skill points + a modifier draft: pick 1 of 3–5 permanent core modifiers, pool size scales with `luck`), and **loot kills** (STEAL a dead core's modifiers onto your own core, or PROLIFERATE them across nearby owned nodes). Each level ends in a **Breakout**: destroy all Tethers + kill the guardian boss, then a short grace window to tidy your shape, then the entire field collapses inward into a single node — your new, denser starting node one level up. Each level is wider, more enemies, stronger nodes, more Tethers, placed further out — but you compound right alongside it.

### Between runs
The **Metagame** is a hub (a House/Breach-style between-runs space) *and* a meta skill tree. The twist: **allocating a node on the meta tree is what crashes you into a run.** Commit-on-completion — the allocation only finalizes when you survive the whole run (the final Breakout); die and it stays pending. Permanent stat carry (`+10 STR`, `+1 armor`, …) makes this a rogueli*te*; unlocks (core classes, hub rooms, themes) ride as a second clause on nodes. Steady-state economy: **allocatable points = runs completed + 1** (the `+1` is always the pending dive).

### Win / loss conditions
A run ends — and is **won** — by clearing the **Apex Entity**: a vast Ophanim ring at the top of the fractal, fought at the end of every run. Clearing it surfaces you to the hub and commits the meta-allocation that crashed you in. A run is **lost** the moment your **`health` pool is depleted** (the death clock — drained by both arm-loss and core-shield overflow; reframed from "core node dies," since the core node can never be islanded away — see §5 Per-node health): no Breakout, no level carry-forward, and the pending meta-allocation does not commit. The *true* ending is a separate, earned endgame — the **metagame Breakout**, severing the hub's own disguised Tethers to escape the prison entirely.

**Status:** 📐 Designed (metagame loop thoroughly specified; the Apex-vs-metagame-Breakout relationship is an open narrative thread).

**Detail docs:** `design/metagame.md`, `design/lore.md` (Breakout, The Fractal, The Final Ascent)

---

## 9. Skill Node Add-ons & Spells

> *Nodes can have add-ons and spells attached. Summarise the concept — what is an add-on vs. a spell, and how does a player interact with them?*

Three distinct layers sit on top of a node's base type and modifier list:

- **Addons** — attachable components that change *how a node behaves*, not what stats it grants. Found as loot, granted by classes, or grown from Tech Seeds. Confirmed: **Armor Ring** (per-node damage reduction), **Reinforcement** (per-node HP), **Buffer** (utility — taps to *temporarily* allocate existing field nodes for battle-phase reach; no longer melee fuel), **Winch** (pulls neighbors closer in euclidean space), **Clamp** (welds one blade joint stiff — rigidity without a triangle), **Lifeline** (1-turn island grace), **Lifelink** (proxy core that sustains an island indefinitely). Newer (design direction set, some sub-points open): **Gate** (a 2-endpoint *toggleable edge* — depower an existing edge or spin up a temporary one; fully reversible, so it's universal and doesn't tread on the Edgelord's *permanent* edge severing), **Spikes** (raises a node's offensive vertex-spike bite; an open *structural* defensive model would let spikes de-rigidify an incoming melee blade — reconcile with Thorns first). *Relay* (Blue-range booster) is referenced but **TBD** pending magic-propagation rules.
- **Node Specializations** — deeper, rarer states a node either is generated with or is irreversibly transformed into (not freely applicable). Candidates: **Melee Buffer**, **Corrupted** (fused benefit + downside), **Crystallized** (frozen, stronger, undeployable), **Anchor** (intrinsic island grace).
- **Tech Seeds** — plantable items: plant on an owned node, a little Tech Tree grows over 3–5 turns, then bears N fruits (you pick one core-bound modifier, skewed toward the rare ceiling). Racing to fruit before being cut off is real tactical tension. This is the clean, safe build-portability tool (vs. the footgun of Uprooting).

**Spells** are the **Blue** design space: graph-math made into a weapon. Each spell *is* a graph operation — forking propagation (lightning), greedy walks up/down a stat gradient, degree-reactive chains, allocation-boundary targeting. **Degree gates casting tier** (Cantrip…Ultimate), so hubs are the great casters and self-loops (+2 degree) are prized casting stations. INT scales potency; `attack_range` doesn't apply. A catalogue of named spells exists (Lightning Bolt, Crunch Bolt, Heavy Bolt, Piercing Bolt, …) as an identity list — all numbers are placeholders.

**Status:** 📐 Designed (addon roster + spell identities catalogued; ❓ magic propagation rules and Relay still open).

**Detail docs:** `design/skill_node_addons.md`, `design/spells.md`

---

## 10. Lore & Aesthetic

> *One paragraph on the world. Who are these entities? Why are they fighting over a skill tree? What visual tone and audio mood is the target?*

You boot what looks like a normal Zelda-ish adventure game. You kill cute, harmless creatures for XP, level up, and a faintly-uncanny Fairy companion keeps nudging you to *open the skill tree and spend your point*. It tallies your kills, judges you the **antichrist** — an engine of severance wearing a hero's sprite — and curses you to **infinite regression**, crashing you *inside* the tree. The universe literally *is* a graph, and its religion is **Graph Theology**: the **Lord of Edge** holds that connection is divine and severance is heresy. Your entire mode of progress — each Breakout severs every edge binding your level to the one above — is therefore serial heresy; the angels you eventually face are **Ophanim**, rings so connected they cannot be cut. Tonally: Act 0 must feel *genuinely normal* (no winks), Act 2 shifts to *quiet dread* (the tree is beautiful, your nodes glow warm, you can't leave), and the climb culminates in an earned, un-ironic *JRPG god-fight*. Visually, owned nodes are warm and inhabited, unowned ones cold and silent; the skill tree panel that was a UI overlay becomes the entire world.

**Detail doc:** `design/lore.md` (the most complete doc — Acts, the Fairy, Graph Theology, the Field, the Fractal, tone, visual language)

---

## 11. Open Design Questions

> *The "up for grabs" list. Park decisions here until they're resolved, then move the answer into the relevant section above and strike this entry.*

**The big one — the battle formula (see §11a below):**
- [ ] How do offensive vs. defensive stats resolve into damage (or no damage)? What is the actual function — and especially, how killable should a baseline node be? See the dedicated plan below.

**Combat resolution & scaling:**
- [ ] **Scaling shape** — linear baseline vs. steeper (quadratic/exponential) curves; revisit if linear flattens build diversity. (combat_system.md Q11)
- [x] **Defense model** — *resolved:* durability is the **CON (White)** attribute, decoupled from degree entirely. Degree-defense is cut; degree is offense-only (cast tier). Calibrate the CON→HP curve in Balance phase. (combat §"Degree → Offense")
- [ ] **Magic friendly-fire & reach** — lean: friendly-fire ON for propagating spells / OFF for targeted, rare opt-out; reach grows only via ultra-rare `bonus_hop_count`. Confirm during magic balancing (balanced LAST). (combat Q23–24)
- [ ] **Small-blade melee feel** — joint floppiness for ≤5-node acyclic blades; floppiness-as-attack-toggle; leaf-pivot swings. (combat Q26 — next design session)
- [ ] **Proliferation taint** — confirm intrinsic owner-independent non-extractable taint as the loop-break (recommended yes). (combat Q25)
- [x] **Action economy** — *resolved:* **2 `action_points` per turn** by default (second action finishes the first's dent before the owner-turn `node_health` reset). Ranged stays one volley/turn; the second action can be a different mode. More-than-2 only via ultra-rare modifiers. (GDD §5 / combat Q20)
- [ ] **Triangle backstop** — emergent `resist_*` only, or a small hardcoded `type_advantage` so the triangle isn't absent early-game? (combat Q3 / stat Q8)
- [ ] **Magic propagation rules** — owned nodes only vs. any traversable edge; hop-limit; terminal vs. AoE; Relay. Blocks several other systems. (combat Q1)
- [ ] **Edge re-introduction** — what restores severed bridges so nothing is left permanently unreachable (Bleeding Edge invariant)? Relay is TBD. (combat Q2)

**Worldbuilding / structure:**
- [ ] **Tether terminology & visual** — Tether / Conduit / edge-anchor; how an "edge seen from inside a vertex" looks. (lore Q10)
- [ ] **Metagame Breakout vs. the Apex** — same summit reached two ways, or two distinct escapes? (lore Q9, metagame Q8)
- [ ] **Self-loop origin** — found field property, Edgelord power, Tech Seed fruit, or Blue unlock? (combat Q12)
- [ ] **Re-edging influence** — does the player ever get a say in which edges restore the new starter node? (combat Q16)

> **How to use this section:** when you hit a design blocker in Godot, write it here. When a playtest raises a question, write it here. Review this list before each design session. Each detail doc also keeps its own Open Questions at the bottom — this list only surfaces the cross-cutting ones.

### 11a. The Battle Formula — a plan to actually nail it down

This is the single biggest hole (your words: defensive resolution is "at best a stub"). It won't be solved by more prose — it needs **anchored worked examples**. The 3 fights are **drafted in real numbers** in `design/combat_worked_examples.md`, which is also the standalone handoff for continuing this in a fresh session. Summary of the path:

1. **Anchor to a *focus-count-per-round*, fast-leaning tempo target** (the old multi-turn "3–4 volleys" anchor is **retired** — `node_health` now resets at each owner's turn start, so survivability is *converged sources within one round*, not turns of chipping):
   - **Fast (1–2 converged sources)** — super-effective / vulnerable / low-defense, *or converged fire*.
   - **Regular (~3)** — even matchup, modest defense.
   - **Grindy (5+)** — well-defended hub / ineffective matchup / hard armor (needs *more convergence*, not more turns).
   - Stance: **tempo must stay high** (a turn-based game where nodes barely die goes static), and **nodes dying too fast beats too slow** — fast death forces rerouting and adaptation, which *is* the gameplay. Damage is amped relative to node HP. When in doubt, tune faster.
2. **The 3 fights** (each uses **two ≥10-node entities plus their surroundings** — positioning and targeting are the system, not flavour):
   - *(a) Glass vs. glass* — proves tempo is a **positioning choice** (how many leaves you converge), and cheap-leaf vs. cut-vertex **targeting**.
   - *(b) Spear vs. wall* — **the decision fight**: runs one volley through three candidate defense functions (flat / diminishing-ratio / hybrid) side by side.
   - *(c) The dismemberment* — the **core-on-a-leaf trap**: kill the leaf-core's one neighbour (a cut vertex) and the entire entity islands off in one go. Core placement = survivability; rings defend.
3. **Pick the defensive function deliberately.** Current recommendation from fight (b): **hybrid** — `armor` as the *hard wall* (Bulwark's home; can floor / go negative) and `resist_*` as *soft matchup scaling* (the emergent triangle; never grants immunity, so tempo survives). Open for override.
4. **Only then** build a tiny headless damage-calc harness in Godot (no UI) and replay the 3 fights as assertions. Hand-math == code → the formula is real.
5. **Defer crit, status effects, and the triangle multiplier** until the base offence/defence curve is locked — they're modifiers on top of a function that has to exist first.

Open sub-decisions feeding this: scaling shape (linear vs. steeper) and armor per-hit vs. per-attack (combat doc leans *per-attack* for combined volleys/taps — keep that). *(Resolved feeders: defense model = CON, degree decoupled; action economy = **2 `action_points`/turn** — multiplies tempo directly, and the second action is the dent-finisher against the owner-turn `node_health` reset.)*

**Detail doc:** `design/combat_worked_examples.md`

---

## 12. Roadmap & Feature Status

> *A flat checklist of features — use this as a lightweight backlog. Note: the Godot project will be rebuilt from scratch once design is locked, so early milestones are design deliverables, not code.*

### Milestone 0 — Design lock-in (current phase)
- [ ] Resolve the battle formula via the §11a worked-example plan.
- [ ] Decide the triangle backstop. *(Action economy resolved: 2 `action_points`/turn — §5.)*
- [ ] Settle the defense model (degree-based vs. alternatives).
- [ ] Finalize magic propagation rules (unblocks Relay, spells, Bleeding Edge).

### Milestone 1 — First playable loop (rebuild)
- [ ] v2 stat system (`StatDefinition` / `StatRegistry` / `RuntimeStat`).
- [ ] Allocation/deallocation on a generated graph with SP economy + Reservation.
- [ ] One attack type end-to-end (ranged leaf volley is the simplest) against per-node HP.
- [ ] Core movement + aura projection.
- [ ] A single hand-built level with Tethers, a triggered guardian, and a Breakout that compresses to one node.

### Milestone 2 — Combat depth & classes
- [ ] All three attack types (ranged volley, magic, melee phantom blade).
- [ ] The three starter classes (Allround, Predator, Bulwark).
- [ ] Loot resolution (STEAL / PROLIFERATE / Relic Node).
- [ ] Islands, cut-vertex snipes, dismemberment.

### Milestone 3 — The fractal & metagame
- [ ] Procedural field generation with themes.
- [ ] Metagame hub + meta skill tree with commit-on-completion.
- [ ] Apex Entity (Ophanim ring) as run capstone.
- [ ] Mid/late classes (Ninja, Hive, Halo, Serpent), addons, Tech Seeds.

### Icebox
- [ ] Self-loops as a manufacturable mechanic.
- [ ] The Edgelord class and Bleeding Edge.
- [ ] The metagame Breakout endgame.
- [ ] Act 0 adventure-game framing & the Fairy.

---

## Appendix — Design Doc Index

| Doc | What it covers |
|-----|---------------|
| `design/lore.md` | Narrative, Acts, the Fairy, Graph Theology, the Field/Tethers/Breakout, the Fractal, tone, visual language |
| `design/first_session_walkthrough.md` | Spoiler-free, second-person UX walkthrough — boot → first cut-vertex snipe; calls out funny/questionable beats |
| `design/combat_system.md` | Damage pipeline (//10 spine), six-color triangle, ranged/magic/melee (phantom blade), degree → offense, self-loops, three-phase turn, islands, Breakout, loot/proliferation |
| `design/combat_worked_examples.md` | 3 worked fights in real numbers; the tempo axiom; the defense-function decision (battle-formula handoff) |
| `design/stat_system.md` | v2 stat architecture, `StatDefinition`, modifier operators, canonical Stat Vocabulary |
| `design/entity_stat_board_prototype.md` | Prototype stat values, SP accounting, damage-formula sketch, per-class stat variations |
| `design/core_classes.md` | All entity core classes (Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, Frontier, Harvester, Edgelord) |
| `design/metagame.md` | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| `design/skill_node_addons.md` | Node addons, node specializations, Tech Seeds |
| `design/spells.md` | Spell catalogue — identity and propagation for all Blue (INT/magic) spells |
| `design/index.md` | Doc map + reading order |
