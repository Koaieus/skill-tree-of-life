class_name CastSpell
extends RefCounted

## The in-flight carrier for a spell propagating through the graph. One
## instance represents the spell *at one node*; [method SpellPropagation.next_hops]
## mints fresh instances for each neighbour it propagates into.
##
## Each instance becomes one entry in the resolved outcome chain: trace
## [member predecessor] → [member current_node] to draw the spell's path,
## sort by [member hop_index] for VFX staggering.

## The original target the cast seeded at. Immutable across hops.
## Field is [code]seed_node[/code] (not [code]seed[/code]) to avoid shadowing
## the GDScript built-in [code]seed()[/code] PRNG function.
var seed_node: SkillNode = null
## Where the in-flight spell currently lives.
var current_node: SkillNode = null
## Graph predecessor in the walk. Null at the seed. For visual chains the
## VFX layer falls back to [member source] when this is null (see
## [DamageEffect]) so the seed projectile flies from the cast-from node.
var predecessor: SkillNode = null
## The node the spell was originally cast FROM (caster's launching node).
## Immutable across hops. Distinct from [member predecessor] so seed-vs-hop
## logic stays explicit (a null predecessor unambiguously marks the seed).
var source: SkillNode = null
## Effective damage AT this node — already scaled by all prior per-hop
## multipliers. On-hit effects read this; they don't re-scale.
var damage: float = 0.0
## Recursion budget left. 0 means no further propagation from here.
var hops_remaining: int = 0
## 0 = seed; +1 per propagation step. Drives VFX stagger order and lets
## damage formulas reference "how deep are we?".
var hop_index: int = 0
## Nodes already hit on this cast (including [member current_node] itself).
## Propagation strategies check this to avoid re-entering — unless their
## [member SpellPropagation.revisit_visited] flag says otherwise.
var visited: Array[SkillNode] = []
## Spell caster — for owner-relative predicates (e.g. only_enemy).
var caster: Entity = null
## The graph the spell walks. Held on the state so propagation strategies
## don't need it threaded as a separate argument.
var graph: Graph = null
