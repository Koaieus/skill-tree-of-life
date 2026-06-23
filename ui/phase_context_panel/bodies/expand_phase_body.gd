@tool
class_name ExpandPhaseBody
extends PhaseBodyBase

## EXPAND-phase body: skill-point budget split across spendable / used /
## wounded / staked buckets via [SegmentedPoolBar].

const _SegmentedPoolBar := preload("res://ui/segmented_pool_bar/segmented_pool_bar.tscn")

@onready var _bar_slot: Control = $BarSlot
@onready var _hint: Label = $Hint


func rebuild() -> void:
	if not is_node_ready():
		return
	for child in _bar_slot.get_children():
		child.queue_free()
	if entity == null or entity.stat_board == null:
		_hint.text = "Skill-point budget will appear here."
		return
	var bar: SegmentedPoolBar = _SegmentedPoolBar.instantiate()
	_bar_slot.add_child(bar)
	bar.bind_skill_points(entity.stat_board.skill_points)
	_hint.text = "Gold = spendable. Click an in-range node to allocate."
