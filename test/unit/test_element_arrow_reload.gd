extends GutTest

## Element arrows (#1810): a reload mints `<element>_element` arrows of the
## element's type into its own bin beside the plain pool, and that bin stops at
## `stock_cap_reloads × mint`. Real default entity board; the count is granted
## by a modifier and read back, never assumed from the starter value.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

const _ELEMENTS: Array[StringName] = [&"fire", &"ice", &"lightning"]

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _entity() -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _grant(e: Entity, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = value
	e.stat_board.add_modifier(m)


func _reload(e: Entity) -> void:
	e.stat_board.action_points.restore_to_full()
	e.reload()


func test_a_reload_mints_the_count_into_the_element_bin_up_to_its_cap() -> void:
	for id in _ELEMENTS:
		var t := _ROSTER.by_id(id)
		assert_not_null(t, "%s is a registered ammo type" % id)
		if t == null:
			continue
		var e := _entity()
		var stat_id := t.per_reload_stat_id()
		_grant(e, stat_id, 3.0)
		var n := int(e.stat_board.get_value(stat_id))
		assert_gt(n, 0, "fixture: %s is positive" % stat_id)
		assert_gt(t.stock_cap_reloads, 0, "%s banks a bounded number of reloads" % id)
		var cap := t.stock_cap_reloads * n
		var quiver: Quiver = e.stat_board.arrows
		var plain_before := quiver.current
		var want := 0
		for i in 3:
			_reload(e)
			want = mini(want + n, cap)
			assert_eq(quiver.stock_of(id), want, "%s bin after reload %d" % [id, i + 1])
		assert_eq(quiver.current, plain_before,
				"%s arrows sit beside the plain pool, not in it (no producer mints plain)" % id)


func test_stock_cap_scales_with_the_mint_and_falls_back_to_max_stock() -> void:
	var t := AmmoType.new()
	t.max_stock = 50
	assert_eq(t.stock_cap(4), 50, "0 reloads → the flat max_stock")
	t.stock_cap_reloads = 2
	assert_eq(t.stock_cap(4), 8, "2 reloads of 4")
	assert_eq(t.stock_cap(0), 50, "a zero mint still banks up to max_stock")
