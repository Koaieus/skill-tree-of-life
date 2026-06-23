@tool
class_name ContractPhaseBody
extends PhaseBodyBase

## CONTRACT-phase body: shows the deallocation-point budget so the player
## sees how many voluntary deallocations they have left this phase.

const _SegmentedPoolBar := preload("res://ui/segmented_pool_bar/segmented_pool_bar.tscn")

@onready var _bar_slot: Control = $BarSlot
@onready var _hint: Label = $Hint


func rebuild() -> void:
	if not is_node_ready():
		return
	for child in _bar_slot.get_children():
		child.queue_free()
	if entity == null or entity.stat_board == null:
		_hint.text = "Deallocation budget will appear here."
		return
	var bar: SegmentedPoolBar = _SegmentedPoolBar.instantiate()
	_bar_slot.add_child(bar)
	bar.bind_deallocation(entity.stat_board.deallocation_points)
	_hint.text = "Click an owned, non-core node to free SP. Costs one point per click."
