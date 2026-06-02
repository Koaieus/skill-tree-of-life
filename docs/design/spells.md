# Spells — Skill Tree of Life

## Overview

Blue (INT/magic) attacks. Each spell defines its own graph-native targeting and propagation — not a generic damage type applied to a graph, but a mechanism *that is* a graph operation. INT scales potency; degree gates casting tier. See `combat_system.md` for the full degree-gating table and damage pipeline.

All power levels, ranges, hop counts, and damage values are placeholders. Nothing here is calibrated — this is an identity catalogue. Power and range balancing come much later.

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

### Lightning Bolt

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** damage targeted node, then propagate to all neighbours, `N` hops total, each hop applies (previous damage × 0.5)
- **notes:** no friendly fire; hops and falloff TBD/tweakable

---

### Crunch Bolt

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** damage targeted node for 1/4 of rated damage, then propagate to all neighbours, `2` (?) hops total, each hop applies (previous damage × 2)
- **notes:** no friendly fire (or?); rampup TBD/tweakable. Inverse of Lightning Bolt — starts small, escalates. Best aimed at nodes deep inside enemy territory rather than the perimeter.

---

### Heavy Bolt

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** damage targeted node, then propagate to adjacent node with **most** armor, `N` (2–3?) hops total
- **notes:** no friendly fire. Climbs the armor gradient — the tank-hunter that ironically seeks out the toughest nodes.

---

### Piercing Bolt

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** damage targeted node, then propagate to adjacent node with **least** armor, `N` (2–3?) hops total
- **notes:** no friendly fire (or?); rampup TBD/tweakable. Seeks out glass nodes — the leaf-hunter.

---

### Silencing Bolt

- **target type:** node
- **power:** high/ultra?
- **range:** medium
- **mechanics/propagation:** deal **no** damage to targeted node, then propagate to adjacent node with highest degree, `N` hops total; after last hop: explodes, dealing 1× damage to the node it is at, half that to adjacents
- **notes:** if this travels to an enemy node with a self-loop (an ideal launching spot for heavy spells due to its high degree), it will do *massive* damage: the hit + 2 outgoing edges as part of the self-loop → these hit the same node, for a total of 3 hits; damage factors tweakable/TBD

---

### Flood

- **target type:** node
- **power:** low
- **range:** medium
- **mechanics/propagation:** from the target, propagate simultaneously to every enemy-owned node reachable within `N` graph-hops (BFS, not a walk — fans out everywhere at once). Each node takes the same flat damage regardless of hop distance. No falloff.
- **notes:** low damage per node is the price of hitting everything. Effective against distributed constellations (Hive, thin tendrils) where no single node is a priority target — you can't dodge it by spreading out. Does not propagate across unallocated or own-owned nodes. Whether it can jump Lifelink pod gaps via neutral-node corridors is open — probably yes if the graph has the path, which makes it the intended anti-Hive tool.

---

### Degree Drain

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** single-target, no propagation. Damage = base × **target's owned degree**. A leaf takes near-zero; a degree-5 hub takes the full multiplied hit.
- **notes:** the anti-hub precision tool. The enemy's best casting node is simultaneously the most rewarding Degree Drain target and the node they most need to protect. Pairs thematically with Silencing Bolt (Silencing travels to the highest-degree node; Degree Drain hits it hardest). Explicitly punishes sloppy targeting — firing at a leaf is a wasted action. Open: owned degree or total degree? Owned mirrors the casting-power metric; total mirrors the HP-bracing metric. Different answers produce different spells.

---

### Topple

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** deal base damage to target. If the target is a **cut vertex** (its removal disconnects the enemy's graph), multiply the damage (×2–3?), and the island check fires *immediately* on the severed component before the enemy can respond.
- **notes:** the graph-reading reward spell. Huge payoff for correctly identifying an articulation point; expensive, poor-value strike against a non–cut-vertex. The immediate island check is the dangerous part — no grace period, no response window. Forces the enemy to think about topology hardening (ring sub-graphs have no cut vertices by definition). Probably wants a visual indicator — should the game highlight cut vertices when Topple is selected, or is partial-information read a design feature?

---

### Ghost Walk

- **target type:** node
- **power:** medium
- **range:** long
- **min range:** short (must cross at least one unallocated node)
- **mechanics/propagation:** the spell travels a path that passes **only through unallocated (neutral) nodes** — cannot enter or cross enemy-held territory as a waypoint. Hits the first enemy-owned node it reaches at the end of the neutral corridor.
- **notes:** a backdoor weapon — bypasses a wall of enemy nodes entirely if there's a neutral corridor behind them. Counter-play: cheap, strategic allocation of a neutral node to close the corridor. Creates a pre-combat map read: "is there a neutral path that opens a back-door angle?" Satisfying when it lands; appropriately unreliable when the enemy has been board-aware. Allocation-boundary mechanic (see `combat_system.md`). Open: if multiple corridors exist, does the caster choose, or does the spell pick the shortest path?

---

### Aftershock

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** deal standard damage to target. If the target is severed (HP → 0), a secondary cast fires from the dead node's former graph position — propagating outward one hop to all of the dead node's former neighbours (ghost cast; the dead node itself is gone, so the secondary hits only its former neighbours, not itself).
- **notes:** rewards aiming at low-HP targets over tanks — the aftershock's value scales with *where* the kill happens. Killing a perimeter leaf nets a weak secondary wave; killing a connector deep inside enemy territory fires the secondary into the interior. Combo-friendly with Topple (Topple to identify the cut vertex, Aftershock to extract the bonus wave on kill). Open: if the secondary also kills a node, does it generate a further aftershock? Probably not by default (recursion hazard), but a build upgrade is imaginable.

---

### Detonate

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** deal zero direct damage. Place a **charge** on the target node. The charge is visible (marked). When any damage source hits the charged node next (any type, any origin), it detonates: full base damage to the node + half to all neighbours. Charge expires after `N` turns if undetonated.
- **notes:** a trap spell — the threat of detonation is often more valuable than the detonation itself. Forces the enemy to route around the marked node or eat the explosion. A well-placed charge on a cut vertex or high-traffic bridge endpoint creates serious movement tension. Open: does the charge trigger on thorns returns, recovery penalty ticks, or only active attack hits? Can the caster detonate it on purpose by following up with a melee hit from an adjacent owned node? Both seem valid and potentially fun.

---

### Supernova

- **target type:** AoE
- **power:** ultra
- **range:** short (euclidean)
- **mechanics/propagation:** all enemy nodes within euclidean radius of the target point take full base damage simultaneously. No graph propagation — pure geometric area blast.
- **notes:** the deliberate exception in the catalogue: euclidean, not topological. Reserved for ultra (degree 5+) to keep it rare and earned. The spell exists so the graph-magic player who has been reading topology all game has one option to just *explode an area* when the graph is too chaotic to parse. Interesting tension: in dense graphs it hits many nodes, but smart dense-graph play (ring topology) means those nodes have more HP and resist. In sparse graphs the nodes are spread far apart and few fall in the radius. Less overpowered than it sounds in both extremes.

---

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
9. **Self-loop interactions** — each propagating spell needs to define what happens at a self-looped node (the two loop returns; see `combat_system.md`). Do both returns each consume a hop? Can a hop-limited spell bottom out inside the self-loop? Define per spell.
10. **Spell slots / economy** — catalogue assumes unlimited access (any spell if degree allows). Is there a selection mechanic, cooldown, or equip-slot model? TBD.
