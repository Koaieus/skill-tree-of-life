extends GutTest

## A blocker owns a node like any entity, so the node's entity-scoped modifiers
## land on the blocker's board — a sparse board that carries only the stats a
## blocker uses. A modifier for a real stat it simply lacks (poison arrows on a
## rock) has nothing to do there and is dropped quietly; an id no StatDef
## declares is still a typo and still warns, on every board.

const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _SMALL_BOARD := preload("res://entity/blocker/blocker_small_board.tres")


func _modifier(stat_id: StringName) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = 1.0
	return m


func test_a_blocker_board_drops_a_known_stat_it_does_not_carry_silently() -> void:
	var board := _SMALL_BOARD.duplicate(true) as EntityStatBoard
	assert_null(board.get_stat(&"poison_arrows_per_reload"), "precondition: the blocker lacks it")
	board.add_modifier(_modifier(&"poison_arrows_per_reload"))
	assert_push_warning_count(0)


func test_a_blocker_board_still_warns_on_an_id_no_stat_declares() -> void:
	var board := _SMALL_BOARD.duplicate(true) as EntityStatBoard
	board.add_modifier(_modifier(&"no_such_stat"))
	assert_push_warning("no stat for id no_such_stat")


func test_a_full_board_still_warns_on_a_known_stat_it_does_not_carry() -> void:
	var board := _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	assert_null(board.get_stat(&"node_spikes"), "precondition: a node-only stat")
	board.add_modifier(_modifier(&"node_spikes"))
	assert_push_warning("no stat for id node_spikes")
