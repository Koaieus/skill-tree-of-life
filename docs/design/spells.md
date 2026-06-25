# Spells — Skill Tree of Life

> ⚠️ **MVP-current state lives in [mvp_decisions.md](mvp_decisions.md).** Cast-range scales by INT (new `spell_range` stat), not by source-node degree. Degree-gating uses **allocated-degree** (`EntityNavigator`). "Overqualified casting" bonuses are deferred.

## Overview

Blue (INT/magic) attacks. Each spell defines its own graph-native targeting and propagation — not a generic damage type applied to a graph, but a mechanism *that is* a graph operation. INT scales potency; degree gates casting tier. See `combat_system.md` for the full degree-gating table and damage pipeline.

All power levels, ranges, hop counts, and damage values are placeholders. Nothing here is calibrated — this is an identity catalogue. Power and range balancing come much later.

---

## Propagation Model

Most spells are configured, not coded. A `PropagationConfig` composes three small interfaces plus a handful of scalars; swapping any of them produces a meaningfully different spell. Think of these as the dials we have to turn — virtually every spell in this catalogue is some combination of them.

| Dial | Question it answers | Examples |
|---|---|---|
| **Filter** | Given current node, which neighbours is the spell *allowed* to copy itself to? | enemy-only / unallocated-only / lower-degree-only / highest-armor / toward-Core / away-from-Core |
| **Step (mutate)** | As the spell hops, how does its payload change? | damage ×0.5 per hop (Lightning) / damage ×2 per hop (Crunch, Resonator) / flip filter mid-cast (Ghost Walk: neutral → enemy) |
| **Merger (reducer)** | A node has ≥1 incidents arriving in the same wave. What lands? | SUM (additive, e.g. Resonator weaponising self-loops) / MAX / FIRST / CANCEL_IF_MULTI (the spell fizzles where it overlaps itself) / CANCEL_IF_EVEN |
| `max_hops` | When does propagation stop expanding? | 0 = single-target; ∞ = Flood |
| `max_visits_per_node` | How many times can the *same* node be hit by *this one cast*? | 1 = never-revisit (default, sane); 2+ = node can take multiple waves; ∞ = pure-hop-gated chaos |
| `damage_multiplier_per_hop` | Scalar shortcut for the most common Step mutation | < 1: falloff (Lightning); > 1: rampup (Crunch); 0: detonate-only-at-end (Silencing) |

The unifying insight: **a node hit by N branches in the same BFS wave is one merger event**, not N separate damage instances. Branches still carry their own per-branch payload state (their own visited-trail, their own multiplied damage), but they share a global visit ledger and converge through the merger. Spells that *want* the additive feel ("hit me from 3 directions and you'll regret it") set merger = SUM; spells that want a sanity floor set merger = MAX or FIRST.

Self-loops are first-class under this model: a self-looped node propagating to itself contributes two incidents on its own self in the next wave, which a SUM-merger spell can weaponise (see Resonator below).

---

## Field Schema

| Field | Values |
|---|---|
| **target type** | `node` (default) / `AoE` (rare) / `edge` (rare) |
| **power** | `low` / `medium` / `high` / `ultra` — maps to minimum caster degree required |
| **range** | `short` / `medium` / `long` — euclidean casting distance, caster node to initial target |
| **min range** | only listed when applicable |
| **mechanics/propagation** | what the spell does after hitting its initial target |
| **notes** | design remarks, open questions, interactions |

---

## Catalogue

### Lightning Bolt [proposal: 9/10]

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** damage targeted node, then propagate to all neighbours, `N` hops total, each hop applies (previous damage × 0.5 [or ×0.6-0.8 if .5 is too steep downhill])
- **notes:** no friendly fire; hops and falloff TBD/tweakable.
- review: simple, effective. Just something that hops and re-deals damage

---

### Crunch Bolt [proposal: 8/10]

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** damage targeted node for 1/4 of rated damage, then propagate to all neighbours, `2` (?) hops total, each hop applies (previous damage × 2)
- **notes:** no friendly fire (or?); rampup TBD/tweakable. Inverse of Lightning Bolt — starts small, escalates. Best aimed at nodes deep inside enemy territory rather than the perimeter.
- review: Just some basic hops based damage ramping spell, needs tweaking for range or mana cost to balance


---

### Heavy Bolt

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** damage targeted node, then propagate to adjacent node with **most** armor, `N` (2–3?) hops total
- **notes:** no friendly fire. Climbs the armor gradient — the tank-hunter that ironically seeks out the toughest nodes.
- review: Just some basic spell, whether we let it focus on `armor` specifically or something else like `health`, we can see.

---

### Piercing Bolt

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** damage targeted node, then propagate to adjacent node with **least** armor, `N` (2–3?) hops total
- **notes:** no friendly fire (or?); rampup TBD/tweakable. Seeks out glass nodes — the leaf-hunter.
- review: Just some basic spell, whether we let it focus on `armor` specifically or something else, we can see.

---

### Silencing Bolt [proposal: 10/10, most elegant and mechanically simple]

- **target type:** node
- **power:** high/ultra?
- **range:** medium
- **mechanics/propagation:** deal **no** damage to targeted node, then propagate to adjacent node with highest degree, `N` hops total; after last hop: explodes, dealing 1× damage to the node it is at, half that to adjacents
- **notes:** if this travels to an enemy node with a self-loop (an ideal launching spot for heavy spells due to its high degree), it will do *massive* damage: the hit + 2 outgoing edges as part of the self-loop → these hit the same node, for a total of 3 hits; damage factors tweakable/TBD
- review: a must-have, should be configured to be an absolute self-loop killer, and also likely to find hubs and deal with them; an enemy hub that is also a self-loop.. bingo.. they're already dead just don't know it yet

---

### Flood [proposal: 2/10, fights healing mechanics in game]

- **target type:** node
- **power:** low
- **range:** medium
- **mechanics/propagation:** from the target, propagate simultaneously to every enemy-owned node reachable within `N` graph-hops (BFS, not a walk — fans out everywhere at once). Each node takes the same flat damage regardless of hop distance. No falloff.
- **notes:** low damage per node is the price of hitting everything. Effective against distributed constellations (Hive, thin tendrils) where no single node is a priority target — you can't dodge it by spreading out. Does not propagate across unallocated or own-owned nodes. Whether it can jump Lifelink pod gaps via neutral-node corridors is open — probably yes if the graph has the path, which makes it the intended anti-Hive tool.
- review: would be a free hit on all owned nodes of an enemy entity, which.. yeah not that useful? given that nodes heal up to full at start of their owner's turn, though we might add healing reduction effects later (or make such a spell like this apply it), then this may become useful in grinding down enemy nodes over multiple turns

---

### Degree Drain [proposal: 8/10]

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** single-target, no propagation. Damage = base × **target's owned degree**. A leaf takes near-zero; a degree-5 hub takes the full multiplied hit.
- **notes:** the anti-hub precision tool. The enemy's best casting node is simultaneously the most rewarding Degree Drain target and the node they most need to protect. Pairs thematically with Silencing Bolt (Silencing travels to the highest-degree node; Degree Drain hits it hardest). Explicitly punishes sloppy targeting — firing at a leaf is a wasted action. Open: owned degree or total degree? Owned mirrors the casting-power metric; total mirrors the HP-bracing metric. Different answers produce different spells.
- review: simple point and click should be less rewarding than e.g. landing a perfectly thought out Silencing bolt that finds and nukes a target -- we should make the cast range or damage to balance.

---

### Topple [proposal: 7/10]

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** deal base damage to target. If the target is a **cut vertex** (its removal disconnects the enemy's graph), multiply the damage (×2–3?), and the island check fires *immediately* on the severed component before the enemy can respond.
- **notes:** the graph-reading reward spell. Huge payoff for correctly identifying an articulation point; expensive, poor-value strike against a non–cut-vertex. The immediate island check is the dangerous part — no grace period, no response window. Forces the enemy to think about topology hardening (ring sub-graphs have no cut vertices by definition). Probably wants a visual indicator — should the game highlight cut vertices when Topple is selected, or is partial-information read a design feature?
- review: this sounds finnicky but could be cool, but would need a specialized class because we can't produce this behavior cleanly via the regular knobs for spell propagation/merger

---

### Ghost Walk [proposal: 6/10]

- **target type:** node
- **power:** medium
- **range:** long
- **min range:** short (must cross at least one unallocated node)
- **mechanics/propagation:** the spell travels a path that passes **only through unallocated (neutral) nodes** — cannot enter or cross enemy-held territory as a waypoint. Hits the first enemy-owned node it reaches at the end of the neutral corridor.
- **notes:** a backdoor weapon — bypasses a wall of enemy nodes entirely if there's a neutral corridor behind them. Counter-play: cheap, strategic allocation of a neutral node to close the corridor. Creates a pre-combat map read: "is there a neutral path that opens a back-door angle?" Satisfying when it lands; appropriately unreliable when the enemy has been board-aware. Allocation-boundary mechanic (see `combat_system.md`). Open: if multiple corridors exist, does the caster choose, or does the spell pick the shortest path?
- review:

---

### Aftershock [rating: 7.5/10]

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** deal standard damage to target. If the target is severed (HP → 0), a secondary cast fires from the dead node's former graph position — propagating outward one hop to all of the dead node's former neighbours (ghost cast; the dead node itself is gone, so the secondary hits only its former neighbours, not itself).
- **notes:** rewards aiming at low-HP targets over tanks — the aftershock's value scales with *where* the kill happens. Killing a perimeter leaf nets a weak secondary wave; killing a connector deep inside enemy territory fires the secondary into the interior. Combo-friendly with Topple (Topple to identify the cut vertex, Aftershock to extract the bonus wave on kill). Open: if the secondary also kills a node, does it generate a further aftershock? Probably not by default (recursion hazard), but a build upgrade is imaginable.
- review: can be cool. in-flight spell would need to know if hit killed the node

---

### Detonate [rating: 3/10, maybe if game evolves to use `traps`]

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** deal zero direct damage. Place a **charge** on the target node. The charge is visible (marked). When any damage source hits the charged node next (any type, any origin), it detonates: full base damage to the node + half to all neighbours. Charge expires after `N` turns if undetonated.
- **notes:** a trap spell — the threat of detonation is often more valuable than the detonation itself. Forces the enemy to route around the marked node or eat the explosion. A well-placed charge on a cut vertex or high-traffic bridge endpoint creates serious movement tension. Open: does the charge trigger on thorns returns, recovery penalty ticks, or only active attack hits? Can the caster detonate it on purpose by following up with a melee hit from an adjacent owned node? Both seem valid and potentially fun.
- review: can do this but maybe later, introduces entire new realm of concepts

---

### Supernova

- **target type:** AoE
- **power:** ultra
- **range:** short (euclidean)
- **mechanics/propagation:** all enemy nodes within euclidean radius of the target point take full base damage simultaneously. No graph propagation — pure geometric area blast.
- **notes:** the deliberate exception in the catalogue: euclidean, not topological. Reserved for ultra (degree 5+) to keep it rare and earned. The spell exists so the graph-magic player who has been reading topology all game has one option to just *explode an area* when the graph is too chaotic to parse. Interesting tension: in dense graphs it hits many nodes, but smart dense-graph play (ring topology) means those nodes have more HP and resist. In sparse graphs the nodes are spread far apart and few fall in the radius. Less overpowered than it sounds in both extremes.
- review: possible, if we tweak spells to accept multiple main targets

---

### Leafblower [new]

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** filter = `degree(next) < degree(current)` (strict, so it can't plateau and loop forever) — naturally flows downhill toward leaves. `damage_multiplier_per_hop = ~1.5–2` so the final leaf eats a big payload while intermediate hubs barely register. Merger = MAX (downhill flow rarely converges, but if it does we don't want a freebie).
- **notes:** the inverse of an anti-hub strike — punishes the enemy's *extremities* by blowing through hubs cheaply and detonating on whatever dangling leaf carries an addon or special node. Counter-play: pull leaves inward (raise their degree) or simply don't dangle valuable leaves.
- review: clean configuration-spell, a good early proof that the propagation dials are expressive enough.

---

### Bruiser [new]

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** filter = `highest current HP among unvisited enemy neighbours` (greedy, single onward branch). `damage_multiplier_per_hop ≈ 1.0` (no falloff) but base damage is low — *intentionally* less than the average node's current HP. `max_visits_per_node = 1`. Merger irrelevant (single branch).
- **notes:** the softener. Cannot kill anything by itself — it climbs the HP gradient nicking the toughest nodes for wound-tier damage. Sets up a follow-up spell or melee strike that finishes the now-bracketed targets, and meanwhile keeps damage spread wide so node refill-on-turn-start can't fully undo it. Plays nasty with wound mechanics (see `stats-system.md`'s `wound_heal_per_turn`).
- review: relies on the wound system being meaningful — if combat HP fully heals every turn and there's no wound conversion, this spell does nothing of value. Worth shipping once wound stickiness is tuned.

---

### Resonator [new] — the self-loop exploder

- **target type:** node
- **power:** high/ultra
- **range:** medium
- **mechanics/propagation:** filter = `max-degree neighbour(s)` (ties allowed — fans to *all* max-degree neighbours, not just one). `damage_multiplier_per_hop = 2.0` (doubles every hop). `max_hops = 2–3`. `max_visits_per_node = ∞` (revisits are the whole point). **Merger = SUM.**
- **notes:** the spell built explicitly to abuse the new model. Fire it at an enemy node with a self-loop and the self-loop's two outbound copies converge back on the same node in the next wave — SUM merger collapses them into one double-damage incident, which then doubles again next hop, and so on. Even a single self-loop in the propagation path turns this into a kill spell; landing it *near* (one hop from) a self-loop is already strong. Against a graph with no self-loops it degenerates into "Crunch Bolt aimed at hubs" — still respectable, just not the highlight reel.
- review: the strongest argument for the propagation refactor — a spell that simply *could not exist* under the per-branch-visited model, because there's no merger and no shared visit count to weaponise. Also pushes us to render self-loops legibly so players can spot the kill setups (see open question below).

---

### Homing Decoring [wip need a better name than this pun; tho it has a charm]
#### Live Laugh Loathe: Home Decor(e) but homing in on Core

- **target type:** node
- **mechanics/propagation:** filter = `neighbour closer to enemy Core` (BFS-distance, computed against the enemy's owned subgraph). Greedy single branch.
- **notes:** always steps toward the enemy Core. Pairs with information-gating — needs the caster to know roughly where the Core is.

---

### Corifugal Bolt

- **target type:** node
- **mechanics/propagation:** filter = `neighbour farther from enemy Core`. Opposite of the homing spell — moves *away* from Core. Likely wants a heavier per-hop damage scaling to justify firing it, since "away from the brain" is intrinsically less valuable than "toward the brain".


## Quick Reference

| Spell | Power | Range | Target | Propagation type |
|---|---|---|---|---|
| Lightning Bolt | medium | medium | node | Fork all, 0.5× falloff |
| Crunch Bolt | high | short/med | node | Fork all, 2× rampup |
| Heavy Bolt | high | short | node | Greedy → max armor |
| Piercing Bolt | high | short | node | Greedy → min armor |
| Silencing Bolt | high/ultra | medium | node | Greedy → max degree, delayed AoE |
| Flood | low | medium | node | BFS fan-out (all reachable) |
| Degree Drain | medium | medium | node | None (single-target, damage scales with degree) |
| Topple | high | short | node | None (bonus damage + instant island on cut vertex) |
| Ghost Walk | medium | long | node | Neutral-corridor traversal |
| Aftershock | high | short/med | node | Ghost cast from dead node's position on kill |
| Detonate | medium | medium | node | Trap (detonates on next incoming hit) |
| Supernova | ultra | short | AoE | Euclidean blast |
| Leafblower | medium | medium | node | Strict-downhill degree filter, rampup, payload-on-leaf |
| Bruiser | medium | medium | node | Greedy → max HP, low base damage, single branch |
| Resonator | high/ultra | medium | node | Max-degree fan, ×2 per hop, **SUM merger** (self-loop killer) |
| Homing Decoring | TBD | TBD | node | Greedy → toward enemy Core |
| Corifugal Bolt | TBD | TBD | node | Greedy → away from enemy Core |

---

## Open Questions

1. **Friendly fire policy** — most spells say "no friendly fire" but Crunch Bolt and Piercing Bolt might be interesting with it enabled. Should be decided per-spell, not globally.
2. **Propagation across own nodes** — can enemy-origin spells propagate through player-owned nodes, using them as relays? Undefined. If yes, the path-finding problem becomes shared and the player's topology affects incoming spell routing. If no, owned nodes block at their boundary.
3. **Detonate trigger** — does the charge detonate on thorns returns, recovery penalty ticks, or only active attack hits? Can the caster intentionally trigger it?
4. **Topple + cut vertex UX** — the spell rewards correct cut vertex identification but players need to *see* this. Highlight cut vertices in the targeting UI when Topple is equipped? Or is partial-information read a deliberate design challenge?
5. **Ghost Walk path choice** — if multiple neutral corridors exist, does the caster choose, or does the spell pick the shortest? Caster choice is more skill-expressive; automatic shortest is simpler.
6. **Degree Drain metric** — owned degree (mirrors casting power, same metric as spell tier) or total degree (mirrors HP bracing)? These are meaningfully different spells.
7. **Aftershock recursion** — if the secondary cast also kills a node, does it generate a further aftershock? No by default; build upgrade potentially yes.
8. **Flood + Lifelink gaps** — can Flood cross Hive pod gaps if graph connectivity exists through the field? Probably yes; intended as the anti-Hive tool.
9. **Self-loop interactions** — under the new propagation model self-loops are well-defined (the two outbound copies converge in the merger), but each spell still needs to confirm its intent. Resonator *wants* them; Leafblower's strict-downhill filter naturally bottoms out at them; Bruiser is single-branch so merger never fires. Worth a per-spell line.
10. **Self-loop rendering & procgen seeding** — Resonator only sings if self-loops actually exist on the board and the player can *see* them. Two prerequisites: (a) procgen should seed at least one self-loop per generated graph (rare, premium node — feels like a fang in the topology), (b) the edge renderer needs a self-loop variant (a small arc/halo glyph around the node, not a degenerate straight line). Neither exists today; both are blockers for Resonator shipping playable rather than just configured.
11. **Spell slots / economy** — catalogue assumes unlimited access (any spell if degree allows). Is there a selection mechanic, cooldown, or equip-slot model? TBD.
