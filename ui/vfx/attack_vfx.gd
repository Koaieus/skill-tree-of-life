class_name AttackVFX
extends Node2D

## Thin dispatcher: hand it a [VFXCoordinator] scene and an action-specific
## payload, it instantiates the coordinator as a world-space child, awaits
## its [method VFXCoordinator.play], then tears it down.
##
## Mounted as a sibling of [NodeHighlightOverlay] under the [Graph] so all
## VFX share world coords with the SkillNodes they target. Stays mounted
## across attacks; per-action coordinators are spawned and freed per call.

const _RANGED_VOLLEY_COORDINATOR: PackedScene = preload(
		"res://ui/vfx/coordinator/arrow_volley_coordinator.tscn")


## Generic dispatch. Future [AttackDef] / [SpellDef] resources will carry the
## coordinator scene reference; for now [BattleSystem] uses the convenience
## wrapper [method play_ranged_volley] which preloads the default ranged scene.
func play(coordinator_scene: PackedScene, payload: Variant) -> void:
	if coordinator_scene == null:
		push_warning("AttackVFX.play: null coordinator_scene")
		return
	var coord := coordinator_scene.instantiate() as VFXCoordinator
	if coord == null:
		push_warning("AttackVFX.play: scene root is not a VFXCoordinator")
		return
	add_child(coord)
	await coord.play(payload)
	coord.queue_free()


## Convenience: default ranged-volley coordinator + [AttackOutcome] payload.
## Preserved so [BattleSystem.launch_attack] keeps its tight call site;
## promote callers to [method play] once attack defs carry a scene reference.
func play_ranged_volley(outcome: AttackOutcome) -> void:
	await play(_RANGED_VOLLEY_COORDINATOR, outcome)
