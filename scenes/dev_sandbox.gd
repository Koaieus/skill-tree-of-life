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


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	$UI.visible = true


func _setup_level() -> void:
	await super()
	if player == null:
		return
	var m := StatModifier.new()
	m.stat_id = &"blade_size"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = _SANDBOX_BLADE_SIZE_BONUS
	player.grant_core_modifier(m)
