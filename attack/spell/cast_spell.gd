class_name CastSpell
extends RefCounted

## The in-flight carrier for a spell propagating through the graph. One
## instance represents the spell *at one node*; [PropagationStep] mints
## fresh instances for each neighbour it propagates into.
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
## How many BFS wavefronts converged at this node in the wave that produced
## this [CastSpell]. Stamped by [SpellResolver] at the grouping pass
## ([code]spell_resolver.gd[/code] ~L52) — see #352. 1 = single incident
## (no convergence); 2+ = converging branches. Read by
## [ConvergenceCritCondition] to gate the convergence crit. Stamped upstream
## of the reducer so it is set even on the [code]reducer == null[/code]
## "first-wins" short-circuit path.
var incident_count: int = 1
## Per-branch trail of nodes visited so far. Carried for filters that need
## branch-local "have I been here on THIS path" semantics; the canonical
## revisit gate is the global ledger on [PropagationContext.global_visit_count]
## (consulted by [MaxVisitsFilter] and the resolver's cap enforcement).
var visited: Array[SkillNode] = []
## Spell caster — for owner-relative predicates (e.g. only_enemy).
var caster: Entity = null
## The graph the spell walks. Held on the state so propagation strategies
## don't need it threaded as a separate argument.
var graph: Graph = null
## Optional RNG used by stochastic propagation strategies ([RandomPickStep]
## and friends). Threaded through every hop so the same seed reproduces the
## same walk. Null = the propagation falls back to a fresh, time-seeded
## RandomNumberGenerator. Tests inject a seeded one via [method
## SpellResolver.resolve]'s `rng` parameter for determinism.
var rng: RandomNumberGenerator = null
