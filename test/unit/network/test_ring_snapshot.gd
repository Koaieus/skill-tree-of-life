extends GutTest
## The inner ring across the wire: `ring_spent` rides its own EntitySnapshot
## row, the `ring_points` pool rides the board row. A restored entity is the
## source's ring state, so a cell it already bought stays refused.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _RING_PATH := "res://entity/ring/aspect_ring.tscn"

var _handler := SpendRingCellCommandHandler.new()
var _ring: RingSystem


func before_each() -> void:
	_ring = RingSystem.new()
	_ring.ring_scene = load(_RING_PATH)
	add_child_autofree(_ring)


func _new_graph() -> Graph:
	var graph := TestWorld.create(self).graph
	await get_tree().process_frame
	return graph


func _new_entity(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


## Earn `k` ring points the way play does: by reaching milestone levels.
func _earn(e: Entity, k: int) -> void:
	var target := int(e.level) + k * e.milestone_level_interval
	target -= target % e.milestone_level_interval
	while int(e.level) < target:
		e._on_xp_replenished()


func _try(graph: Graph, e: Entity, cell: StringName) -> bool:
	var ctx := CommandContext.new()
	ctx.graph = graph
	ctx.ring_system = _ring
	var cmd := SpendRingCellCommand.new(e.entity_id, cell)
	if not _handler.validate(cmd, ctx):
		return false
	return _handler.apply(cmd, ctx)


func _transfer(source: Graph, target: Graph) -> void:
	var entity_bytes := EntitySnapshot.encode(source)
	var graph_bytes := GraphSnapshot.encode(source)
	EntitySnapshot.decode(entity_bytes, target)
	GraphSnapshot.decode(graph_bytes, target)
	EntitySnapshot.resolve_graph_refs(entity_bytes, target)


func test_ring_spent_and_the_pool_round_trip() -> void:
	var src_graph := await _new_graph()
	var src := _new_entity(src_graph)
	await get_tree().process_frame
	_earn(src, 2)
	assert_true(_try(src_graph, src, &"BleedingT1"), "sanity: the source buys a T1")
	var dst_graph := await _new_graph()
	var dst := _new_entity(dst_graph)
	await get_tree().process_frame
	_transfer(src_graph, dst_graph)
	assert_eq(dst.ring_spent, src.ring_spent, "ring_spent crossed")
	assert_eq(float(dst.stat_board.ring_points.get_value()),
			float(src.stat_board.ring_points.get_value()), "the pool's cap crossed")
	assert_eq(dst.stat_board.ring_points.available(),
			src.stat_board.ring_points.available(), "the unspent points crossed")
	assert_eq(dst.stat_board.ring_points.available(), 1, "one point left of two")
	assert_eq(float(dst.stat_board.get_stat(&"bleeding_aspect").get_value()),
			float(src.stat_board.get_stat(&"bleeding_aspect").get_value()), "the grant's effect crossed")
	# The board carries the grant, but the core register does not restore it
	# (Entity's restore path, not this row): lootability is lost after a load.
	pending("restored core_modifiers lack the ring grant — outside this fence, see #1651")


func test_a_restored_entity_re_buying_a_spent_cell_is_refused() -> void:
	var src_graph := await _new_graph()
	var src := _new_entity(src_graph)
	await get_tree().process_frame
	_earn(src, 2)
	assert_true(_try(src_graph, src, &"BleedingT1"), "sanity: the source buys a T1")
	var dst_graph := await _new_graph()
	var dst := _new_entity(dst_graph)
	await get_tree().process_frame
	_transfer(src_graph, dst_graph)
	assert_gt(dst.stat_board.ring_points.available(), 0, "funded: a refusal is about the cell, not the pool")
	var reg := dst.core_modifiers.size()
	assert_false(_try(dst_graph, dst, &"BleedingT1"), "a spent cell stays spent after restore")
	assert_eq(dst.core_modifiers.size(), reg, "no side effect")
	assert_true(_try(dst_graph, dst, &"BleedingT2"), "its T2 is adjacent to the restored spend")
