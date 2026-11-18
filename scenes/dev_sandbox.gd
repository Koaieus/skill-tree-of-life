extends GameRoot

## Hand-authored sandbox. Inherits GameRoot defaults — the `%Player` node
## baked into dev_sandbox.tscn is picked up by GameRoot._setup_level.
##
## Both entities carry `default_entity_board.tres` (Entity._ready duplicates
## it), never an inline copy: a copy silently loses every stat added after it
## was pasted — the inline one had rotted to 16 missing fields, no Quiver among
## them, so Reload sat disabled. Sandbox-only tuning goes on as core modifiers
## here, on top of the live board.

## The sandbox player swings a wide blade so melee is worth poking at.
const _SANDBOX_BLADE_SIZE_BONUS := 4.0

## The counts the sandbox Player starts higher in, for instant testing of the
## forge and the element arrows: the three element counts and Catalyst's.
const _STARTER_COUNTS: Array[StringName] = [
		&"fire_element", &"ice_element", &"lightning_element", &"catalyst_aspect"]

## Added to each starter count on the sandbox Player only, on top of the count's
## `StatDef.default_value` (1 + 2 = 3 each). Tentative, easy to change.
@export_range(0, 20, 1) var starter_count_bonus: float = 2.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	$UI.visible = true


func _setup_level() -> void:
	await super()
	if player == null:
		return
	_grant(&"blade_size", _SANDBOX_BLADE_SIZE_BONUS)
	for id in _STARTER_COUNTS:
		_grant(id, starter_count_bonus)


func _grant(stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	player.grant_core_modifier(m)
