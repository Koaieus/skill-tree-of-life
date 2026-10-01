extends GutTest

## The `aspects` family (#1266): eight `<concept>_aspect` children under one
## parent, on the real default entity board. Ranged reads an aspect as the
## special-arrow mint per reload, entity-flat, off `AmmoType.per_reload_stat_id`.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

const _ASPECTS: Array[StringName] = [
	&"poison_aspect", &"corruption_aspect", &"curse_aspect", &"wither_aspect",
	&"blindness_aspect", &"scout_aspect", &"armor_break_aspect", &"explosive_aspect"]

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _entity() -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = value
	return m


func test_every_aspect_resolves_on_the_default_board() -> void:
	var b := _entity().stat_board
	for id in _ASPECTS:
		assert_not_null(b.get_stat(id), "%s is a typed stat on the default board" % id)
		if b.get_stat(id) != null:
			assert_eq(int(b.get_value(id)), 0, "%s defaults to 0" % id)


func test_plus_one_aspects_raises_every_child_by_one() -> void:
	var b := _entity().stat_board
	var before := {}
	for id in _ASPECTS:
		before[id] = int(b.get_value(id)) if b.get_stat(id) != null else -999
	assert_not_null(b.get_stat(&"aspects"), "the aspects parent is on the default board")
	b.add_modifier(_mod(&"aspects", 1.0))
	for id in _ASPECTS:
		assert_eq(int(b.get_value(id)), int(before[id]) + 1, "+1 aspects reaches %s" % id)


func _poison_minted(grant: float) -> int:
	var e := _entity()
	if grant != 0.0:
		e.stat_board.add_modifier(_mod(&"poison_aspect", grant))
	e.stat_board.action_points.restore_to_full()
	var before := e.stat_board.arrows.stock_of(&"poison")
	e.reload()
	return e.stat_board.arrows.stock_of(&"poison") - before


func test_plus_two_poison_aspect_mints_two_more_poison_arrows_each_reload() -> void:
	assert_eq(_poison_minted(2.0) - _poison_minted(0.0), 2,
			"each reload mints poison_aspect poison arrows")


func test_retired_mint_stats_are_gone() -> void:
	for kind in ["poison", "scout"]:
		var retired := StringName("%s_%s" % [kind, "arrows_per_reload"])
		assert_null(StatRegistry.get_def(retired), "%s retired for %s_aspect" % [retired, kind])
