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
## The status-stack weight this arrival carries — the stack counterpart of
## [member damage]. Seeded 1.0; [method PropagationConfig.mint] copies it and
## shapes it by [member PropagationConfig.hop_stacks]; a merge carries the MAX
## of its incidents (never the fold, so a SUM spell cannot compound). The
## landing's starting [member HitLanding.stack_scale] is
## [method IncidentReducer.fold_stacks] over the incidents' weights.
var stack_weight: float = 1.0
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

## Spell-specific carried state: one [PayloadState] per
## [member PropagationConfig.extensions] entry, in that order. Read one by id
## with [method extra] — never by index.
var extras: Array[PayloadState] = []


## The seed's blank payload — the one constructor besides [method derived]. The
## resolver stamps one per seed node and fills in the cast's facts.
static func blank() -> CastSpell:
	return CastSpell.new()


## The one copy routine: a fresh payload carrying [param parent]'s universal and
## walk-bookkeeping fields, and nothing else. Each caller then applies only its
## deltas — [method PropagationConfig.mint] advances the walk and stamps the
## pick, [method IncidentReducer._merge_payload_defaults] folds the incidents.
## Arrays are duplicated, never shared with the parent.
##
## Deliberate non-copies, left at their defaults:
## [member damage] is the reducer's (or the mint's progression) to set;
## [member incident_count] and [member arrived_from] are resolver facts stamped
## at the grouping pass.
##
## [member extras] are not copied either: each constructor builds them through
## the extensions (seed, mint, merge), which own their state's evolution.
static func derived(parent: CastSpell) -> CastSpell:
	var next := CastSpell.new()
	next.seed_node = parent.seed_node
	next.current_node = parent.current_node
	next.predecessor = parent.predecessor
	next.source = parent.source
	next.caster = parent.caster
	next.graph = parent.graph
	next.rng = parent.rng
	next.seed_damage = parent.seed_damage
	next.hops_remaining = parent.hops_remaining
	next.hop_index = parent.hop_index
	next.visited = parent.visited.duplicate()
	next.stack_weight = parent.stack_weight
	return next


## The state the extension with [param id] carries on this payload, or null.
func extra(id: StringName) -> PayloadState:
	for s in extras:
		if s.get_id() == id:
			return s
	return null
