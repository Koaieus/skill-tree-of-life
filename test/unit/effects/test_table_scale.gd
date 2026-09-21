extends GutTest

## TableScale: a per-step multiplier list indexed by the rounded distance —
## the one shape that alternates sign and stops dead, which no continuous
## scale and no value-based discard can author. Past the end is
## `DistanceScale.NOT_GRANTED`, never 0.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _chain: Array[SkillNode]


func _table(steps: Array[float], past_end: int = TableScale.PastEnd.NOT_GRANTED) -> TableScale:
	var t := TableScale.new()
	t.per_step = steps
	t.past_end = past_end
	return t


# ── Acceptance 1: the formula ───────────────────────────────────────────────

func test_each_step_returns_v_times_its_entry() -> void:
	var t := _table([5.0, -4.0, 3.0, -2.0, 1.0])
	for i in 5:
		assert_almost_eq(t.scale(float(i), -1.0, 1.0), [5.0, -4.0, 3.0, -2.0, 1.0][i], 0.001, "d = %d" % i)
	assert_almost_eq(t.scale(1.0, -1.0, 2.0), -8.0, 0.001, "a multiplier table: v * entry")


func test_distance_is_rounded_to_the_nearest_step() -> void:
	var t := _table([5.0, -4.0, 3.0])
	assert_almost_eq(t.scale(0.4, -1.0, 1.0), 5.0, 0.001, "0.4 → step 0")
	assert_almost_eq(t.scale(1.6, -1.0, 1.0), 3.0, 0.001, "1.6 → step 2")


func test_past_the_end_is_not_granted_by_default() -> void:
	var t := _table([5.0, -4.0, 3.0, -2.0, 1.0])
	assert_true(is_nan(t.scale(5.0, -1.0, 1.0)), "d = 5 → NOT_GRANTED (NaN), never 0")
	assert_true(is_nan(t.scale(50.0, -1.0, 1.0)), "far past → NOT_GRANTED")


func test_hold_last_repeats_the_final_entry() -> void:
	var t := _table([5.0, -4.0, 3.0, -2.0, 1.0], TableScale.PastEnd.HOLD_LAST)
	assert_almost_eq(t.scale(5.0, -1.0, 1.0), 1.0, 0.001, "d = 5 holds the last entry")
	assert_almost_eq(t.scale(50.0, -1.0, 3.0), 3.0, 0.001, "still v * last")


func test_empty_table_is_not_granted_everywhere(params = use_parameters([
		TableScale.PastEnd.NOT_GRANTED, TableScale.PastEnd.HOLD_LAST])) -> void:
	var t := _table([], params)
	assert_true(is_nan(t.scale(0.0, -1.0, 1.0)), "empty → NaN at the source")
	assert_true(is_nan(t.scale(3.0, -1.0, 1.0)), "empty → NaN anywhere")


func test_does_not_use_the_bound() -> void:
	assert_false(_table([1.0]).uses_bound())


# ── Acceptance 2: through an aura ───────────────────────────────────────────

## One straight line N0—N1—…—N7, so hop distance from N0 IS the index.
func _build_chain() -> void:
	AuraDistanceCache.clear()
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
	_chain = []
	for i in 8:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_chain.append(sn)
	for i in 7:
		_graph.add_edge(_chain[i], _chain[i + 1])
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _spawn_owning_whole_chain() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container: NodeEffectReadout.gather walks it for grant rows.
	_graph.entities_container.add_child(ent)
	await get_tree().process_frame
	for n in _chain:
		_alloc.force_allocate(ent, n)
	ent.core_location = _chain[0]
	ent.stat_board.armor.base_value = 0.0
	return ent


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


func _grant_rows(n: SkillNode) -> int:
	return NodeEffectReadout.gather(n, _graph).size()


func test_aura_grants_exactly_the_table_and_no_row_past_it() -> void:
	_build_chain()
	var ent: Entity = await _spawn_owning_whole_chain()
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = 1.0
	var aura := AuraEffect.new()
	var reach := HopRangeFinder.new()
	reach.max_hops = 6
	aura.reach = reach
	aura.distance_scale = _table([5.0, -4.0, 3.0, -2.0, 1.0])
	aura.discard = AuraEffect.Discard.NONE
	aura.modifiers = [m]
	ent.grant_effect(aura)

	var expected := [5.0, -4.0, 3.0, -2.0, 1.0]
	for i in 5:
		assert_eq(_grant_rows(_chain[i]), 1, "hop %d: one row" % i)
		assert_almost_eq(_armor(_chain[i]), expected[i], 0.001, "hop %d lands its entry" % i)
	assert_eq(_grant_rows(_chain[5]), 0, "hop 5: past the end, no ledger entry despite discard NONE")
	assert_eq(_grant_rows(_chain[6]), 0, "hop 6: in reach, still past the end")
	assert_eq(_grant_rows(_chain[7]), 0, "hop 7: past reach")
