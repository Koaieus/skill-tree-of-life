@tool
@abstract
class_name VFXCoordinator
extends Node2D

## Plays the visual sequence for one action — an attack, a spell, anything
## that fires once and resolves. One subclass per "shape" of action:
## [RangedVolleyCoordinator] = N projectiles; future melee = phantom-blade
## swing; future magic = projectile hopping along edges.
##
## Coordinators are instantiated as world-space children of [AttackVFX]
## (the dispatcher). The dispatcher awaits [method play], then frees the
## coordinator. Implementations decide WHEN within their sequence to call
## the game-state mutation (e.g. [method SkillNode.take_damage]) —
## typically at the dramatic moment, so reactive VFX (the hit-flash on
## [signal SkillNode.damaged]) syncs automatically.


## Returns when the visual sequence is fully drained — i.e. every spawned
## child (projectile, swing, particle) has finished lingering and the
## dispatcher is safe to [method queue_free] this coordinator without
## visual pop. [param payload] is action-specific; concrete subclasses
## cast and validate.
@abstract func play(payload: Variant) -> void


## The outcome this presenter stages and plays — [BattleSystem] sets it at
## mount, before [method begin_windup], so a wind-up that has to spawn one
## thing per hit (the parked ranged volley, #1042) can read the hits the
## contract's `(plan, tempo)` arguments do not carry. Null on a playground or
## a test that goes straight to [method play].
var outcome: AttackOutcome = null


## The wave's landing points, at the beat the wave is about to LAND — a ranged
## volley's LAST release (#1048), a magic wave's launch (its bolts all leave in
## one loop, so first release is last). The camera director fits its zoom to
## these and nothing else (ADR 0027). Distinct from
## [signal MagicBounceCoordinator.wave_started], which a subclass already owns.
signal wave_landing(points: PackedVector2Array)

## [b]The presenter contract[/b] (ADR 0027), shared with [MeleePreview] — the two
## do not share a base class; the contract is these three members, stated here
## and cross-referenced from there:
##
##   * [method begin_windup] — stage the wind-up, return the seconds it occupies.
##     [BattleSystem._stage_windup] waits that long on a [BeatClock] BEFORE the
##     mutation loop starts, for every mode alike. 0.0 = no wind-up, today's
##     timing exactly.
##   * [method focus_marker] — the [Node2D] the director's shot follows, or
##     null for "nothing to follow yet" (ranged hands its marker over at first
##     release through the signal below, which then OPENS the follow).
##   * [signal focus_marker_changed] — the marker moved onto a new node; the
##     director rebinds its follow without re-tweening.
##
## Stage this action's wind-up and return the seconds it occupies. Runs before
## [method play]. The default is no wind-up: returning 0.0 reproduces the
## pre-contract timing exactly.
func begin_windup(_plan: AttackPlan, _tempo: PresentationTempo) -> float:
	return 0.0


## The [Node2D] the camera follows for this action's shot, or null for "frame
## the span once" — the other half of the presenter contract.
func focus_marker() -> Node2D:
	return null


## The node [method focus_marker] answers with just changed — a presenter that
## spawns its marker after the commit (the melee ghost is rebuilt at wind-up)
## emits this so [CameraDirector] rebinds its open follow onto it.
signal focus_marker_changed(marker: Node2D)
