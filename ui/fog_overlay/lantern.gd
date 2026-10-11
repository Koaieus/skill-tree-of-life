class_name Lantern
extends Node2D

## A view-only disc of sight carried by whatever it is a child of: an arrow, a
## spell, a blade vertex. Its [member global_position] is the disc's centre.
##
## A lantern means "you saw it", never "you can target it": [LanternLayer]
## clears fog and lights nodes under it for the local viewer's camp only, and
## nothing logical ([VisionSystem]'s visibility, picking, targeting, the AI)
## ever reads it. See docs/domain/vision-system.md, "Lanterns".
##
## Contract for carriers: instance `lantern.tscn` as a plain child, set
## [member radius] and [member source]. Nothing else to wire.

const GROUP := &"vision_lanterns"

## World-space radius of the disc, in px. Set by whoever attaches the lantern.
@export_range(0.0, 2000.0, 1.0, "suffix:px") var radius: float = 120.0
## Whose lantern this is. Only a source in the local viewer's camp is lit
## ([method VisionSystem.is_viewer_camp]); null is never lit.
var source: Entity = null


func _enter_tree() -> void:
	add_to_group(GROUP)
	# Wake any idle layer: it sleeps while the group is empty.
	get_tree().call_group(LanternLayer.GROUP, &"wake")


func _exit_tree() -> void:
	remove_from_group(GROUP)
