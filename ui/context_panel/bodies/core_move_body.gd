@tool
class_name CoreMoveBody
extends ContextBodyBase

## Context body shown while the player is composing a core move (#21). Surfaces
## the core slot, the movement-point budget (as a segmented bar), and a hint.
## Active buffs read off the entity + node modifier bins are the natural #39 seam
## — they'll render here once core-class range buffs land, no panel work needed.

const _SegmentedPoolBar := preload("res://ui/segmented_pool_bar/segmented_pool_bar.tscn")

const _MP_TINT := Color(0.3, 0.9, 0.85)

@onready var _name: Label = $CoreName
@onready var _bar_slot: Control = $BarSlot
@onready var _hint: Label = $Hint


func rebuild() -> void:
	if not is_node_ready():
		return
	for child in _bar_slot.get_children():
		child.queue_free()
	if entity == null or entity.stat_board == null:
		_name.text = "Core"
		_hint.text = "Movement budget will appear here."
		return
	var core := entity.core_location
	_name.text = "%s — core" % entity.display_name if core != null else "%s" % entity.display_name
	var mp: PoolStat = entity.stat_board.movement_points
	if mp != null:
		var bar: SegmentedPoolBar = _SegmentedPoolBar.instantiate()
		_bar_slot.add_child(bar)
		bar.bind_simple(mp, _MP_TINT, "Movement")
	_hint.text = "Drag the core, or click an owned node within reach, to move. 1 MP per hop."
