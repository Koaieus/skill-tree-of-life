extends GutTest

## Terrain is node state (#1794): a Heat / Cold / Charge landing writes the
## node's two ints through [method NodeCombat.add_terrain] and never lands a
## status row; the live index follows that one writer (and a snapshot decode);
## the fingerprint folds the ints. Fixture: A - B, both unallocated.

const _POISON := preload("res://effects/status/poison.tres")

var _w: TestWorld
var _graph: Graph
var _a: SkillNode
var _b: SkillNode
var _fire: Element
var _ice: Element
var _lightning: Element
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	CombatWorld.reset_live()
	_worlds = []
	_w = TestWorld.create(self)
	_graph = _w.graph
	_a = _w.add_node(&"A")
	_b = _w.add_node(&"B")
	_w.link(_a, _b)
	await get_tree().process_frame
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_ice = roster.by_id(&"ice")
	_lightning = roster.by_id(&"lightning")


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()
	CombatWorld.reset_live()


func test_heat_landing_on_an_unallocated_node_raises_t_and_adds_no_row() -> void:
	assert_null(_a.owned_by, "precondition: unallocated")
	_a.get_combat().apply_status(_fire.terrain, 3.0)
	assert_eq(_a.state.terrain_t, 3, "Heat raises the signed t")
	assert_eq(_a.get_combat().get_statuses().size(), 0, "terrain never lands a status row")


func test_cold_lowers_t_and_nets_against_heat() -> void:
	_b.get_combat().apply_status(_ice.terrain, 2.0)
	assert_eq(_b.state.terrain_t, -2, "Cold lowers t")
	_a.get_combat().apply_status(_fire.terrain, 3.0)
	_a.get_combat().apply_status(_ice.terrain, 2.0)
	assert_eq(_a.state.terrain_t, 1, "Heat 3 then Cold 2 nets to 1")
	assert_eq(_a.get_combat().get_statuses().size(), 0)


func test_charge_is_independent_of_t_and_never_below_zero() -> void:
	var c := _a.get_combat()
	c.apply_status(_fire.terrain, 2.0)
	c.apply_status(_lightning.terrain, 3.0)
	assert_eq(_a.state.charge, 3, "Charge lands on its own int")
	assert_eq(_a.state.terrain_t, 2, "and leaves t alone")
	c.add_terrain(_lightning, -5)
	assert_eq(_a.state.charge, 0, "Charge clamps at 0")
	assert_eq(_a.state.terrain_t, 2)


func test_a_non_member_status_still_lands_as_a_row() -> void:
	var e := _w.add_entity("Holder")
	await get_tree().process_frame
	_w.allocator().force_allocate(e, _a)
	_a.get_combat().apply_status(_POISON, 2.0)
	assert_eq(_a.get_combat().get_statuses().size(), 1, "poison is no element's terrain")
	assert_eq(_a.state.terrain_t, 0)


func test_the_first_write_notes_the_node_and_back_to_zero_forgets_it() -> void:
	var live := CombatWorld.live()
	var c := _a.get_combat()
	assert_false(live.holds_terrain(c), "precondition: not indexed")
	c.add_terrain(_fire, 2)
	assert_true(live.holds_terrain(c), "first terrain write notes the node")
	c.add_terrain(_lightning, 1)
	c.add_terrain(_ice, 2)
	assert_true(live.holds_terrain(c), "t = 0 but charge > 0 still carries terrain")
	c.add_terrain(_lightning, -1)
	assert_false(live.holds_terrain(c), "t = 0 and charge = 0 forgets it")
	assert_eq(live.terrain_nodes().size(), 0)


func test_a_shadow_write_never_touches_the_index_or_the_live_state() -> void:
	var world := CombatWorld.shadow()
	_worlds.append(world)
	var shadow := _a.get_combat().snapshot(world)
	shadow.add_terrain(_fire, 5)
	assert_eq(shadow.terrain_t(), 5, "the shadow's clone moved")
	assert_eq(_a.state.terrain_t, 0, "the live state did not")
	assert_false(CombatWorld.live().holds_terrain(_a.get_combat()))
	assert_false(CombatWorld.live().holds_terrain(shadow))
	assert_false(world.holds_terrain(shadow), "a shadow world keeps no index")


func test_a_decoded_snapshot_rebuilds_the_index() -> void:
	_a.get_combat().add_terrain(_ice, 4)
	_b.get_combat().add_terrain(_lightning, 2)
	var bytes := GraphSnapshot.encode(_graph)
	var target := TestWorld.create(self, "Target").graph
	await get_tree().process_frame
	CombatWorld.reset_live()
	GraphSnapshot.decode(bytes, target)
	var live := CombatWorld.live()
	var by_id := {}
	for n in target.get_skill_nodes():
		by_id[target.get_stable_id(n)] = n
	var ta: SkillNode = by_id[_graph.get_stable_id(_a)]
	var tb: SkillNode = by_id[_graph.get_stable_id(_b)]
	assert_eq(ta.state.terrain_t, -4)
	assert_eq(tb.state.charge, 2)
	assert_true(live.holds_terrain(ta.get_combat()), "decode notes a node carrying t")
	assert_true(live.holds_terrain(tb.get_combat()), "decode notes a node carrying charge")
	assert_eq(live.terrain_nodes().size(), 2, "and nothing else")


func test_the_fingerprint_folds_terrain() -> void:
	var bare := WorldFingerprint.compute(_graph)
	_a.get_combat().add_terrain(_fire, 1)
	var hot := WorldFingerprint.compute(_graph)
	assert_ne(hot, bare, "one node's t differing folds differently")
	_a.get_combat().add_terrain(_fire, -1)
	_b.get_combat().add_terrain(_fire, 1)
	assert_ne(WorldFingerprint.compute(_graph), hot, "the same t on another node folds differently")
	_b.get_combat().add_terrain(_fire, -1)
	assert_eq(WorldFingerprint.compute(_graph), bare, "equal terrain folds equal")
