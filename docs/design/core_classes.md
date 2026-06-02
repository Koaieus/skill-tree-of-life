# Core Classes — Skill Tree of Life

A **core class** defines an entity's fundamental identity — starting stat weights, core aura shape and reach, unique mechanics, and the constellation geometry it is rewarded for maintaining. Two entities with identical allocations but different core classes play completely differently.

Core classes are not locked. A run may present opportunities to shift class identity through late-game loot or Keystone nodes. The starting class sets the trajectory.

---

## Class Entry Schema

| Field | What it captures |
|---|---|
| **Identity** | One-sentence design philosophy. The thing the class *is*. |
| **Playstyle** | How it plays in practice — the turn-by-turn decisions, how it wins. |
| **Stat profile** | Which stats are boosted, nerfed, or unique at creation. |
| **Aura** | What the core radiates, to what range, by which distance metric, with what falloff. |
| **Ideal constellation** | The shape this class is rewarded for building. Determines field theme preference. |
| **Unique mechanic(s)** | Class-specific rules, abilities, or passives not available to other classes. |
| **Synergizes with** | Node types, addons, field themes, or stats this class particularly benefits from. |
| **Counterplay** | How an opponent exploits this class's constraints. |
| **Introduction point** | When in the fractal progression this class appears. Complex classes withheld from early levels. |
| **Balancing notes** | Known tensions, failure modes, things to watch for during development. |

---

## Starter Classes

Always available. Designed to be legible to new players.

---

### The Allround — *The Human*

**Identity:** No specialization, no constraints, a small persistent edge in experience — the reliable generalist.

**Playstyle:** The Allround adapts to whatever the field offers. No mechanic forces a particular constellation shape, no stat constraint narrows attack options. It plays whatever the situation calls for — a melee push here, a ranged nest there, White node economy if the field supports it. Its small XP bonus means it reaches new SP slightly faster than anyone else, compounding quietly over a long run.

**Stat profile:**
| | |
|---|---|
| Boosted | `xp_per_turn +1` (base) — a small something, enough to give it a reason to exist |
| Nerfed | Nothing |
| Unique | None |

**Aura:** Standard linear falloff by hops. No shell, no coil, no inversion. Consistent everywhere.

**Ideal constellation:** Whatever works. Adapts to the field's structure rather than imposing one.

**Unique mechanic(s):** None. The feature is the absence of constraints.

**Synergizes with:** Everything, mediocrely.

**Counterplay:** Outspecialize it. Any focused build beats an Allround at its own specialization. Force the game into a lane.

**Introduction point:** Always available. The default choice.

**Balancing notes:** The XP bonus must be meaningful enough to *choose* the Allround. Too small → invisible. Too large → undercuts other classes' identity through SP advantage.

---

### The Predator — *The Hunter*

**Identity:** Grows by consuming enemies, not by leveling — feeds on adjacency kills.

**Playstyle:** The Predator is XP-starved. Killing from range and never touching the enemy causes stagnation. The compensation is BLITZ — on a killing blow with at least one owned node adjacent to the dying entity, the Predator steals one adjacent enemy-owned node at no SP cost. This is its real growth engine: not leveling, but consuming. Sustained aggression snowballs; retreat starves. It commits where the Ninja retreats.

**Stat profile:**
| | |
|---|---|
| Boosted | `deallocation_points +1` (reshapes quickly toward targets); STR and DEX slightly boosted |
| Nerfed | `xp_per_turn ×0.5` (halved — must BLITZ or stagnate) |
| Unique | BLITZ (class exclusive) |

**Aura:** Short-range, aggressive. Buffs attack output of nodes within ~2 hops of the core.

**Ideal constellation:** Forward-extended toward the nearest enemy. Compact. Core close to the front to keep aura active.

**Unique mechanic(s):**
- **BLITZ (class exclusive):** On a killing blow, if at least one owned node is adjacent to any dying entity node: steal one adjacent enemy-owned node, direct transfer, no SP cost.
- **Core BLITZ bonus:** If the stolen node is the Relic Node (dead core itself): loot resolution triggers immediately with +1 STEAL pick.

**Synergizes with:** Buffer addon (melee burst aligned with close-range play); high-dealloc nodes; R (Red) nodes for STR.

**Counterplay:** Kite it. The Predator requires adjacency — keep it at range. A G-heavy ranged opponent that maintains distance exploits the Predator's need to close the gap. Deny BLITZ by avoiding adjacency at the kill moment.

**Introduction point:** Early game.

**Balancing notes:** BLITZ gives +1 to sp_max (node immediately allocated, current SP unchanged). The Predator may be constellation-rich and SP-poor at high BLITZ counts — more nodes than its level suggests, less flexibility to reshape. Watch for snowball speed in early small-enemy clusters.

---

### The Bulwark — *The Fortress*

**Identity:** An immovable fortress that becomes exponentially harder to damage with each investment in its floor-reduction progression.

**Playstyle:** Plants itself, lets enemies come, becomes progressively more unkillable. Its `damage_floor` starts at 3 (higher than the global default of 1), meaning even heavily-armored nodes always take at minimum 3 chip damage per hit. The class progression reduces the floor: 3→2→1→0→-1→... Each step is more impactful than the last (halving the minimum each time, then eliminating it, then inverting it to healing). The short-range aura creates a fortress zone — nodes near the core fight from a fortified position.

**Stat profile:**
| | |
|---|---|
| Boosted | `armor` (all nodes), `resist_r/g/b` (modest, uniform), `node_health_max` |
| Nerfed | `deallocation_points` (reshapes slowly); `movement_speed` |
| Unique | `damage_floor = 3` starting; floor-reduction perk path |

**Aura:** Short-range, heavily defensive. Within ~3 hops of core: additional armor, additional resist, and a weak offensive aura component so nearby nodes can fend off approaches.

**Ideal constellation:** Compact. Ring-topology preferred (2-edge-connected). Core at center.

**Unique mechanic(s):**
- **`damage_floor` perk path:** Class-specific upgrade series: each perk reduces `damage_floor` by 1. Upgrade costs increase per step. The class's roguelike arc is this journey. Reaching 0 = chip immunity; negative = healing from hits.

**Synergizes with:** Armor Ring and Reinforcement addons; compact ring topologies; W (White) economic nodes in the interior.

**Counterplay:** Economic starvation — deny White node access. B (Blue/magic) graph-traversal may reach inside the fortress if the graph provides a path. At late stages when the floor is negative: disrupting the healing-on-hit requires forcing the Bulwark to stop being hit, which means denying adjacency.

**Introduction point:** Early game.

**Balancing notes:** The hyperbolic floor reduction is intentional — do not flatten it. The inflection at floor=0 (first chip-immune state) is the key calibration point. Watch: what `damage_floor` perk cost makes the floor=0 milestone feel earned but achievable?

---

## Mid-Game Classes

Introduced after the player is comfortable with basic island rules and the stat system.

---

### The Ninja — *The Phantom*

**Identity:** A mobile surgical striker that hits from a tight core cluster and retreats before the enemy can respond.

**Playstyle:** Defined by deallocation budget. More deallocations per turn than any other class means it can reshape dramatically within a single turn — extend a tendril toward a target, strike, retract, all in sequence. Its core aura is intense but very short-ranged, so the core must be close to the fighting nodes for them to hit hard. Low SP cap means it can't sprawl. The class identity lives in the interplay between high DAP, intense close-range aura, and SP constraint.

**Stat profile:**
| | |
|---|---|
| Boosted | `deallocation_points` (high); core aura strength (intense, very short-range) |
| Nerfed | `skill_points_max` (low cap); effectiveness of nodes more than ~6 hops from core |
| Unique | None beyond stat weights + aura shape |

**Aura:** Intense, very short-range (~2 hops). Steep falloff.

**Ideal constellation:** Compact core cluster with temporary tendrils. Between strikes, constellation collapses inward.

**Unique mechanic(s):** None — the class is the aura constraint and the DAP budget. Stats and shape rules are the mechanic.

**Synergizes with:** Buffer addon; high-dealloc nodes; R (Red) STR nodes.

**Counterplay:** Ring topology. A 2-edge-connected constellation with no single bridge is hard to sever with one strike. Force the Ninja to make multiple cuts it can't afford with its low SP cap.

**Introduction point:** Mid-game.

---

### The Hive — *The Swarm*

**Identity:** A distributed organism that sacrifices any individual pod but never exposes the real core.

**Playstyle:** Multiple isolated sub-constellations, each anchored by a Lifelink proxy core. Each pod is small (penalized if any sub-graph exceeds N nodes), productive (White-heavy economic pods common), and expendable. The real core hides deep in one pod — the player ideally never reveals which one. Wins through economic pressure: more pods, more White income, more SP, more territory.

**Stat profile:**
| | |
|---|---|
| Boosted | `sp_per_turn` (more income to support many pods); `xp_per_turn` from White nodes |
| Nerfed | All node stats: steep multiplicative penalty if any sub-graph exceeds N nodes |
| Unique | Starts with 2–3 Lifelink nodes at class creation |

**Aura:** Inverted or absent. A weak per-pod aura (each Lifelink node radiates a small buff to its sub-graph) or none — the pods are self-sufficient.

**Ideal constellation:** Multiple small isolated pods (3–5 nodes), spread across the field.

**Unique mechanic(s):**
- **Lifelink nodes:** Proxy cores sustaining islands indefinitely. Destroying a Lifelink collapses its pod.
- **Pod size penalty:** Multiplicative nerf to all stats in any sub-graph exceeding N nodes.
- **Core concealment:** Which pod contains the real core is not telegraphed by the class itself.

**Synergizes with:** W (White) nodes; Lifelink addon; Constellation Map and Cluster Web field themes.

**Counterplay:** Systematic pod destruction. Each Lifelink is the weakspot — find it, destroy it, lose the pod. Magic (B-type) that hop-propagates may reach hidden Lifelinks if the graph path exists.

**Introduction point:** Late-game only. Requires understanding basic island rules and Lifelink before encountering this in the wild.

**Balancing notes:** Lifeline + Lifelink combo is most dangerous in a Hive context. Do not balance around this interaction until seen in playtesting.

---

### The Halo — *The Ring*

**Identity:** Power lives at exactly the right distance — and touching the ring hurts.

**Playstyle:** The Halo's aura is a shell: it buffs nodes at exactly `shell_distance` hops from the core, and only those nodes. But the shell isn't just a power zone — it's a trap. Shell nodes deal thorns damage back to any melee attacker, creating a burning ring that punishes contact. An opponent who tries to melee through the ring pays for it on every swing. Near-shell nodes (shell_distance ± 1) deal reduced thorns, creating a gradient of danger. The class rewards building a closed ring at the right hop-distance and keeping the core centered. A ring topology at distance N is also 2-edge-connected — the mathematically defensible shape and the ideal shape are the same.

**Stat profile:**
| | |
|---|---|
| Boosted | Nodes at exactly `shell_distance` hops: major buff to all stats (attack, defense, HP), thorns aura |
| Nerfed | Nodes inside and outside the shell: no aura benefit |
| Unique | `shell_distance` (INT stat, default 3); `thorns_base` (INT stat, default 1) |

**Aura:** Shell with thorns gradient.
- Nodes AT `shell_distance`: full aura buff + `thorns = 2 × thorns_base` returned to melee attackers
- Nodes at `shell_distance ± 1`: partial buff + `thorns = 1 × thorns_base`
- Other nodes: no aura

**How thorns works:** When a melee attack hits a node with `thorns > 0`, the attacker's attacking node takes `thorns` flat damage in return — not reduced by the attacker's armor. The ring bites back.

**Anti-ranged reflect:** Not currently provided by the base mechanic. TBD after combat prototypes. The aura may eventually provide deflection or partial reflect against ranged/magic attacks, but this is deferred.

**Ideal constellation:** A ring of nodes at exactly `shell_distance` hops, closing a cycle. Additional outer nodes for SP/economy are fine but unbuffed. Core at the geometric center of the ring.

**Unique mechanic(s):**
- **`shell_distance` stat:** The ring's hop distance from core. Default 3. Can be adjusted by the Shell Shift ability (see below) or by rare node loot.
- **Shell Shift (class ability):** Once per turn, the Halo may raise or lower `shell_distance` by 1. No hard cap in either direction. Expanding the shell requires the constellation to follow — nodes that were at `shell_distance` are now at `shell_distance−1` (near-shell, partial buff only) until new nodes are allocated at the new distance to form the ring. Shrinking the shell pulls near-shell nodes into the ring (temporary power spike) while making outer nodes redundant. The self-limiting factor is node cost: an ever-expanding shell requires ever-more SP to maintain ring coverage, which the entity must provide or the ring thins. There is no mechanical cap — if a player builds a viable strategy around expanding the shell by 1 per turn, that is valid play, not abuse. The resource cost is real; let the system enforce it.
- **`thorns_base` stat:** Scales both the shell thorns (×2) and near-shell thorns (×1). Can be upgraded through loot or class progression. Higher `thorns_base` makes the ring progressively more dangerous to contact.
- **Ring completion bonus (proposed):** If the shell ring forms a complete cycle at exactly shell_distance, an additional bonus applies — to be calibrated. Rewards deliberately closing the loop.
- **Thorns and ring state interaction:** If a snipe shifts nodes OUT of the shell (see ring-shrink math below), those nodes lose their thorns. The ring softens in that area — safe to melee. The Halo must rebuild ring topology to restore coverage.

**Ring-shrink graph math:**

Consider a constellation with:
- `core → A → D → [all other nodes]`
- `core → B → C → D → [all other nodes]`

BFS gives D hop distance 2 via `core→A→D` (shortest path). The alternate path `core→B→C→D` is length 3, so it doesn't affect D's hop distance.

If an attacker snipes A:
- D's only remaining path is `core→B→C→D` = hop 3 (was hop 2)
- Every node beyond D is now +1 hop further from core
- Nodes that were at `shell_distance` are now at `shell_distance+1` — they leave the ring (lose buff AND thorns)
- Nodes that were at `shell_distance−1` are now at `shell_distance` — they enter the ring (gain buff AND thorns)

The ring doesn't shrink in parameter (`shell_distance` is unchanged). The *set of nodes in the ring* shifts: some nodes leave, some enter. A single snipe can simultaneously eject nodes from the ring and pull new ones in, scrambling the Halo's geometry.

**Defense:** The Halo player wants the inner zone (nodes between core and shell) to be *dense* — multiple equal-length paths from core to each ring node. If many paths of equal length exist, sniping one doesn't globally shift hop distances; BFS finds the alternate. Closing cycles in the inner zone is the primary defensive strategy. The outer shell can be sparse (the ring itself); the inner zone should be redundant.

**Synergizes with:** Ring topology (2-edge-connectivity protects against single-snipe distortion); Cluster Web and Web field themes (dense inner zone easier to build); Winch addon (reduces euclidean distance between ring nodes).

**Counterplay:**
- **Topological attack (primary):** Don't attack the shell directly. Attack the inner zone's shortest-path intermediary nodes. Sniping a near-core node that is the unique shortest-path provider for multiple ring nodes pushes those nodes out of the shell, softening or eliminating their thorns. Then melee the softened area safely.
- **Low-edge-density fields:** In sparse graphs, each near-core node is more likely to be the unique intermediary. The snipe effect is more dramatic. Prefer sparse fields or seek to reduce inner edge density before attacking.
- **Ring opening (secondary):** Bleeding Edge or Uprooting to sever one edge of the ring cycle. A broken ring is a path — all nodes on the broken side now have only one route to the core, making them vulnerable to the same topological attack.
- *Note: do NOT melee the shell directly without first softening it. Thorns punish blind melee aggression.*

**Introduction point:** Mid-game.

**Balancing notes:** The thorns mechanic must bite enough to matter without being an instant-kill death trap. Default `thorns = 2` on shell nodes at N=1 is the starting proposal — calibrate so a melee attacker takes meaningful chip over multiple swings, not instant death. Watch: does the topology-snipe counterplay feel accessible to players, or does it require graph theory intuition most players don't have? If the latter, consider a UI hint showing "hop distance changes" on node hover after a snipe.

---

### The Serpent — *The Coil*

**Identity:** Power flows to nodes that are far in hops but near in space — a constellation that winds around itself.

**Playstyle:** The Serpent's aura scales two ways simultaneously: buff proportional to hop-distance from core (further hops = more buff), penalty proportional to euclidean distance from core (further in space = penalized). The sweet spot is many hops away but spatially near. The shape this produces: a tight coil, spiral, or labyrinthine path that winds many times around the core without straying far. The chasm scenario is the class's peak power state: core on one side of a region with few edges crossing, with a winding path crossing the chasm and back, placing premium nodes near the core geometrically while being many hops away topologically. Those nodes receive both the hop-distance buff AND the core's euclidean aura — double-buffed.

**Stat profile:**
| | |
|---|---|
| Boosted | Nodes far in hops from core: buff proportional to `hop_distance_from_core` |
| Nerfed | Nodes far in spatial distance from core: penalty proportional to `euclidean_distance_from_core` |
| Unique | Dual-metric aura (both components active simultaneously) |

**Aura:** Dual-component. Component A: buff scales with hop_distance_from_core (further = stronger). Component B: penalty scales with euclidean_distance_from_core (closer = no penalty; further = penalized). Net: the premium zone is many hops away, spatially close. A node at hop 9 and euclidean 180px: maximum buff + inside core aura range = double-buffed.

**Ideal constellation:** Coil / spiral / labyrinth. The path from core to leaf winds many times without expanding geographically. In dense graphs: zigzag or spiral patterns. Looks nothing like a normal constellation.

**Chasm exploitation:**
When a field has a sparse region (a "chasm" — few or no edges crossing it), the Serpent can cross it via a small bridge and wind back to the core side. The end nodes on the return path are:
- Euclidean-close to the core (across the chasm, but spatially near if the chasm is narrow)
- Many hops from the core (the path wound up, across, and back down)
- Potentially inside the core's euclidean aura range (if the aura radius exceeds the chasm width)

These nodes receive both the Serpent's hop-distance buff and the core's euclidean aura simultaneously. They are the most powerful nodes the class can produce.

**Unique mechanic(s):**
- **Dual-metric aura:** The first class to make hop-distance and euclidean-distance explicitly compete. Players must reason in both metrics simultaneously.
- **Deceptive reach:** "Far" nodes (by hops) are actually nearby geometrically. Opponents who expect distant nodes to be weakly supported are wrong — and their ranged attacks can reach those nodes easily.

**Synergizes with:** Winch addon (reduces euclidean distance, helps avoid penalties); The Web and dense field themes (many edges = many winding paths); B (Blue) magic spells with hop-based propagation (long hop-paths = long spell chains).

**Counterplay:**
- **Bridge targeting (primary):** Do NOT attack N9 (the premium node at the end of the wind). Attack the bridge — the 1–2 nodes that make the chasm crossing possible. Destroying the bridge collapses the entire arm on the far side. The Serpent's premium nodes are a consequence of the bridge existing; remove the bridge, remove the nodes.
- **Why ranged alone doesn't win:** Ranged attacks reach the premium nodes easily (they're spatially close). But hitting the premium nodes doesn't solve the problem while the bridge stands. The bridge itself is typically at a *higher* euclidean distance from the attacker than the premium nodes, making it harder to range-snipe than it looks. Magic (B-type, hop-based) may be more effective at reaching the bridge through the graph.
- **Field theme denial:** Force the Serpent to fight in sparse or radial fields (Constellation Map, Classic Talent Tree) where winding paths are few and chasm opportunities are scarce. In The Web, the Serpent thrives.

**Introduction point:** Mid-to-late game. Requires fluency with both distance metrics simultaneously.

**Balancing notes:** The dual-coefficient aura needs careful calibration. If penalty is too weak, the Serpent is good at everything; if too strong, it's unplayable outside dense fields. The Winch addon interaction needs a cap — otherwise Winch trivializes the euclidean penalty. The chasm scenario is the intended power fantasy, not an exploit.

---

## Design Space — Sketched Classes

Identified directions with clear identity; mechanics not yet fully developed.

---

### The Frontier — *The Pioneer*

**Identity:** Power comes from exposed ends — the more dead-ends in the constellation, the stronger every node.

Mechanics sketch: buff proportional to the count of leaf nodes (nodes with only one connection). Rewards sprawling, tendril-heavy builds that avoid closing cycles. Counterintuitively penalized by ring topology — a ring has no leaf nodes. Attacked strongly by ring-lovers (Bulwark, Halo). Edge case to rule: does the Frontier benefit from nodes that briefly become leaves during island creation before dissolving?

---

### The Harvester — *The Cultivator*

**Identity:** An economic engine that fights through resource dominance rather than military force.

Mechanics sketch: White (W) nodes generate double or triple normal xp_per_turn. Base military stats nerfed. Tech Seed capacity increased. Starve it of White nodes and it's helpless. Protect its economy and it becomes unstoppable over a long run.

---

## Class Comparison Matrix

| Class | Primary resource | Aura type | Ideal shape | Thorns | Complexity |
|---|---|---|---|---|---|
| Allround | XP (bonus) | Linear / hop | Any | No | Low |
| Predator | Enemy nodes (BLITZ) | Close-range attack | Forward-extended | No | Low-Med |
| Bulwark | Armor / floor reduction | Close-range defense | Compact ring | No | Low-Med |
| Ninja | Dealloc budget | Intense, very short | Compact + tendrils | No | Med |
| Hive | Distributed pods | Per-pod (or none) | Many isolated pods | No | High |
| Halo | Shell ring + thorns | Shell at N hops | Ring at shell_dist | **Yes** | Med |
| Serpent | Hop/euclid tension | Dual-metric | Coil / spiral | No | High |
| Frontier | Leaf nodes | Leaf-count scalar | Sprawling tendrils | No | Med |
| Harvester | White XP income | TBD | White-heavy cluster | No | Med |

---

## Open Questions

1. **Class discovery pacing:** Proposed: Allround, Predator, Bulwark always available; Ninja, Hive, Halo, Serpent unlock through run progression or meta-progression.
2. **Class evolution / mutation:** Can a class shift mid-run through Keystone nodes? The Bulwark's floor reduction is one example of in-class progression. Inter-class mutation (e.g. a Ninja that gains a Halo aura shell) needs scoping.
3. **Hive core concealment:** Is there an explicit UI mechanic to conceal which pod holds the real core, or is it inherent to fog of war?
4. **Shell Shift balance:** No hard cap on shell_distance by design. Monitor in playtesting: does the self-limiting resource cost (ring coverage requires nodes at the new distance) actually prevent degenerate strategies, or does it need a soft cap?
5. **Serpent Winch cap:** At what effective euclidean reduction per node does Winch trivialize the penalty? Needs a hard cap.
6. **Frontier + Bleeding Edge:** Does the Frontier benefit from leaf nodes created by islands in the process of dissolving?
7. **Halo anti-ranged / anti-magic reflect:** Thorns is melee-only for now. Does the shell aura eventually provide deflect or reflect against ranged and magic too? TBD after combat prototypes.
8. **Halo UI for ring distortion:** Should the game show hop distance changes in real time as nodes are sniped? Accessibility concern — the topology insight may not be obvious without visual feedback.
9. **`thorns_base` upgrade path:** What's the ceiling? At what value does the shell deter all melee, removing a damage type from viable counterplay?
10. **Relay addon:** Referenced in earlier docs as established. It is not confirmed. TBD pending magic propagation design. See `skill_node_addons.md`.
