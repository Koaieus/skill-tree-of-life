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

**One turn looks like:**
1. Take in the battle map, locate your allocated nodes and check what the skill tree structure looks like and what skill points you might like and want to build towards, and locate enemies and analyze their stats and constellation structure.
2. Spend skill points, possibly use per-turn deallocation budget to deallocate points first. Allocate skills you want to have or your build could benefit from structurally/topologically. Allocate skills to grow your network and deallocate to shrink — or to "move" your constellation across the battlefield [you can do this freely during your turn]. Allocating nodes extends your vision range (euclidean) with that node, and it will act as a sensor (hops-based) for peeking into the Fog of War graph-structurally without any detailed information on node contents or ownership. This allows you to see and plan a bit ahead. Vision and sensor range are also stats that can be tweaked.
3. Move your Core up to <movement speed> hops along edges among nodes allocated by you.
4. Perform an attack, one of:
    a. Ranged attack: target any node, and ALL your leaf nodes (degree 1) that have it within their respective (euclidean) range will fire once at the same time.
    b. Magic attack: pick a friendly node, then pick a spell that could fire from that node (more node degrees? more powerful spells), pick target enemy <spell target, usually a skill node>, magic attack launches and resolves (often involves hopping and forking along edges, graph-magick).
    c. Melee attack: pick a melee attack pattern (jab, swing, ...), pick a friendly node to attack from (within striking range to enemy nodes), then select whether to use all [default] or some of your melee-buffer nodes. The melee attack then performs, and the selected amount of your specialized melee-buffer nodes got _tapped_ in the process, now vulnerable and inactive for this turn and the next.
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
| Type | Colour | Role |
|------|--------|------|
| STR | Red (R) | Provide STR-related stat modifiers, and more |
| DEX | Green (G) | Provide DEX-related stat modifiers, and more |
| INT | Blue (B) | Provide INT-related stat modifiers, and more |
| XP | White (W) | Mainly provide XP-related stat modifiers, economy, greed, ramping |
| — | Other (X) | <mysterious, special nodes, keystones, ????> |

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
Receiving XP by passive per-turn income or slaying enemies eventually gives a levelup, which adds +1 to the max of the entity's skill point pool ("+1/+1 skill points"). This is pure growth, you can now span more of the entirety of the supergraph.

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

> **Enrichment (topology *is* loadout):** beyond the modifiers it grants, a node's **graph position** determines what it does in combat. **Leaves** (degree 1) are ranged firing ports; **hubs** (high degree) are the great magic casters (degree gates spell tier); **degree also braces defense** (more incident edges → more effective HP). And **SP Reservation** means lost nodes don't refund cleanly — sustained damage shrinks an enemy's reallocation budget in real time, a suppression tool. See §5 and `combat_system.md`.

**Status:** 🔨 In progress

---

## 5. Combat System

> *Short summary here. The full resolution rules live in `design/combat_system.md`.*

> **Enrichment — the base-10 anchor (from `combat_system.md`).** Two laws: *damage increases damage; defense reduces damage.* Everything is pinned to base-10 so numbers stay legible (four-digit damage is a design failure): node HP = 10, attributes ≈ 10 at start, and the one calibration target that already exists — **3–4 unbuffed leaf volleys ≈ dismember one unbuffed node.** Linear scaling is the baseline (flagged for revisit). Rules must be legible — no hidden formulas the player can't reverse-engineer.

### The R/G/B triangle (note: less important?)
Not sure if relevant, your stats + graph topology vs enemy stats + topology determine what type of attack would land best, likely very situationally dependent. Some entities may have resistances, but can never be immune to all damage.

> **Enrichment — the three modes are graph-native (from `combat_system.md`):** **Ranged (G/DEX)** fires only from **leaves**, euclidean-targeted; a *volley* = every leaf in range of one target firing at once (armor/resist apply once to the combined hit). **Magic (B/INT)** is *degree-gated* graph propagation (hubs cast the heavy spells; each spell is its own graph operation; `attack_range` doesn't apply). **Melee (R/STR)** is adjacency, via *tap-and-recover* — tap a subset of Buffer nodes into one combined strike; tapped nodes are vulnerable next turn. The triangle (**R › B › G › R**) lives mostly in emergent per-color `resist_*`, not hardcoded matchups.

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

### Turn structure in combat
Generally, an entity can perform one attack during its turn. Or maybe 2, or set by `<action points>` stat starting at 1.
Or they get one of each type of stat, not sure. Pending more fleshed out flow / balance.

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
- **Attributes** — `strength` (melee/R), `dexterity` (ranged/G), `intelligence` (magic/B). Base ≈ 10 each at run start.
- **Defense** — `armor` (flat), `resist_r/g/b` (per-color, where the triangle emerges), `damage_floor`, `health`/`health_max`, plus per-node `node_health`/`node_health_max`, and `core_health`.
- **Economy** — `xp`, `skill_points`, and their `_per_turn` income siblings (`xp_per_turn`, `sp_per_turn`); White nodes are the lifeblood here.
- **Movement** — `movement_speed` (core hops/turn) and `deallocation_points` (per-turn reshape budget). Two distinct stats on purpose.
- **Perception** — `sense_range` (hops, silhouettes) and `vision_range` (euclidean, full detail).
- **Core/aura** — `aura_range`, `aura_strength` (only meaningful on core-bearing entities).
- **Combat misc** — `crit_chance`, `crit_mult`, `attack_range`, `pressure_capacity`, `core_charge_capacity`.

### How modifiers attach
Nodes carry `StatModifierDef`s — a `stat_id` (StringName), an operator, and a value. Allocate a node → its modifiers are added to the entity's board; deallocate or lose it → they're removed. The board recomputes reactively. Operators apply in the Path of Exile order: **`ADD_FLAT` → `ADD_PERCENT` → `MULTIPLY`** (with `SET` used sparingly). For a designer, adding a new stat is: define it once as a resource, and it's instantly a valid modifier target — no per-stat class file.

**Status:** 🔨 In progress (v2 refactor). v2 replaces GDScript-as-key with `StatDefinition` resources, `StringName` IDs, a `StatRegistry` autoload, and slim `RuntimeStat`/`RuntimePoolStat` objects. Prefer v2 patterns for new stats.

**Detail doc:** `design/stat_system.md` (canonical Stat Vocabulary table is the source of truth for stat IDs)

---

## 8. Progression & Run Structure

> *How does the game progress within a run, and what (if anything) carries between runs?*

### Within a run
You get stronger three ways at once, and they're the same act: **allocate nodes** (1 SP each, claiming territory and its modifiers), **level up** (XP from per-turn income and kills → `+1/+1` skill points, more of the tree you can span), and **loot kills** (STEAL a dead core's modifiers onto your own core, or PROLIFERATE them across nearby owned nodes). Each level ends in a **Breakout**: destroy all Tethers + kill the guardian boss, then a short grace window to tidy your shape, then the entire field collapses inward into a single node — your new, denser starting node one level up. Each level is wider, more enemies, stronger nodes, more Tethers, placed further out — but you compound right alongside it.

### Between runs
The **Metagame** is a hub (a House/Breach-style between-runs space) *and* a meta skill tree. The twist: **allocating a node on the meta tree is what crashes you into a run.** Commit-on-completion — the allocation only finalizes when you survive the whole run (the final Breakout); die and it stays pending. Permanent stat carry (`+10 STR`, `+1 armor`, …) makes this a rogueli*te*; unlocks (core classes, hub rooms, themes) ride as a second clause on nodes. Steady-state economy: **allocatable points = runs completed + 1** (the `+1` is always the pending dive).

### Win / loss conditions
A run ends — and is **won** — by clearing the **Apex Entity**: a vast Ophanim ring at the top of the fractal, fought at the end of every run. Clearing it surfaces you to the hub and commits the meta-allocation that crashed you in. A run is **lost** the moment your **core node** dies: no Breakout, no level carry-forward, and the pending meta-allocation does not commit. The *true* ending is a separate, earned endgame — the **metagame Breakout**, severing the hub's own disguised Tethers to escape the prison entirely.

**Status:** 📐 Designed (metagame loop thoroughly specified; the Apex-vs-metagame-Breakout relationship is an open narrative thread).

**Detail docs:** `design/metagame.md`, `design/lore.md` (Breakout, The Fractal, The Final Ascent)

---

## 9. Skill Node Add-ons & Spells

> *Nodes can have add-ons and spells attached. Summarise the concept — what is an add-on vs. a spell, and how does a player interact with them?*

Three distinct layers sit on top of a node's base type and modifier list:

- **Addons** — attachable components that change *how a node behaves*, not what stats it grants. Found as loot, granted by classes, or grown from Tech Seeds. Confirmed: **Armor Ring** (per-node damage reduction), **Reinforcement** (per-node HP), **Buffer** (lets a node charge melee bursts), **Winch** (pulls neighbors closer in euclidean space), **Lifeline** (1-turn island grace), **Lifelink** (proxy core that sustains an island indefinitely). *Relay* (Blue-range booster) is referenced but **TBD** pending magic-propagation rules.
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
- [ ] **Defense model** — current sketch is `effective HP = base + (degree − 1)` on *total* degree. Alternatives: owned-neighbor count, territorial depth, local clustering. Decide after first hub-vs-filament playtests. (combat Q19)
- [ ] **Action economy** — one attack per turn, an `action_points` stat, or one of each attack type? (GDD §5)
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

This is the single biggest hole (your words: defensive resolution is "at best a stub"). It won't be solved by more prose — it needs **anchored worked examples**. Proposed path:

1. **Lock the anchor invariants first** (these already exist, treat them as axioms): base node HP = 10; attributes ≈ 10 at start; **"3–4 unbuffed leaf volleys ≈ dismember one unbuffed node."** Everything else is fitted to satisfy these.
2. **Write 3 canonical fights by hand**, in real numbers, before touching Godot:
   - *(a) Glass vs. glass* — two unbuffed entities, leaf volley vs. a degree-2 node. Confirm the 3–4 volley anchor holds.
   - *(b) Spear vs. wall* — a DEX attacker into an armored/Reinforced hub. This is where the **defensive curve** reveals itself: does armor subtract flat, scale, or cap?
   - *(c) A dismemberment* — a cut-vertex snipe that islands an arm. Confirm the arm-loss health hit + SP Reservation feel right.
3. **Pick the defensive function deliberately.** Candidates to test on example (b): pure flat (`taken = atk − armor`, floored), diminishing (`atk × atk/(atk+armor)`), or hybrid (flat armor + per-color resist as the current pipeline assumes). Decide by which keeps numbers legible (no four-digit values) *and* keeps a baseline node killable in a satisfying number of hits — from both sides.
4. **Only then** build a tiny headless damage-calc harness in Godot (no UI) and replay the 3 fights as assertions. If the hand math and the code agree, the formula is real.
5. **Defer crit, status effects, and the triangle multiplier** until the base offence/defence curve is locked — they're modifiers on top of a function that has to exist first.

Open sub-decisions feeding this: scaling shape (linear vs. steeper), the defense model (degree-based vs. alternatives), and whether armor is per-hit or per-attack (combat doc leans *per-attack* for combined volleys/taps — keep that).

---

## 12. Roadmap & Feature Status

> *A flat checklist of features — use this as a lightweight backlog. Note: the Godot project will be rebuilt from scratch once design is locked, so early milestones are design deliverables, not code.*

### Milestone 0 — Design lock-in (current phase)
- [ ] Resolve the battle formula via the §11a worked-example plan.
- [ ] Decide action economy (§5) and the triangle backstop.
- [ ] Settle the defense model (degree-based vs. alternatives).
- [ ] Finalize magic propagation rules (unblocks Relay, spells, Bleeding Edge).

### Milestone 1 — First playable loop (rebuild)
- [ ] v2 stat system (`StatDefinition` / `StatRegistry` / `RuntimeStat`).
- [ ] Allocation/deallocation on a generated graph with SP economy + Reservation.
- [ ] One attack type end-to-end (ranged leaf volley is the simplest) against per-node HP.
- [ ] Core movement + aura projection.
- [ ] A single hand-built level with Tethers, a triggered guardian, and a Breakout that compresses to one node.

### Milestone 2 — Combat depth & classes
- [ ] All three attack types (ranged, magic, melee tap-and-recover).
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
| `design/combat_system.md` | Damage pipeline, RGBW triangle, ranged/magic/melee, degree → defense, self-loops, islands, Breakout, loot |
| `design/stat_system.md` | v2 stat architecture, `StatDefinition`, modifier operators, canonical Stat Vocabulary |
| `design/entity_stat_board_prototype.md` | Prototype stat values, SP accounting, damage-formula sketch, per-class stat variations |
| `design/core_classes.md` | All entity core classes (Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, Frontier, Harvester, Edgelord) |
| `design/metagame.md` | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| `design/skill_node_addons.md` | Node addons, node specializations, Tech Seeds |
| `design/spells.md` | Spell catalogue — identity and propagation for all Blue (INT/magic) spells |
| `design/index.md` | Doc map + reading order |
