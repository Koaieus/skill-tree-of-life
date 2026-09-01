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
## The direction of travel INTO [member current_node] — the storm's heading.
##
## Normally just [code]current_node.position - predecessor.position[/code], and
## a spell that never merges could read that instead. It exists because a
## MERGED front has no single predecessor to subtract: several incidents
## arrived from several sides, and the question "which way is this front
## going now" has a better answer than "whichever predecessor the reducer
## happened to keep". [CycloneReducer] writes the damage-weighted mean here,
## so a strong front from the west and a weak one from the south leave heading
## west-by-south. [CycloneStep] measures its turn ranking against it.
##
## [constant Vector2.ZERO] means "unset" (and also means two fronts cancelled
## head-on) — readers fall back to [member predecessor], then [member source].
var arrival_bearing: Vector2 = Vector2.ZERO
## The node the spell was originally cast FROM (caster's launching node).
## Immutable across hops. Distinct from [member predecessor] so seed-vs-hop
## logic stays explicit (a null predecessor unambiguously marks the seed).
var source: SkillNode = null
## Effective damage AT this node — already shaped by every prior hop's
## [HopDamageProgression]. On-hit effects read this; they don't re-scale.
var damage: float = 0.0
## The damage this cast seeded at ([code]spell_damage(source) × power[/code]).
## Immutable across hops — same lifecycle as [member seed_node] — so a
## progression can express itself as a fraction of the seed
## ([ScaledAddProgression]) instead of an absolute. Stamped once by
## [SpellResolver]; INT is never re-read per hop (that would compound it).
var seed_damage: float = 0.0
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
## (consulted by [SpellResolver]'s unconditional cap enforcement).
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
## Nodes this front may NOT travel back into on its next step — the "where I
## came from" set, vetoed by [BacktrackFilter]. An ARRAY and not a single
## [member predecessor] because a convergence merges N fronts that genuinely
## arrived from N directions, and the merged payload has to refuse all of them
## (owner's spec for Cyclone: [i]"it makes the cast-from an array, and the
## step/propagation needs to veto all of them for travel"[/i]).
##
## [b]Empty means free[/b], which is what makes the reset branchless: a step
## that closed a cycle mints its children with an empty set, so the filter is
## one membership test with no "did we just reset?" special case. Populated at
## MINT by [CycloneStep]; merged by [CycloneReducer]. Distinct from
## [member predecessor], which stays the single canonical "the projectile flew
## from here" reader for VFX.
var came_from: Array[SkillNode] = []
## True when the hop that produced this payload landed on a node already in its
## own lineage's [member visited] trail — i.e. it CLOSED a cycle.
##
## Stamped at mint by [CycloneStep], read by [CycleCritCondition]. This is the
## Design A split [ConvergenceCritCondition] documents: the step/reducer does
## the math and stamps the fact, the crit condition owns the policy and stays a
## read-only predicate. The trail cannot be re-derived at landing time, because
## a closing mint RESETS [member visited] to just the landed node.
var closed_cycle: bool = false
