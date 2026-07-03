@tool
class_name CombatCardMelee
extends CombatReadoutCard
## Melee readout: blade size as [CapacityBlips] diamond pips + blade damage,
## each with a breakpoint sliver read from the STR intrinsic (see
## [AttributeRules] / stats-system.md's intrinsic table — both `blade_size`
## and `blade_damage` step every 10 STR).

const STR_STEP := 10.0

@onready var _size_blips: CapacityBlips = %SizeBlips
@onready var _size_sliver: Label = %SizeSliver
@onready var _damage_row: CombatValueRow = %DamageRow

var _board: StatBoard


func bind(board: StatBoard, owner_entity: Entity = null) -> void:
	_board = board
	_owner_entity = owner_entity
	if board == null:
		return
	if board.blade_size != null:
		board.blade_size.value_changed.connect(_refresh)
	if board.blade_damage != null:
		board.blade_damage.value_changed.connect(_refresh)
	if board.strength != null:
		board.strength.value_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _board == null:
		return
	var str_v: float = float(_board.strength.value) if _board.strength != null else 0.0
	var next_bp: float = (floor(str_v / STR_STEP) + 1.0) * STR_STEP

	var size_v: int = int(_board.blade_size.value) if _board.blade_size != null else 0
	_size_blips.max_count = max(size_v + 2, 5)
	_size_blips.count = size_v
	_size_sliver.text = "+1 / 10 STR - next @%d" % int(next_bp)

	var damage_v: float = float(_board.blade_damage.value) if _board.blade_damage != null else 0.0
	_damage_row.set_value(damage_v)
	_damage_row.set_sliver("+1 / 10 STR - next @%d" % int(next_bp))

	# #119 — node-local override preview. blade_size (the pip display) has no
	# override-highlight visual of its own yet (CapacityBlips is per-pip, not
	# a single value); only the damage row previews for v1.
	var ov: Variant = _local_override_or_null(&"blade_damage", damage_v)
	if ov != null:
		_damage_row.show_override(ov)
	else:
		_damage_row.clear_override()
