@tool
class_name CombatCardDefense
extends CombatReadoutCard
## Defense readout: armor + damage floor ([Mitigation]'s `min_damage_taken`).
##
## TODO: R/G/B elemental resists from the design mock have no backing stat
## yet (only physical `armor`/`min_damage_taken` exist on StatBoard today —
## see .claude/rules/stats-system.md "Damage mitigation"). Add resist
## StatDefs + wire Mitigation.apply() per-type before surfacing them here.
##
## Never mode-highlighted (not tied to an AttackMode) — the shell still
## flashes it via [method flash_unmute] on any relevant stat change.

@onready var _armor_row: CombatValueRow = %ArmorRow
@onready var _floor_row: CombatValueRow = %FloorRow

var _board: StatBoard


func bind(board: StatBoard) -> void:
	_board = board
	if board == null:
		return
	if board.armor != null:
		board.armor.value_changed.connect(_refresh)
	if board.min_damage_taken != null:
		board.min_damage_taken.value_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _board == null:
		return
	_armor_row.set_value(float(_board.armor.value) if _board.armor != null else 0.0)
	_floor_row.set_value(float(_board.min_damage_taken.value) if _board.min_damage_taken != null else 0.0)
