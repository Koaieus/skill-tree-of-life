extends GutTest

## `dev_sandbox.tscn` runs on `default_entity_board.tres` plus sandbox-only
## modifiers — never an inline board copy, which silently loses every stat
## added after it was pasted (godot-scene-authoring rule). The copy that
## motivated this had rotted to 16 missing fields, `arrows` among them, so
## `Entity.can_reload()` was false and the Quiver tray's Reload sat disabled
## with 2 AP in hand.

const _SANDBOX := preload("res://scenes/dev_sandbox.tscn")

var _root: GameRoot


func before_each() -> void:
	_root = _SANDBOX.instantiate()
	add_child_autofree(_root)
	for _i in 60:
		await wait_physics_frames(1)
		if _root.turn_manager.current_entity != null:
			break
	assert_eq(_root.turn_manager.current_entity, _root.player, "fixture: player holds the first turn")


func test_player_carries_every_board_field() -> void:
	var board := _root.player.stat_board
	var missing: Array[String] = []
	for prop in board.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.type == TYPE_OBJECT and board.get(prop.name) == null:
			missing.append(prop.name)
	assert_eq(missing, [], "null typed fields on the sandbox player's board")


func test_player_can_reload_with_ap_in_hand() -> void:
	assert_not_null(_root.player.stat_board.arrows, "the Quiver")
	assert_true(_root.player.can_reload())


func test_sandbox_blade_size_bonus_sits_on_top_of_the_live_board() -> void:
	var default_board: EntityStatBoard = preload("res://entity/default_entity_board.tres")
	var base := default_board.blade_size.base_value
	assert_eq(_root.player.stat_board.blade_size.get_value(), base + 4.0 + _str_blade_bonus(_root.player),
			"default base + the sandbox's +4, not a forked base_value")


func test_entities_never_share_a_stat_object() -> void:
	var enemy: Entity = _root.graph.entities_container.get_node("Enemy")
	assert_ne(_root.player.stat_board, enemy.stat_board)
	assert_ne(_root.player.stat_board.initiative, enemy.stat_board.initiative,
			"a shared initiative pool double-connects TurnManager's forecast")


## `+1 blade_size per 40 STR`, the intrinsic the default board applies.
func _str_blade_bonus(e: Entity) -> float:
	return floorf(e.stat_board.strength.get_value() / 40.0)
