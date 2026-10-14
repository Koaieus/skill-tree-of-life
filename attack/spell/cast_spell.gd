class_name CastSpell
extends RefCounted

## The in-flight carrier for a spell propagating through the graph. One
## instance represents the spell *at one node*; a [PropagationSpread] selects
## the neighbours it propagates into and [method PropagationConfig.mint] builds
## the fresh instance for each (#852).
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
## west-by-south. [CycloneSpread] measures its turn ranking against it.
##
## [constant Vector2.ZERO] means "unset" (and also means two fronts cancelled
## head-on) — readers fall back to [member predecessor], then [member source].
var arrival_bearing: Vector2 = Vector2.ZERO
## The fraction of the incoming damage THIS front was minted with — the turn-rank
## coefficient that was actually applied, with any closing bonus already folded
## in ([member CycloneSpread.closing_gain]).
##
## It exists because the number is otherwise destroyed the instant it is used.
## [CycloneSpread] hands it over as [member PropagationPick.share], the mint
## multiplies [member damage] by it and it is gone from the arithmetic;
## [CycloneReducer] then SUMS every incident, and the crit multiplies again
## at landing. So a landed amount cannot be inverted back to "which rank made
## this", and rank is the entire mechanic — the sharp turn circulates, the wide
## turns radiate. The VFX layer has to be TOLD, exactly as it is told
## [member PropagationEvent.verb] rather than inferring it (#704).
##
## Default 1.0 = "full strength, undivided", which is what every spell that does
## not split its damage across a fan means.
var arrival_share: float = 1.0
## The status-stack weight this arrival carries — the stack counterpart of
## [member damage]. Seeded 1.0; [method PropagationConfig.mint] copies it and
## shapes it by [member PropagationConfig.hop_stacks]; a merge carries the MAX
## of its incidents (never the fold, so a SUM spell cannot compound). The
## landing's starting [member HitLanding.stack_scale] is
## [method IncidentReducer.fold_stacks] over the incidents' weights.
var stack_weight: float = 1.0
## Which way the storm turned to get here: +1 clockwise, -1 counter-clockwise,
## 0 for "no handedness" (the seed, and every non-curl spell).
##
## CONSTANT for a whole cast — [method Curl.rank] ranks in one fixed direction
## from the arrival edge at every single node, so this is one value per cast
## rather than a per-arc one. It is carried anyway because the VFX layer has no
## other honest way to reach it: deriving a turn needs the direction the front
## arrived INTO its origin, which lives in a DIFFERENT event, and
## [member PropagationEvent.predecessor] is a node ref with the event-to-event
## link deliberately deferred. With revisits uncapped a node is the target of
## many events, so "which one fed this arc" is genuinely ambiguous downstream.
var turn_sign: float = 0.0
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
var hops_remaining: float = 0.0
## 0 = seed; +1 per propagation step. Drives VFX stagger order and lets
## damage formulas reference "how deep are we?".
var hop_index: int = 0
## How many BFS wavefronts converged at this node in the wave that produced
## this [CastSpell]. Stamped by [SpellResolver] at the grouping pass
## ([code]spell_resolver.gd[/code] ~L52) — see #352. 1 = single incident
## (no convergence); 2+ = converging branches. Read by
## [ConvergenceCondition] to gate the convergence crit. Stamped upstream
## of the reducer so it is set even on the [code]reducer == null[/code]
## "first-wins" short-circuit path.
var incident_count: int = 1
## The predecessor of every incident merged into this landing — an UNORDERED,
## deduped set: ask membership ([code]has[/code]), never position. Stamped by
## [SpellResolver] beside [member incident_count] on every reducer path, so it
## holds all converging fronts even though the reducer keeps one
## [member predecessor]. Empty on the seed. Crit conditions read it ("did any
## front reach here from X"); VFX keeps reading [member predecessor].
var arrived_from: Array[SkillNode] = []
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
## Optional RNG used by stochastic propagation strategies ([RandomPickSpread]
## and friends). Threaded through every hop so the same seed reproduces the
## same walk. Null = the propagation falls back to a fresh, time-seeded
## RandomNumberGenerator. Tests inject a seeded one via [method
## SpellResolver.resolve]'s `rng` parameter for determinism.
var rng: RandomNumberGenerator = null
## The "where I came from" set — the nodes [BacktrackFilter] vetoes this
## front's next step back into. Set at SELECT by the spread on its
## [PropagationPick] and copied onto the child by [method PropagationConfig.mint];
## [CycloneSpread] stamps the parent node on an open hop and an empty set on a
## cycle-closing one, and [CycloneReducer] keeps the closer's (cleared) or the
## surviving lineage's set on a merge. Cyclone itself no longer vetoes on it —
## its curl ranks from the arrival edge and never offers it — so there it is
## telemetry; a spell that pairs [BacktrackFilter] with a spread that stamps it
## gets the veto.
##
## [b]Empty means free[/b]: a front with nothing stamped may step anywhere, so
## the filter is one membership test with no reset special case. Distinct from
## [member predecessor] (the single "the projectile flew from here" reader for
## VFX) and from [member arrived_from] (every merged front's predecessor).
var came_from: Array[SkillNode] = []
## True when the hop that produced this payload landed on a node already in its
## own lineage's [member visited] trail — i.e. it CLOSED a cycle.
##
## Decided at select by [CycloneSpread], read by [CycleCondition]. This is the
## Design A split [ConvergenceCondition] documents: the spread/reducer does
## the math and stamps the fact, the crit condition owns the policy and stays a
## read-only predicate. The trail cannot be re-derived at landing time, because
## a closing mint RESETS [member visited] to just the landed node.
var closed_cycle: bool = false
