class_name AttackVFX
extends Node2D

## Thin dispatcher: [method mount] instantiates a [VFXCoordinator] scene as a
## world-space child; [method play] awaits its [method VFXCoordinator.play]
## with an action-specific payload, then tears it down.
##
## Mounted as a sibling of [NodeHighlightOverlay] under the [Graph] so all
## VFX share world coords with the SkillNodes they target. Stays mounted
## across attacks; per-action coordinators are spawned and freed per call.

const RANGED_VOLLEY_COORDINATOR: PackedScene = preload(
		"res://ui/vfx/coordinator/arrow_volley_coordinator.tscn")


## Instantiate [param coordinator_scene] as a world-space child and return it,
## or null (with a warning) when the scene is missing or its root is not a
## [VFXCoordinator]. Split from [method play] so [BattleSystem._commit] can
## mount the coordinator AT COMMIT — the presenter contract
## ([method VFXCoordinator.begin_windup] / [method VFXCoordinator.focus_marker])
## has to be answerable before the mutation loop starts, not once it is
## already running.
func mount(coordinator_scene: PackedScene) -> VFXCoordinator:
	if coordinator_scene == null:
		push_warning("AttackVFX.mount: null coordinator_scene")
		return null
	var coord := coordinator_scene.instantiate() as VFXCoordinator
	if coord == null:
		push_warning("AttackVFX.mount: scene root is not a VFXCoordinator")
		return null
	add_child(coord)
	return coord


## Run a mounted coordinator's sequence to the end, then tear it down. Null is
## a no-op, so a caller can hand over whatever [method mount] returned.
func play(coord: VFXCoordinator, payload: Variant) -> void:
	if coord == null:
		return
	# `VFXCoordinator.play` is declared `-> void`, so the analyzer flags this
	# await as redundant — but the concrete coordinators (arrow volley, magic
	# bounce) are runtime coroutines that await their own timelines; skipping
	# this would queue_free the coordinator at its first yield and cancel the
	# whole volley/spell. Keep the await.
	@warning_ignore("redundant_await")
	await coord.play(payload)
	coord.queue_free()


## Convenience: default ranged-volley coordinator + [AttackOutcome] payload,
## mounted and played in one call, for a caller with no wind-up to stage.
func play_ranged_volley(outcome: AttackOutcome) -> void:
	await play(mount(RANGED_VOLLEY_COORDINATOR), outcome)
