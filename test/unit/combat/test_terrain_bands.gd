extends GutTest

## The band function and the crossing signal (#1794). Every expected value is
## computed from [TerrainRules] and the default node board's `terrain_cap_k`
## (count > t_per_degree × degree primes, cap = k × T) — never a literal.

const _NODE_BOARD := preload("res://skill_node/default_node_board.tres")
const _SIGNAL := "terrain_band_changed"

var _w: TestWorld
var _hub: SkillNode
var _leaf: SkillNode
var _fire: Element
var _ice: Element
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	CombatWorld.reset_live()
	_worlds = []
	_w = TestWorld.create(self)
	_hub = _w.add_node(&"Hub")
	_leaf = _w.add_node(&"Leaf")
	_w.link(_hub, _leaf)
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_ice = ElementRoster.shared().by_id(&"ice")


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()
	CombatWorld.reset_live()


func _primed(e: Element) -> ElementBand:
	return e.bands[0]


func _overflow(e: Element) -> ElementBand:
	return e.bands[e.bands.size() - 1]


func test_band_sweep_over_graph_degree_and_stake() -> void:
	var per_degree := TerrainRules.shared().t_per_degree
	var k_base := int(_NODE_BOARD.terrain_cap_k.base_value)
	assert_true(_overflow(_fire).at_cap, "precondition: the last band sits at the cap")
	var c := _hub.get_combat()
	for d in range(1, 7):
		if d > 1:
			_w.link(_hub, _w.add_node(StringName("L%d" % d)))
		for s in range(1, 6):
			_hub.stake_level = s
			var t := per_degree * d
			var cap := (k_base + s) * t
			var at := "degree %d stake %d" % [d, s]
			assert_eq(c.terrain_threshold(), t, "T = t_per_degree × graph degree, " + at)
			assert_eq(c.terrain_cap(), cap, "cap = (k base + stake) × T, " + at)
			assert_null(Terrain.band_of(_fire, t, t, cap), "≤ T is inert, " + at)
			assert_eq(Terrain.band_of(_fire, t + 1, t, cap), _primed(_fire), "T + 1 primes, " + at)
			assert_eq(Terrain.band_of(_fire, cap, t, cap), _primed(_fire), "the cap is still primed, " + at)
			assert_eq(Terrain.band_of(_fire, cap + 1, t, cap), _overflow(_fire), "cap + 1 overflows, " + at)


func test_a_live_node_crossing_T_emits_once_null_to_primed() -> void:
	var c := _leaf.get_combat()
	var t := c.terrain_threshold()
	watch_signals(_leaf)
	c.add_terrain(_fire, t)
	assert_signal_emit_count(_leaf, _SIGNAL, 0, "up to T is inert")
	c.add_terrain(_fire, 1)
	assert_signal_emit_count(_leaf, _SIGNAL, 1)
	assert_eq(get_signal_parameters(_leaf, _SIGNAL), [_fire, null, _primed(_fire)])


func test_a_write_within_a_band_emits_nothing() -> void:
	var c := _leaf.get_combat()
	var t := c.terrain_threshold()
	assert_gt(c.terrain_cap(), t + 1, "precondition: room inside the primed band")
	c.add_terrain(_fire, t + 1)
	watch_signals(_leaf)
	c.add_terrain(_fire, 1)
	assert_signal_emit_count(_leaf, _SIGNAL, 0)


func test_a_sign_flip_across_both_thresholds_emits_two() -> void:
	var c := _leaf.get_combat()
	var t := c.terrain_threshold()
	c.add_terrain(_fire, t + 1)
	watch_signals(_leaf)
	c.add_terrain(_ice, 2 * (t + 1))
	assert_eq(_leaf.state.terrain_t, -(t + 1))
	assert_signal_emit_count(_leaf, _SIGNAL, 2)
	assert_eq(get_signal_parameters(_leaf, _SIGNAL, 0), [_fire, _primed(_fire), null], "Fire's band leaves first")
	assert_eq(get_signal_parameters(_leaf, _SIGNAL, 1), [_ice, null, _primed(_ice)], "then Ice's arrives")


func test_a_write_back_under_T_emits_primed_to_null() -> void:
	var c := _leaf.get_combat()
	var t := c.terrain_threshold()
	c.add_terrain(_fire, t + 1)
	watch_signals(_leaf)
	c.add_terrain(_fire, -1)
	assert_signal_emit_count(_leaf, _SIGNAL, 1)
	assert_eq(get_signal_parameters(_leaf, _SIGNAL), [_fire, _primed(_fire), null])


func test_a_shadow_write_emits_nothing() -> void:
	var world := CombatWorld.shadow()
	_worlds.append(world)
	var shadow := _leaf.get_combat().snapshot(world)
	watch_signals(_leaf)
	shadow.add_terrain(_fire, _leaf.get_combat().terrain_cap() + 1)
	assert_signal_emit_count(_leaf, _SIGNAL, 0)
