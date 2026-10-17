extends GutTest
## The NPC ring spender: at turn start, its highest school's sector — T1 on
## both aspects, then T2, then the keystone — among currently buyable cells,
## one command per cell through the same pipeline a player uses.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _RING_PATH := "res://entity/ring/aspect_ring.tscn"

var _graph: Graph
var _applier: CommandApplier
var _enemy: Entity
var _ai: AIController


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	var ring := RingSystem.new()
	ring.ring_scene = load(_RING_PATH)
	add_child_autofree(ring)
	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.ring_system = ring
	add_child_autofree(_applier)
	_enemy = Entity.new()
	_enemy.name = "Enemy"
	_enemy.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.command_applier = _applier
	_enemy.add_child(_ai)
	await get_tree().process_frame


func _earn(k: int) -> void:
	var target := int(_enemy.level) + k * _enemy.milestone_level_interval
	target -= target % _enemy.milestone_level_interval
	while int(_enemy.level) < target:
		_enemy._on_xp_replenished()


func _boost(stat_id: StringName, v: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	_enemy.stat_board.add_modifier(m)


func test_strength_highest_with_three_points_buys_its_sector_in_order() -> void:
	_earn(3)
	assert_eq(_enemy.stat_board.ring_points.available(), 3, "sanity: three points")
	# STRICTLY highest — the STR-first tie-break must not be what passes this.
	_boost(&"strength", 50.0)
	await _ai._spend_ring_points()
	assert_eq(_enemy.ring_spent, [&"BleedingT1", &"WeaknessT1", &"BleedingT2"] as Array[StringName],
			"T1 on both aspects, then the first T2")
	assert_eq(_enemy.stat_board.ring_points.available(), 0, "every point spent")


func test_another_highest_school_buys_its_own_sector() -> void:
	_earn(1)
	_boost(&"dexterity", 50.0)
	await _ai._spend_ring_points()
	assert_eq(_enemy.ring_spent.size(), 1)
	if _enemy.ring_spent.size() == 1:
		var c := _applier.ring_system.table().cell(_enemy.ring_spent[0])
		assert_eq(c.sector.id, &"dexterity", "the dexterity sector")
		assert_eq(c.tier, 1, "a T1 first")


func test_no_points_buys_nothing() -> void:
	await _ai._spend_ring_points()
	assert_true(_enemy.ring_spent.is_empty())


func test_two_points_buy_two_cells_through_a_queued_applier() -> void:
	_earn(2)
	assert_eq(_enemy.stat_board.ring_points.available(), 2, "sanity: two points")
	_boost(&"strength", 50.0)
	# A turn starting mid-drain: the applier is busy, so each spend is QUEUED
	# and only lands when the drain reaches it.
	_applier.is_applying = true
	_ai._spend_ring_points()
	assert_true(_enemy.ring_spent.is_empty(), "queued, not yet applied")
	_applier.is_applying = false
	_applier._drain()
	assert_eq(_enemy.ring_spent, [&"BleedingT1", &"WeaknessT1"] as Array[StringName],
			"both queued spends applied in one turn")
