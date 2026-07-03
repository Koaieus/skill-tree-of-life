@tool
class_name CombatCardRanged
extends CombatReadoutCard
## Ranged readout: damage/leaf + firing range (px).
##
## TODO: promote to formula-driven StatDef (stats-system.md direction) —
## `RangedDamageFormula.compute()` (attack/formulas/ranged_damage.gd) is
## floor(DEX/10)+1 and isn't a board stat yet, so it's re-derived here
## rather than read off a StatDef. Once it is, drop this duplication.

@onready var _damage_row: CombatValueRow = %DamageRow
@onready var _range_row: CombatValueRow = %RangeRow

var _board: StatBoard


func bind(board: StatBoard, owner_entity: Entity = null) -> void:
	_board = board
	_owner_entity = owner_entity
	if board == null:
		return
	if board.dexterity != null:
		board.dexterity.value_changed.connect(_refresh)
	if board.range != null:
		board.range.value_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _board == null:
		return
	var dex: float = float(_board.dexterity.value) if _board.dexterity != null else 0.0
	_damage_row.set_value(floor(dex / 10.0) + 1.0)

	var range_v: float = float(_board.range.value) if _board.range != null else 0.0
	_range_row.set_value(range_v, " px")

	# #119 — node-local override preview. `range` is leaf-localized per
	# stats-system.md; damage has no backing StatDef (see class doc TODO),
	# so only the range row can preview.
	var ov: Variant = _local_override_or_null(&"range", range_v)
	if ov != null:
		_range_row.show_override(ov)
	else:
		_range_row.clear_override()
