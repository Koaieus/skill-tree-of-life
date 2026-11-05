@tool
extends Node2D
## Floating disk on voluntary deallocation — a puff marking the spot the node
## vacated, rising, shrinking and whitening as it fades. Spawned by
## [method AllocationVFX.spawn_dealloc_lift]; add it to its host FIRST, then
## [method play]. Inherits its host's z, as it always has.

@export_range(0.05, 2.0, 0.01) var duration: float = 0.30
## Rise distance = disk radius × this.
@export_range(0.0, 6.0, 0.1) var rise_factor: float = 1.5
@export_range(0.0, 2.0, 0.05) var end_scale: float = 0.6


## Starts the lift at [param world_pos]; frees itself when done.
func play(world_pos: Vector2, disk_radius: float, color: Color) -> void:
	global_position = world_pos
	var disk := %Disk
	disk.disk_radius = disk_radius
	disk.disk_color = color
	var tween := create_tween()
	tween.set_parallel(true)
	# Off the root's OWN `position`, not `world_pos` — those agree only for a
	# host at the origin.
	tween.tween_property(self, "position:y", position.y - disk_radius * rise_factor, duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * end_scale, duration)
	# Owner → white (holy puff of smoke) over the first ~70%, so the bloom reads
	# before the fade really kicks in; alpha stays 1 through the shift.
	tween.tween_property(disk, "disk_color", Color.WHITE, duration * 0.7)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
