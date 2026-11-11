extends GutTest

## #1795 — the world turn's terrain pass ([method CombatWorld.flow_temperature]):
## Heat/Cold diffusion on the signed t (floored Metropolis per edge, one
## snapshot a step), then one decay sweep of t and Charge at each node's band
## rate, all committed through [TerrainSettle]. Fixture, all unallocated: the
## leaf pairs A-B, C-D, E-F; the chain M-N-O; the blob G-H, H-I, I-J, H-J,
## J-K, G-L.

const _EDGES := [[&"A", &"B"], [&"C", &"D"], [&"E", &"F"], [&"M", &"N"], [&"N", &"O"],
		[&"G", &"H"], [&"H", &"I"], [&"I", &"J"], [&"H", &"J"], [&"J", &"K"], [&"G", &"L"]]
const _BLOB := [&"G", &"H", &"I", &"J", &"K", &"L"]
## The blob's opening terrain: [id, t, charge].
const _BLOB_START := [[&"G", 9, 0], [&"H", -1, 0], [&"I", 0, 3], [&"J", 0, 0],
		[&"K", 4, 1], [&"L", -7, 0]]

var _w: TestWorld
var _graph: Graph
var _n: Dictionary = {}  # StringName -> SkillNode
var _fire: Element
var _ice: Element
var _lightning: Element
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	CombatWorld.reset_live()
	_worlds = []
	_w = TestWorld.create(self)
	_graph = _w.graph
	_n = {}
	for e: Array in _EDGES:
		for id: StringName in e:
			if not _n.has(id):
				_n[id] = _w.add_node(id)
		_w.link(_n[e[0]], _n[e[1]])
	await get_tree().process_frame
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_ice = roster.by_id(&"ice")
	_lightning = roster.by_id(&"lightning")


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()
	CombatWorld.reset_live()


func _c(id: StringName) -> NodeCombat:
	return (_n[id] as SkillNode).get_combat()


func _put(id: StringName, t: int, charge: int = 0) -> void:
	var c := _c(id)
	c.add_terrain(_fire, t - c.terrain_t())
	c.add_terrain(_lightning, charge - c.charge())


func _ints(ids: Array) -> Array:
	var out := []
	for id: StringName in ids:
		out.append([_c(id).terrain_t(), _c(id).charge()])
	return out


func _fill_blob(reverse: bool) -> void:
	var rows := _BLOB_START.duplicate()
	if reverse:
		rows.reverse()
	for r: Array in rows:
		_put(r[0], r[1], r[2])


func _clear_blob() -> void:
	for id: StringName in _BLOB:
		_put(id, 0, 0)


func test_a_diffusion_step_conserves_the_sum_and_never_raises_the_square_sum() -> void:
	_fill_blob(false)
	var before := _ints(_BLOB)
	var sum := 0
	var sq := 0
	for id: StringName in _BLOB:
		sum += _c(id).terrain_t()
		sq += _c(id).terrain_t() * _c(id).terrain_t()
	for step in 4:
		CombatWorld.live().diffuse_temperature()
		var s := 0
		var s2 := 0
		for id: StringName in _BLOB:
			s += _c(id).terrain_t()
			s2 += _c(id).terrain_t() * _c(id).terrain_t()
		assert_eq(s, sum, "step %d conserves Σt" % step)
		assert_true(s2 <= sq, "step %d never raises Σt² (%d → %d)" % [step, sq, s2])
		sq = s2
	assert_ne(_ints(_BLOB), before, "sanity: heat moved")


func test_a_gap_at_or_below_the_larger_degree_moves_nothing() -> void:
	_put(&"N", 2)
	_put(&"A", 1)
	CombatWorld.live().diffuse_temperature()
	assert_eq(_ints([&"M", &"N", &"O"]), [[0, 0], [2, 0], [0, 0]], "gap 2 against degree 2: ⌊2 / 3⌋ = 0")
	assert_eq(_ints([&"A", &"B"]), [[1, 0], [0, 0]], "gap 1 against degree 1: ⌊1 / 2⌋ = 0")


func test_plus_six_beside_minus_six_on_two_leaves_ends_at_zero() -> void:
	_put(&"A", 6)
	_put(&"B", -6)
	CombatWorld.live().diffuse_temperature()
	assert_eq(_ints([&"A", &"B"]), [[0, 0], [0, 0]], "gap 12 over 1 + 1 moves 6")


func test_the_decay_sweep_below_the_first_band_reads_the_element_rate() -> void:
	_put(&"A", 2)
	_put(&"B", 2)
	_put(&"C", -2)
	_put(&"D", -2)
	_put(&"E", 0, 2)
	assert_null(_c(&"A").terrain_band(_fire), "precondition: 2 is at or below T, no band")
	assert_null(_c(&"C").terrain_band(_ice))
	assert_null(_c(&"E").terrain_band(_lightning))
	CombatWorld.live().flow_temperature(1)
	var hot := 2 - _fire.decay_per_world_turn
	var cold := -2 + _ice.decay_per_world_turn
	assert_eq(_ints([&"A", &"B"]), [[hot, 0], [hot, 0]], "Heat decays by Fire's own rate")
	assert_eq(_ints([&"C", &"D"]), [[cold, 0], [cold, 0]], "Cold by Ice's")
	assert_eq(_ints([&"E"]), [[0, 2 - _lightning.decay_per_world_turn]], "Charge by Lightning's")
	assert_eq(_ints([&"F"]), [[0, 0]], "Charge never flows to a neighbour")


func test_the_decay_sweep_reads_each_band_rate_before_it_writes() -> void:
	var a := _c(&"A")
	var c := _c(&"C")
	var t := a.terrain_threshold()
	var cap := c.terrain_cap()
	_put(&"A", t + 1)
	_put(&"B", t + 1)
	_put(&"C", cap + 1)
	_put(&"D", cap + 1)
	var primed := a.terrain_band(_fire)
	var over := c.terrain_band(_fire)
	assert_not_null(primed, "precondition: T + 1 primes")
	assert_not_null(over, "precondition: cap + 1 overflows")
	if primed == null or over == null:
		return
	assert_false(primed.at_cap)
	assert_true(over.at_cap)
	var r_p := primed.decay_per_world_turn
	var r_o := over.decay_per_world_turn
	CombatWorld.live().flow_temperature(1)
	assert_eq(_ints([&"A", &"B"]), [[t + 1 - r_p, 0], [t + 1 - r_p, 0]], "the primed band's rate")
	assert_eq(_ints([&"C", &"D"]), [[cap + 1 - r_o, 0], [cap + 1 - r_o, 0]],
			"the overflow's whole rate, even to or below the cap")


func test_the_index_order_never_reaches_the_result() -> void:
	_fill_blob(false)
	var first := CombatWorld.live().terrain_nodes()[0]
	CombatWorld.live().flow_temperature(1)
	var forward := _ints(_BLOB)
	_clear_blob()
	_fill_blob(true)
	assert_ne(CombatWorld.live().terrain_nodes()[0], first, "sanity: the index is filled the other way")
	CombatWorld.live().flow_temperature(1)
	assert_eq(_ints(_BLOB), forward)


func test_two_steps_per_world_turn_equal_two_single_steps() -> void:
	_fill_blob(false)
	var live := CombatWorld.live()
	live.flow_temperature(2)
	var two := _ints(_BLOB)
	_clear_blob()
	_fill_blob(false)
	live.diffuse_temperature()
	live.diffuse_temperature()
	live.decay_terrain()
	assert_eq(_ints(_BLOB), two)


func test_a_shadow_world_never_runs_the_pass() -> void:
	var world := CombatWorld.shadow()
	_worlds.append(world)
	var sa := _c(&"A").snapshot(world)
	var sb := _c(&"B").snapshot(world)
	sa.add_terrain(_fire, 6)
	sb.add_terrain(_lightning, 2)
	world.flow_temperature(1)
	assert_eq(sa.terrain_t(), 6, "no diffusion and no decay on a shadow")
	assert_eq(sb.charge(), 2)


func test_the_index_follows_the_pass() -> void:
	var live := CombatWorld.live()
	var e := _c(&"E")
	_put(&"E", 0, 2)
	var turns := 0
	while e.charge() > 0 and turns < 100:
		assert_true(live.holds_terrain(e), "a Charge-only node stays indexed while it holds Charge")
		live.flow_temperature(1)
		turns += 1
	assert_eq(e.charge(), 0, "Charge decays out")
	assert_false(live.holds_terrain(e), "and the node leaves the index")
	_put(&"A", 6)
	_put(&"B", -6)
	live.flow_temperature(1)
	assert_false(live.holds_terrain(_c(&"A")), "t = 0 and no Charge after the pass: gone")
	assert_false(live.holds_terrain(_c(&"B")))


func test_a_restored_world_matches_its_source_after_one_world_turn() -> void:
	_fill_blob(false)
	_put(&"A", 5)
	_put(&"E", 0, 3)
	var bytes := GraphSnapshot.encode(_graph)
	CombatWorld.live().flow_temperature(1)
	var source := {}
	for id: StringName in _n:
		source[_graph.get_stable_id(_n[id])] = [_c(id).terrain_t(), _c(id).charge()]
	var target := TestWorld.create(self, "Target").graph
	await get_tree().process_frame
	CombatWorld.reset_live()
	GraphSnapshot.decode(bytes, target)
	CombatWorld.live().flow_temperature(1)
	var restored := {}
	for n in target.get_skill_nodes():
		restored[target.get_stable_id(n)] = [n.state.terrain_t, n.state.charge]
	assert_eq(restored, source)
