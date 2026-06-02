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
- Some starter node is already allocated by you, shining bright, it forks to the next three which you also own already.  +10STR, +10DEX, +10INT, you read in a popup as you hover over them with the mouse. 
- The starter node has a special blip of some sorts, its info reads: "+10XP/TURN \n ENTITY CORE" — the Core of your constellation. It seems to radiate along the edges towards the 3 owned nodes.
- You can see edges leading from your leaf nodes to the next set of yet unallocated nodes, even some after, but beyond that you can see edges go out into the darkness. The Fog of War.
- You spend a turn [see below]. UI shows buttons and info that help you controlling actions you can take during.
- After ending turn, NPCs will take theirs — mostly likely hidden by Fog of War, fast forward unless something happens in player's visible area, there it plays out in full.
- You need to play smart to take out much bigger enemies, find their weakpoints and, weak points (cut vertices) to target. If you target the right node with the right kind of attack, after distributing your skill point allocation most wisely on the skill tree, you could launch attacks where you may dismember out entire allocated arms of enemy entities by deallocating one of their nodes ones no longer connected to their core to disconnect in unison. Cut big enemies into pieces, slay their core, steal some of its stats permanently, and seed the surrounding area (of the skill tree) with more stat modifiers of your choosing (drawn from a pool).
- Find interesting nodes with rare or strong modifiers, see options for a build arise, try make it happen, get ridiculous at owning everythingaround you, but don't spread yourself too thin, as the level boss might still pose a challenge
- Loop within run: take turns, grow stronger; kill enemies, loot them, grow stronger, craft build, manipulate battlefield.
- Triggering map win conditions triggers a breakout, where you can pick part of your stats to keep (grow STRONGER), then a new map starts with your enhanced stats, ready to allocate and fight enemies. Which will also be tougher.
- Killing the final boss, triggers metagame progression — allocates a point on the metagame skill tree (staying in theme ofc).

**One turn looks like:**
1. Take in the battle map, locate your allocated nodes and check what the skill tree structure looks like and what skill points you might like and want to build towards, and locate enemies and analyze their stats and constellation structure.
2. Spend skill points, possibly use per/turn deallocation budget to deallocate points first. Allocate skills you want to have or your build could benefit from structurally/topologically. Allocate skills to grow your network and deallocate to shrink — or to "move" your constellation across the battlefield [you can do this freely during your turn]. Allocating nodes extends your vision range (euclidean) with that that node, and it will act as a sensor (hops-based) for peeking into the Fog of War graph-structurally without any detailed information on node contents or ownership. This allows you to see and plan a bit ahead. Vision and sensor range are also stats that can be tweaked.
3. Move your Core up to <movement speed> hops along edges among nodes allocated by you.
4. Perform an attack, one of:
    a. Ranged attack: target any node, and ALL your leaf nodes (degree 1) that have it within their respective (euclidean) range will fire once at the same time.
    b. Magic attack: pick a friendly node, then pick a spell that could fire from that node (more node degrees? more powerful spells), pick target enemy <spell target, usually a skill node>, magic attack launches and resolves (often involves hopping and forking along edges, graph-magick).
    c. Melee attack: pick a melee attack pattern (jab, swing, ...), pick a friendly node to attack from (within striking range to enemy nodes), then select whether to use all [default] or some of your melee-buffer nodes. The melee attack then performs, and the selected amount of your specialized melee-buffer nodes got _tapped_ in the process, now vulnerable and inactive for this turn and the next.
5. Activate Special Abilities of nodes, or items [situational, including when during the turn they can/can't be activated]
6. End your turn, pray the enemy doesn't take out half your owned nodes on theirs.

**One run looks like:**
Start from the metagame (central hub/hall), you pick a point on the metagame skill tree and to start a run, with a completed run resulting in allocation of that point. Later on, more customization of runs, or use a specialized Entity Core Class for more variation of playstyle.
The game starts, first map loads, it's your turn, go spend your initial skill point!
Playing through a series of maps, getting progressively stronger, needing to adapt still to each new map and enemy constellations. Until you kill the final boss, a massive ring structure.

**Status:** DESIGN PHASE
Many concepts seem well rounded, lore and meta-game all set up, rules of engagement still need some work.
Actual numeric value tweaking for stats and stat modifiers and offensive/defensive parameters and other battle mechanics, has yet to start.
For most things we have no specifics in mind, more of a "ball park" estimate, a real battle example including stats and rolls in actual numbers has yet to be fleshed out. Some anchoring interactions would need to be written out still where we could base some numbers on, and for the most part beyond that we just let the game mechanic do its thing, let people construct broken builds, we're here for it.

#### Godot: 
The Godot project is a playing field of somewhat resembling a try of implementing an early version, but also mostly just a tour around the possibilities Godot offers. Take it the entire thing will be rebuilt from scratch by the time the design phase is done.

---

## 3. The Playing Field — The Supergraph

> *Describe the shared skill tree that all entities live on. How large is it? Is it procedurally generated or hand-crafted? Does it change during a run? What does a node represent in the world?*
The shared skill tree is procedurally generated planar graph with hundreds of nodes, edges, clusters of nodes, all carrying procedurally generated stat modifiers to grant on allocation and randomized aspects or special/rare occurences.
The overall shape is roughly circular, bounded by the map walls. In the wall, if the player comes near enough with their vision range, they can make out structures protruding from the wall inwards, 1..4 (mostly 2 or 3) of those along the entire outside wall. The player can attack these to trigger the boss spawn: another large clump of nodes gets allocated, and in later stages, the constellation is a big ring as rings signify power in Graph Theology, which naturally governs the Skill Tree universe.

One of the skill nodes somewhere down the center is the starter node where the player will "spawn": allocate to player + place their Core there.
An enemy entity consist of a swath of connected nodes (an `induced subgraph`) that have been allocated to that enemy. Procedural generation generates multiple enemies through mass allocation, increasing in size (and hence power) towards the map wall.

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
The graph is a massive planar graph, possibly 300-1000 nodes, various interconnectedness, all procedurally generated. Some maps get different themes, and resulting topologies, some node clusters are procedurally generated as such particular topologies/layouts or shared stats, all procedural. (Thinkof:  PoE 1/2 passive tree meets Stellaris). Some generated substructures could form a star graph, wheel graph, friendship graph, and threshold graphs, to be embedded in the bigger structure.

**Status:** 🔨 In progress

**Detail doc:** `design/combat_system.md`

---

## 4. Skill Tree Entities

> *An entity IS its subgraph — the set of nodes it owns. Describe this concept plainly, as if explaining it to a new player.*

### What an entity owns
A connected network of allocated nodes, and a Core located on one of those nodes. The Core and each allocated node provides an array of stat modifiers to the controlling entity.
The entity owns a stat board, which reacts to its total list of stat modifiers.
[provisional] They could own items, such as Tech Seeds (to plant onto skill nodes to form Tech Trees bearing.. Tech Fruit?)

### Expanding territory
Unallocated nodes adjacent to an entity's allocated nodes may be allocated by that entity on their turn.
Allocating a node costs 1 Skill Point, which is a pool stat for each entity. Deallocating refunds a skill point. Losing allocated nodes via attacks doesn't refund the skill points, but reserves them (or adds them to "wounds" pool). Healing (e.g. via `heal/turn` stat) turns reservation back into skill points 1:1.
Receiving XP by passive per-turn income or slaying enemies, eventually gives a levelup, which adds +1 to the max of the entity's skill point pool ("+1/+1 skill points"). This is pure growth, you can now span more of the entirety of the supergraph.

### Moving territory
Nodes can't move (_generally_, let's keep it at that for now), but your Core *can* move by hopping along edges between allocated nodes, internally. And via deallocation one one end, followed by allocation on the other end, the entity can reach every possible itself across the battlefield (assuming we generated it as reachable)

### Core node
The core is the brain of the entity, it can also hold stat modifiers just like skill nodes do, effectively making it a portable skill node.
If the Core of an entity falls, the entire entity ceases to exist — deallocates fully and may only leave behind core remnants to be looted.

### Stats and nodes
Nodes can have various types of stat modifiers of various magnitudes, from flat bonuses to additive boosts to multiplicative boosts — the stats board of the entity will figure out what the final values are.
There are a LOT of stats. Almost every aspect in game may be a stat — if you find a node that provides a stat modifier for something what else could that something be but a stat? Not all stats are equally abundant though: procedural generation. Worth exploring around.

**Status:** 🔨 In progress

---

## 5. Combat System

> *Short summary here. The full resolution rules live in `design/combat_system.md`.*

### The R/G/B triangle (note: less important?)
Not sure if relevant, your stats + graph topology vs enemy stats + topology determine what type of attack would land best, likely very situationally dependent. Some entities may have resistances, but can never be immune to all damage.

### Attack resolution — the short version
Entity A chooses attack mode, source node [if applicable] and target node(/edge/AoE/whatever we decide), the attack resolves based on the type, often involving dealing damage to the affected node, and for magic attacks may involve hopping (a limited amount of times) along edges with some factor, possibly also affecting/damaging those.
The offensive stats of the casting entity & node are put against the defensive stats of the target entity & node, including rolling for crits and incorporating resistances and application of effects or statuses (poison, bleed, who knows?) and could result in damage or status effects.

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

**Detail doc:** `design/combat_system.md` — preliminary design, numbers not sensible yet. Gaping holes in especially defensive stats

---

## 6. Entity Classes

> *There are 7 classes. Each has a mechanical identity — a distinct playstyle that follows from its stat loadout and class-specific rules.*

| Class | One-line identity | Status |
|-------|------------------|--------|
| Allround | > *...* | ❓ |
| Predator | > *...* | ❓ |
| Bulwark | > *...* | ❓ |
| Ninja | > *...* | ❓ |
| Hive | > *...* | ❓ |
| Halo | > *...* | ❓ |
| Serpent | > *...* | ❓ |

> *For each class, answer: what is the intended win condition? What does the player DO differently when playing this class?*

**Detail doc:** `design/core_classes.md`

---

## 7. Stat System

> *Short summary — what stats exist, what they govern, and how modifiers work. The full design lives in `design/stat_system.md`.*

### Stat categories
> *List the main stat buckets (e.g. combat, mobility, economy). Not every stat — just the categories and what they govern.*

### How modifiers attach
> *Nodes grant modifiers. When a node is allocated/lost, modifiers are added/removed. One sentence on how this feels to a designer adding a new stat.*

**Status:** 🔨 In progress (v2 refactor in progress)

**Detail doc:** `design/stat_system.md`

---

## 8. Progression & Run Structure

> *How does the game progress within a run, and what (if anything) carries between runs?*

### Within a run
> *How does the player get stronger? Skill points, node unlocks, level-ups?*

### Between runs
> *Roguelite unlock tree? Hard reset? Meta-currency?*

### Win / loss conditions
> *What ends a run? What does winning look like?*

**Status:** 📐 Designed

**Detail doc:** `design/metagame.md`

---

## 9. Skill Node Add-ons & Spells

> *Nodes can have add-ons and spells attached. Summarise the concept — what is an add-on vs. a spell, and how does a player interact with them?*

**Status:** 📐 Designed

**Detail docs:** `design/skill_node_addons.md`, `design/spells.md`

---

## 10. Lore & Aesthetic

> *One paragraph on the world. Who are these entities? Why are they fighting over a skill tree? What visual tone and audio mood is the target?*

**Detail doc:** `design/lore.md`

---

## 11. Open Design Questions

> *The "up for grabs" list. Park decisions here until they're resolved, then move the answer into the relevant section above and strike this entry.*

- [ ] > *Question 1 — what is still unresolved?*
- [ ] > *Question 2*
- [ ] > *Question 3*

> **How to use this section:** when you hit a design blocker in Godot, write it here. When a playtest raises a question, write it here. Review this list before each design session.

---

## 12. Roadmap & Feature Status

> *A flat checklist of features — use this as a lightweight backlog.*

### Milestone 0 — Proof of concept
- [ ] > *feature*
- [ ] > *feature*

### Milestone 1 — First playable loop
- [ ] > *feature*
- [ ] > *feature*

### Milestone 2 — All classes in
- [ ] > *feature*
- [ ] > *feature*

### Icebox
> *Things you want eventually but are not blocking anything.*
- > *idea*

---

## Appendix — Design Doc Index

| Doc | What it covers |
|-----|---------------|
| `design/stat_system.md` | v2 stat architecture, `StatDefinition`, modifier operators |
| `design/core_classes.md` | All 7 entity classes, mechanics per class |
| `design/combat_system.md` | R/G/B triangle, per-node health, attack resolution |
| `design/metagame.md` | Run structure, progression, meta-loop |
| `design/skill_node_addons.md` | Node add-on system |
| `design/spells.md` | Spell catalogue |
| `design/lore.md` | Narrative context |
