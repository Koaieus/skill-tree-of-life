extends GutTest

## The reach slot on [PropagationConfig] (where a wave CAN go, before the cap
## and the filter) and [member CastSpell.arrived_from] (every merged front's
## predecessor, as an unordered set).

const H := preload("res://test/unit/spell/spell_test_helper.gd")


## Proposes a fixed node list, edges or not.
class FixedReach extends PropagationReach:
	var nodes: Array[SkillNode] = []

	func candidates(_lctx: LandingContext) -> Array[SkillNode]:
		return nodes.duplicate()

	func get_description() -> String:
		return "Reaches fixed nodes."


## Records each landing's `arrived_from`, keyed by the landed node.
class ArrivedRecorder extends OnHitEffect:
	var seen: Dictionary = {}  ## SkillNode -> Array[SkillNode]

	func apply(landing: HitLanding) -> void:
		var lctx := landing as LandingContext
		seen[lctx.node] = lctx.payload.arrived_from.duplicate()


## [helper, graph, attacker, nodes] — attacker owns 0, the defender the rest.
func _setup(adjacency: Array, defender_indices: Array, orphan: bool = false) -> Array:
	var helper := H.new()
	var graph := helper.make_graph(adjacency, self)
	if orphan:
		var node := preload("res://skill_node/skill_node.tscn").instantiate() as SkillNode
		node.name = "Orphan"
		graph.skill_nodes_container.add_child(node)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, defender_indices)
	helper.assign_owner(graph, atk, [0])
	return [helper, graph, atk, graph.get_skill_nodes()]


func _hit_count(helper: SpellTestHelper, outcome: AttackOutcome, node: SkillNode) -> int:
	return (helper.hits_by_node(outcome).get(node, []) as Array).size()


func test_null_reach_fans_to_exactly_the_graph_neighbours() -> void:
	var c := _setup([[0, 1], [1, 2], [1, 3], [3, 4]], [1, 2, 3, 4])
	var helper: SpellTestHelper = c[0]
	var n: Array[SkillNode] = c[3]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	assert_null(config.reach, "reach defaults to null")
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[1], n[0], c[2], c[1])
	assert_eq(_hit_count(helper, outcome, n[1]), 1)
	assert_eq(_hit_count(helper, outcome, n[2]), 1)
	assert_eq(_hit_count(helper, outcome, n[3]), 1)
	assert_eq(_hit_count(helper, outcome, n[4]), 0, "two hops away, out of a one-hop wave")


func test_reach_lands_on_a_node_with_no_edge_to_the_landing() -> void:
	var c := _setup([[0, 1], [1, 2]], [1, 2, 3], true)
	var helper: SpellTestHelper = c[0]
	var n: Array[SkillNode] = c[3]
	var reach := FixedReach.new()
	reach.nodes = [n[3]]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	config.reach = reach
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[1], n[0], c[2], c[1])
	assert_eq(_hit_count(helper, outcome, n[3]), 1, "the edgeless orphan lands")
	assert_eq(_hit_count(helper, outcome, n[2]), 0, "the reach replaced the neighbours")


func test_reach_candidates_still_pass_the_visit_cap_and_the_filter() -> void:
	var c := _setup([[0, 1], [1, 2]], [1, 2, 3], true)
	var helper: SpellTestHelper = c[0]
	var n: Array[SkillNode] = c[3]
	var reach := FixedReach.new()
	# n[1] is the landing itself (cap 1, already visited); n[0] is the caster's
	# own node (the enemy filter refuses it); n[3] is the control.
	reach.nodes = [n[1], n[0], n[3]]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	config.reach = reach
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[1], n[0], c[2], c[1])
	assert_eq(_hit_count(helper, outcome, n[1]), 1, "over-cap node never lands again")
	assert_eq(_hit_count(helper, outcome, n[0]), 0, "filtered node never lands")
	assert_eq(_hit_count(helper, outcome, n[3]), 1, "the eligible reach candidate lands")


func test_reach_line_joins_the_config_description() -> void:
	var helper := H.new()
	var config := helper.make_config(helper.fan_all(), null, null, {max_hops = 1})
	config.reach = FixedReach.new()
	assert_string_contains(config.get_description(), "Reaches fixed nodes.")


func _assert_diamond_arrived_from(reducer: IncidentReducer) -> void:
	# Diamond 1 → {2, 3} → 4: two fronts merge on 4.
	var c := _setup([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [1, 2, 3, 4])
	var helper: SpellTestHelper = c[0]
	var n: Array[SkillNode] = c[3]
	var recorder := ArrivedRecorder.new()
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), reducer,
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new(), recorder], 10.0)
	SpellResolver.resolve(spell, n[1], n[0], c[2], c[1])
	assert_true(recorder.seen.has(n[4]), "node 4 landed")
	var arrived: Array = recorder.seen.get(n[4], [])
	assert_eq(arrived.size(), 2, "both fronts, deduped")
	assert_true(arrived.has(n[2]), "front from 2 is in the set")
	assert_true(arrived.has(n[3]), "front from 3 is in the set")
	assert_true((recorder.seen.get(n[1], [null]) as Array).is_empty(), "seed arrived_from is empty")
	assert_eq(recorder.seen.get(n[2], []), [n[1]], "a single front's set is its predecessor")


func test_arrived_from_holds_every_merged_front_under_first_reducer() -> void:
	_assert_diamond_arrived_from(H.new().first_reducer())


func test_arrived_from_holds_every_merged_front_under_sum_reducer() -> void:
	_assert_diamond_arrived_from(H.new().sum_reducer())


func test_arrived_from_with_no_reducer_still_holds_every_front() -> void:
	_assert_diamond_arrived_from(null)
