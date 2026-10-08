---
status: exploring
---

# Spells — Skill Tree of Life

> **The roster is code.** A spell exists if and only if it has a `SpellDef` in [`attack/spell/defs/`](../../attack/spell/defs/). Its `.tres` holds the numbers and the player-facing `description`; the propagation pipeline is [`docs/domain/spell-propagation.md`](../domain/spell-propagation.md); a shipped spell's *why* is a docstring on the filter / spread / reducer that implements it. This doc holds only what is **not built**: the design lens below, the issue-backed spells, and a fenced **idea pool** of spells that do **not** exist. Never cite an idea-pool entry as a game mechanic.
>
> Settled calls on cast range, degree gating, spell cost gates and spell damage are ADRs — see the [ADR index](../adr/index.md).

## How a spell dies

A spell is a **graph automaton**: a local rule applied in synchronous waves. It is a signal-carrying one, closer to Wireworld or a sandpile than to Conway's Life. So *how it stops* is as much part of its identity as how it spreads. There are two independent ways to fizzle:

| Death | Mechanism | Established name | Ours |
|---|---|---|---|
| **Structural** | The wave collides with itself and the merger kills it there | interference: an overcrowding threshold, or a parity rule | `CancelIfMultiReducer` (built, no shipped spell uses it yet); `CANCEL_IF_EVEN` (designed, not built) |
| **Energetic** | The payload shrinks each hop until nothing is left | a subcritical branching process | per-hop falloff (Lightning); Cyclone below its `closing_gain` threshold; a spent `max_hops` budget |

Energetic death has a **criticality** dial. If each hop keeps less than it loses, the wave dies out. If it keeps more, the wave grows. Near the balance point, cascade size depends on the board's structure more than on the numbers. That is why Cyclone demolishes a lone triangle but radiates out of a cluster of them (owner call 2026-09-01).

The two deaths imply different counter-play. You **starve** an energetic spell by breaking the board into short chains that give it nothing to feed on. You **trap** a structural spell by closing loops so it runs into itself. Every catalogue entry should eventually say which death it has. That formalization, and mining the graph-automata field for new spells, is #1201.

---

## Trailblazer

Shipped. Roster: `attack/spell/defs/trail_blazer.tres`. Mechanics: the `ExpressionFilter` clause `from_entity_degree <= 2 and to_entity_degree >= 2` is the stop, the `ScaleDamageEffect` + `JunctionCondition` pair is the slam (see `docs/domain/spell-propagation.md`). Prose below is the retired `TrailBlazerSpread` docstring (#858), kept verbatim.


Single-path "string walker" for The Trail Blazer, a true "Line Killer".

The initial hit lands as normal. From there the walk jumps to every hostile
neighbour and reads its [b]entity degree[/b] — how many of its edges run to
nodes owned by the [b]same[/b] entity ([method LandingContext.entity_degree_of]):

- [b]degree 2[/b] — a link in the chain. Take damage, ramp, keep walking
  (never back into [member CastSpell.visited]).
- [b]degree > 2[/b] — a junction. The walk ends there, slammed.

Neither half of that ending is this class's job any more (#851). The spread
is pure selection: it picks every surviving candidate at full share and
nothing else — the child itself is minted by [method PropagationConfig.mint]
(#852).
  - The [b]slam[/b] is a [ScaleDamageEffect] gated on [JunctionCondition],
    authored before [DamageEffect] on the spell's `on_hit_effects`. It fires
    where the spell LANDS, which is also why a cast seeded directly onto a
    junction is now slammed (it never was before — the old code decided the
    slam at child-mint, so hop 0 had no chance to qualify).
  - The [b]stop[/b] is the filter: `from_entity_degree <= 2` on the spell's
    [ExpressionFilter]. The walk ends at a junction because nothing is
    eligible to leave one, not because a step zeroed a counter.

So it runs down an entire trail for as long as that trail is a chain of
degree-2 nodes. Launched at the tip of a trail, the first jump lands on a
degree-2 node and the walk (and its ramp) triggers immediately.

The read: a tool that punishes long-stretched constellations, and one that
stays effective even on a caster with poor stats — the damage comes from the
defender's own shape, not from the attacker's INT.

[b]Entity degree is the whole point, not an implementation detail.[/b] The
spell is about the defender's territory shape, so an unrelated enemy node
sitting next to the string must not read as a junction and halt the walk.
This walked GRAPH degree until 2026-08-07; the step-level tests missed it
because their fixtures left every node unowned (see the header of
`test/unit/spell/test_trail_blazer_spread.gd`) and the end-to-end ones missed it
because on a fully-owned string the two degrees coincide. Both readers of
that fact now live elsewhere — [JunctionCondition] and the filter clause —
and `docs/domain/degree.md` is the rule.

The per-hop ramp comes from [member PropagationConfig.hop_damage] (typically
[FlatAddProgression] with [code]increment = 2[/code]).

On a pure string the filter + visit cap leave exactly one candidate per hop
(the unvisited next node); when multiple candidates survive, all of them are
picked in parallel — no random pick.

Example — seed A, string B-C-D-E, junction F (degree 3), with the stock
`FlatAddProgression(2)` on the propagation config, a `ScaleDamageEffect`
(MULTIPLY ×2, when = [JunctionCondition]) and a seed of 1
(`spell_damage × power`):
  A=1  B=3  C=5  D=7  E=9  →  F = (9 + 2) × 2 = 22 (slam, then stops).

---

## Designed, issue open — not built

These have an issue; the issue is the design's home, not this doc.

| Idea | Issue |
|---|---|
| Chromatic Cascade — colour-rule variant of Resonator | #355 |
| One cleanse spell per DoT family + a rare cure-all | #969 |
| Mining the graph-automata field for new spells | #1201 |
| Composable / bred spells | #1200 |

---

## Idea pool — NONE of these exist

> ⚠️ **Not in the game, no issue, not scheduled.** Early spitballs kept as inspiration. None has a `SpellDef`; before treating any as real, check `attack/spell/defs/`. Promote one by filing an issue, then move it up to *Designed, issue open*.

### Field schema (the vocabulary the entries below use)

| Field | Values |
|---|---|
| **target type** | `node` (default) / `AoE` (rare) / `edge` (rare) |
| **power** | `low` / `medium` / `high` / `ultra` — maps to minimum caster degree required |
| **range** | `short` / `medium` / `long` — euclidean casting distance, caster node to initial target |
| **min range** | only listed when applicable |
| **mechanics/propagation** | what the spell does after hitting its initial target |
| **notes** | design remarks, open questions, interactions |

---

### Crunch Bolt

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** damage targeted node for 1/4 of rated damage, then propagate to all neighbours, `2` (?) hops total, each hop applies (previous damage × 2)
- **notes:** no friendly fire (or?); rampup TBD/tweakable. Inverse of Lightning Bolt — starts small, escalates. Best aimed at nodes deep inside enemy territory rather than the perimeter.
- review: Just some basic hops based damage ramping spell, needs tweaking for range to balance

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

### Flood

- **target type:** node
- **power:** low
- **range:** medium
- **mechanics/propagation:** from the target, propagate simultaneously to every enemy-owned node reachable within `N` graph-hops (BFS, not a walk — fans out everywhere at once). Each node takes the same flat damage regardless of hop distance. No falloff.
- **notes:** low damage per node is the price of hitting everything. Effective against distributed constellations (Hive, thin tendrils) where no single node is a priority target — you can't dodge it by spreading out. Does not propagate across unallocated or own-owned nodes. Whether it can jump Lifelink pod gaps via neutral-node corridors is open — probably yes if the graph has the path, which makes it the intended anti-Hive tool.
- review: would be a free hit on all owned nodes of an enemy entity, which.. yeah not that useful? given that nodes heal up to full at start of their owner's turn, though we might add healing reduction effects later (or make such a spell like this apply it), then this may become useful in grinding down enemy nodes over multiple turns

---

### Degree Drain

- **target type:** node
- **power:** medium
- **range:** medium
- **mechanics/propagation:** single-target, no propagation. Damage = base × **target's owned degree**. A leaf takes near-zero; a degree-5 hub takes the full multiplied hit.
- **notes:** the anti-hub precision tool. The enemy's best casting node is simultaneously the most rewarding Degree Drain target and the node they most need to protect. Pairs thematically with Reverberator (Reverberator climbs toward the highest-degree node; Degree Drain hits it hardest). Explicitly punishes sloppy targeting — firing at a leaf is a wasted action. Open: owned degree or total degree? Owned mirrors the casting-power metric; total mirrors the HP-bracing metric. Different answers produce different spells.
- review: simple point and click should be less rewarding than e.g. landing a perfectly thought out Reverberator that finds and nukes a target -- we should make the cast range or damage to balance.

---

### Topple

- **target type:** node
- **power:** high
- **range:** short
- **mechanics/propagation:** deal base damage to target. If the target is a **cut vertex** (its removal disconnects the enemy's graph), multiply the damage (×2–3?), and the island check fires *immediately* on the severed component before the enemy can respond.
- **notes:** the graph-reading reward spell. Huge payoff for correctly identifying an articulation point; expensive, poor-value strike against a non–cut-vertex. The immediate island check is the dangerous part — no grace period, no response window. Forces the enemy to think about topology hardening (ring sub-graphs have no cut vertices by definition). Probably wants a visual indicator — should the game highlight cut vertices when Topple is selected, or is partial-information read a design feature?
- review: this sounds finnicky but could be cool, but would need a specialized class because we can't produce this behavior cleanly via the regular knobs for spell propagation/merger

---

### Ghost Walk

- **target type:** node
- **power:** medium
- **range:** long
- **min range:** short (must cross at least one unallocated node)
- **mechanics/propagation:** the spell travels a path that passes **only through unallocated (neutral) nodes** — cannot enter or cross enemy-held territory as a waypoint. Hits the first enemy-owned node it reaches at the end of the neutral corridor.
- **notes:** a backdoor weapon — bypasses a wall of enemy nodes entirely if there's a neutral corridor behind them. Counter-play: cheap, strategic allocation of a neutral node to close the corridor. Creates a pre-combat map read: "is there a neutral path that opens a back-door angle?" Satisfying when it lands; appropriately unreliable when the enemy has been board-aware. Allocation-boundary mechanic (see `combat_system.md`). Open: if multiple corridors exist, does the caster choose, or does the spell pick the shortest path?
- review:

---

### Aftershock

- **target type:** node
- **power:** high
- **range:** short/medium
- **mechanics/propagation:** deal standard damage to target. If the target is severed (HP → 0), a secondary cast fires from the dead node's former graph position — propagating outward one hop to all of the dead node's former neighbours (ghost cast; the dead node itself is gone, so the secondary hits only its former neighbours, not itself).
- **notes:** rewards aiming at low-HP targets over tanks — the aftershock's value scales with *where* the kill happens. Killing a perimeter leaf nets a weak secondary wave; killing a connector deep inside enemy territory fires the secondary into the interior. Combo-friendly with Topple (Topple to identify the cut vertex, Aftershock to extract the bonus wave on kill). Open: if the secondary also kills a node, does it generate a further aftershock? Probably not by default (recursion hazard), but a build upgrade is imaginable.
- review: can be cool. in-flight spell would need to know if hit killed the node

---

### Detonate

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

### Homing Decoring [wip need a better name than this pun; tho it has a charm]
#### Live Laugh Loathe: Home Decor(e) but homing in on Core

- **target type:** node
- **mechanics/propagation:** filter = `neighbour closer to enemy Core` (BFS-distance, computed against the enemy's owned subgraph). Greedy single branch.
- **notes:** always steps toward the enemy Core. Pairs with information-gating — needs the caster to know roughly where the Core is.

---

### Corifugal Bolt

- **target type:** node
- **mechanics/propagation:** filter = `neighbour farther from enemy Core`. Opposite of the homing spell — moves *away* from Core. Likely wants a heavier per-hop damage scaling to justify firing it, since "away from the brain" is intrinsically less valuable than "toward the brain".

---

### Open questions on the idea pool

1. **Friendly fire policy** — most ideas say "no friendly fire"; should be decided per spell, not globally.
2. **Propagation across own nodes** — can enemy-origin spells relay through player-owned nodes? Undefined.
3. **Detonate trigger** — thorns returns, penalty ticks, or only active attack hits? Can the caster trigger it?
4. **Topple + cut-vertex UX** — highlight cut vertices when armed, or is the partial-information read the challenge?
5. **Ghost Walk path choice** — caster picks the corridor, or shortest wins?
6. **Degree Drain metric** — owned degree (casting-power metric) or total degree (bracing metric)? Different spells.
7. **Aftershock recursion** — does a secondary kill chain another aftershock? No by default.
8. **Flood + Lifelink gaps** — can Flood cross pod gaps through the field?

---

## Open questions (spells)

1. **Spell slots / economy** — spells are granted per node and looted as spellbooks (#198, #204); whether there is also an equip-slot or cooldown model is open.
