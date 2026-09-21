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


## The wave's landing points, at the beat a wave is released — the camera
## director fits its zoom to these and nothing else (ADR 0027). Distinct from
## [signal MagicBounceCoordinator.wave_started], which a subclass already owns.
signal wave_landing(points: PackedVector2Array)

## The presenter contract, shared with [MeleePreview] (ADR 0027): stage this
## action's wind-up and return the seconds it occupies, which [BattleSystem]
## waits out on a [BeatClock] BEFORE the mutation loop starts. Runs before
## [method play]. The default is no wind-up: returning 0.0 reproduces the
## pre-contract timing exactly.
func begin_windup(_plan: AttackPlan, _tempo: PresentationTempo) -> float:
	return 0.0


## The [Node2D] the camera follows for this action's shot, or null for "frame
## the span once" — the other half of the presenter contract.
func focus_marker() -> Node2D:
	return null
