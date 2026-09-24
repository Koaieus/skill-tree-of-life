extends Node2D
## The [code]live[/code] stage-gimbal substrate (#1108): the shipped entity
## look, `core_gimbal.tscn`, adapted onto the property contract every row of
## [code]IdleTurnProbe[/code]'s substrate table shares. Unlike `viewport3d`
## this goes through the real leaf — its gate, its notifier wiring, its
## footprint constant — so its delta is what a live core costs.
##
## The leaf derives `ring_count` from `owner_level`, so the adapter writes the
## level that yields the requested count; `phase` is written after identity,
## as the probe spreads it (`--gimbal-phase`).

const _LOOK := preload("res://skill_node/visuals/core_gimbal.tscn")

@export_range(2, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		if _leaf != null:
			_leaf.owner_level = _level_for(value)

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if _leaf != null:
			_leaf.entity_tint = value

## The SkillNode radius the look sits on, px — the leaf's own `radius`.
@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		if _leaf != null:
			_leaf.configure(value)

@export var phase: float = 0.0:
	set(value):
		phase = value
		if _leaf != null:
			_leaf.phase = value

var _leaf: SkillNodeVisual


func _ready() -> void:
	_leaf = _LOOK.instantiate()
	_leaf.owner_level = _level_for(ring_count)
	_leaf.entity_tint = tint
	_leaf.configure(base_radius)
	_leaf.phase = phase
	add_child(_leaf)


static func _level_for(rings: int) -> int:
	return (clampi(rings, 2, 5) - 2) * 10
