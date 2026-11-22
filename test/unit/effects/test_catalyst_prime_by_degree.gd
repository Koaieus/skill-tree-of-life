extends GutTest

## A threshold that drops under a node's count primes it, and its Catalyst
## converts (docs/domain/catalyst.md § Two triggers). Fixture: A - B - C plus an
## open gate B - D, so B sits at graph degree 3; flipping the gate removes the
## edge (degree 2) and T drops by 2 × t_per_degree. Flips go through the
## production door, [method AllocationSystem.apply_gate_flip_recorded]. T is
## read off B, never a literal. The shipped `catalyst.tres` is the def: the
## seat reads the status roster.

const _CATALYST := preload("res://effects/status/catalyst.tres")

var _w: TestWorld
var _b: SkillNode
var _node: NodeCombat
var _gate: Gate
var _fire: Element
var _ice: Element
var _lightning: Element


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	var holder := _w.add_entity("P")
	var a := _w.add_node(&"A")
	var b := _w.add_node(&"B")
	var c := _w.add_node(&"C")
	var d := _w.add_node(&"D")
	_w.link(a, b)
	_w.link(b, c)
	_gate = _w.graph.add_gate(b, d, true)
	b.owned_by = holder
	holder.navigator.mirror_add(b)
	await get_tree().process_frame
	_b = b
	_node = b.get_combat()
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_ice = roster.by_id(&"ice")
	_lightning = roster.by_id(&"lightning")


func after_each() -> void:
	CombatWorld.reset_live()


func _t() -> int:
	return _node.terrain_threshold()


func _store() -> int:
	return int(_node.get_status_power(_CATALYST.id))


func _flip() -> void:
	var gates: Array[Gate] = [_gate]
	_w.allocator().apply_gate_flip_recorded(gates, null, [] as Array[SkillNode])


## T after one incident edge goes, read without mutating: T scales with degree.
func _t_after_drop() -> int:
	var deg := _b.get_graph_degree(_w.graph)
	@warning_ignore("integer_division")
	return _t() * (deg - 1) / deg


func test_fixture_b_sits_at_degree_three() -> void:
	assert_eq(_b.get_graph_degree(_w.graph), 3, "fixture: B has three incident edges")


func test_a_gate_removing_an_edge_primes_heat_and_converts() -> void:
	var t0 := _t()
	var heat := _t_after_drop() + 1
	assert_lte(heat, t0, "fixture: Heat is inert at the pre-flip T")
	_node.add_terrain(_fire, heat)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	assert_gt(store, 0, "fixture: B holds Catalyst")
	watch_signals(_b)
	_flip()
	assert_signal_emitted(_b, "catalyst_converted", "the live world announces the conversion")
	assert_lt(_t(), t0, "the flip lowered T")
	assert_gt(_node.terrain_t(), _t(), "B is Burning at the new T")
	assert_eq(_store(), 0, "the whole row converted")
	assert_eq(_node.terrain_t(), heat + store, "Heat = count + converted")


func test_cold_primes_into_frozen_and_converts() -> void:
	var cold := _t_after_drop() + 1
	_node.add_terrain(_ice, cold)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	_flip()
	assert_eq(_store(), 0, "the whole row converted")
	assert_eq(_node.terrain_t(), -(cold + store), "Cold = count + converted")


func test_charge_primes_into_shocked_and_converts() -> void:
	var charge := _t_after_drop() + 1
	_node.add_terrain(_lightning, charge)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	_flip()
	assert_eq(_store(), 0, "the whole row converted")
	assert_eq(_node.charge(), charge + store, "Charge = count + converted")


func test_an_added_edge_converts_nothing() -> void:
	_flip()
	var heat := _t()
	_node.add_terrain(_fire, heat)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	_flip()
	assert_eq(_b.get_graph_degree(_w.graph), 3, "the flip added the edge back")
	assert_eq(_store(), store, "a rising T converts nothing")
	assert_eq(_node.terrain_t(), heat, "Heat untouched")


func test_two_counts_crossing_split_the_store_by_excess_past_the_new_t() -> void:
	var t1 := _t_after_drop()
	assert_gte(_t() - t1, 2, "fixture: the drop leaves room for two different excesses")
	_node.add_terrain(_fire, t1 + 1)
	_node.add_terrain(_lightning, t1 + 2)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	var parts := CatalystStatus.converted(store, {_fire.id(): 1, _lightning.id(): 2})
	_flip()
	assert_eq(_store(), 0, "the whole row converted")
	assert_eq(_node.terrain_t(), t1 + 1 + int(parts.get(_fire.id(), 0)), "Heat's share: excess 1")
	assert_eq(_node.charge(), t1 + 2 + int(parts.get(_lightning.id(), 0)), "Charge's share: excess 2")


func test_a_node_already_primed_converts_nothing_new() -> void:
	var heat := _t() + 1
	_node.add_terrain(_fire, heat)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	_flip()
	assert_eq(_store(), store, "already Burning before the drop: no new priming")
	assert_eq(_node.terrain_t(), heat, "Heat untouched")


func test_a_snapshot_style_edge_removal_converts_nothing() -> void:
	var heat := _t_after_drop() + 1
	_node.add_terrain(_fire, heat)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	_w.graph.remove_edge(_w.graph.edge_between(_gate.from, _gate.to))
	assert_eq(_store(), store, "a bare edge removal (snapshot apply) is not a priming route")
	assert_eq(_node.terrain_t(), heat, "Heat untouched")


func test_a_shadow_world_stays_silent() -> void:
	var t0 := _t()
	var heat := _t_after_drop() + 1
	_node.add_terrain(_fire, heat)
	_node.apply_status(_CATALYST, 3.0)
	var store := _store()
	var shadow := CombatWorld.shadow()
	var slice := shadow.combat_for(_b)
	_w.graph.remove_edge(_w.graph.edge_between(_gate.from, _gate.to))
	watch_signals(_b)
	var changed := shadow.prime_threshold_drops({slice: t0, _node: t0})
	shadow.free_shadow()
	assert_eq(changed.size(), 0, "the shadow reads nothing")
	assert_eq(_store(), store, "the live row is untouched")
	assert_eq(_node.terrain_t(), heat, "live Heat untouched")
	assert_signal_not_emitted(_b, "catalyst_converted", "no cue on the live world")
