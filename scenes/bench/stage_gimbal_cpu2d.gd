extends Node2D
## The [code]cpu2d[/code] stage-gimbal substrate: [code]core_halos.tscn[/code]
## pinned to GIMBAL, adapted onto the three-property contract every row of
## [code]IdleTurnProbe[/code]'s substrate table shares ([code]ring_count[/code],
## [code]tint[/code], [code]base_radius[/code] — the names [code]gimbal_3d.gd[/code]
## already exposes). CoreHalos is not bent: this maps the contract onto what
## it reads (`gimbal_ring_count`, `entity_tint`, `configure(radius)`).

@export_range(1, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		if is_node_ready():
			$CoreHalos.gimbal_ring_count = value

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if is_node_ready():
			$CoreHalos.entity_tint = value

## The SkillNode radius the gimbal sits on; CoreHalos scales outward from it
## by its own `halo_scale` (1.8, the live core_presence.tscn value).
@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		if is_node_ready():
			$CoreHalos.configure(value)


func _ready() -> void:
	$CoreHalos.gimbal_ring_count = ring_count
	$CoreHalos.entity_tint = tint
	$CoreHalos.configure(base_radius)
	# Pass the #802 animation gate unconditionally: a staged gimbal is a
	# measurement, and a fogged one still has to pay its full per-frame cost.
	$CoreHalos.halo_revealed = true
