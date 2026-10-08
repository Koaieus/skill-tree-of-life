extends GutTest

## Pestilence (#1504): the SUM spell. A thin poison fan whose reducer folds
## stacks by SUM, so a node lands one innate share per branch converging on
## it in one wave — per landing, never compounding — and a node's per-cast
## total is bounded by its entity degree × `max_visits_per_node` × innate.

const _DEF_PATH := "res://attack/spell/defs/pestilence.tres"

## 0 → seed 1 → {2, 3} → 4.
const DIAMOND := [[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]]
## 0 → seed 1 → {2, 3, 5} → 4.
const TRIPLE := [[0, 1], [1, 2], [1, 3], [1, 5], [2, 4], [3, 4], [5, 4]]
## 0 → seed 1 → {2, 3} → 4 → {5, 6} → 7.
const DOUBLE_DIAMOND := [[0, 1], [1, 2], [1, 3], [2, 4], [3, 4], [4, 5], [4, 6], [5, 7], [6, 7]]
## A wheel: hub 1 spoked to the closed ring 2..7, a chord 2–5; the caster owns 0.
const WHEEL := [[0, 2], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7],
		[2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 2], [2, 5]]

var _h: SpellTestHelper
var _def: SpellDef


func before_each() -> void:
	_h = SpellTestHelper.new()
	_def = load(_DEF_PATH) as SpellDef if ResourceLoader.exists(_DEF_PATH) else null


func _innate() -> float:
	return float(_def.affinities[0].innate)


## Attacker owns 0, the defender every other node. Returns [graph, nodes, outcome].
func _cast(adjacency: Array, node_count: int, seed_idx: int = 1) -> Array:
	var graph := _h.make_graph(adjacency, self)
	var atk := _h.make_entity(graph, "A", Color.RED)
	var dfn := _h.make_entity(graph, "D", Color.BLUE)
	_h.give_big_hp(dfn)
	var enemy: Array = []
	for i in range(1, node_count):
		enemy.append(i)
	_h.assign_owner(graph, atk, [0])
	_h.assign_owner(graph, dfn, enemy)
	var n := graph.get_skill_nodes()
	return [graph, n, SpellResolver.resolve(_def, n[seed_idx], n[0], atk, graph)]


func _statuses_on(outcome: AttackOutcome, node: SkillNode) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		if hit.target == node and hit is StatusInstance:
			out.append(hit)
	return out


## The node's first landing (its earliest wave).
func _first_power(outcome: AttackOutcome, node: SkillNode) -> float:
	var first: StatusInstance = null
	for hit in _statuses_on(outcome, node):
		if first == null or hit.arrival_time < first.arrival_time:
			first = hit
	return first.power if first != null else 0.0


func _ready_def() -> bool:
	assert_not_null(_def, "pestilence.tres exists")
	return _def != null


func test_a_diamond_lands_two_shares_on_the_far_node() -> void:
	if not _ready_def():
		return
	var r := _cast(DIAMOND, 5)
	var n: Array = r[1]
	assert_almost_eq(_first_power(r[2], n[2]), _innate(), 0.0001, "a lone branch lands one share")
	assert_almost_eq(_first_power(r[2], n[4]), 2.0 * _innate(), 0.0001, "two branches meet: 2 shares")


func test_three_converging_branches_land_three_shares() -> void:
	if not _ready_def():
		return
	var r := _cast(TRIPLE, 6)
	assert_almost_eq(_first_power(r[2], r[1][4]), 3.0 * _innate(), 0.0001)


func test_a_double_diamond_lands_two_at_each_convergence_never_four() -> void:
	if not _ready_def():
		return
	var r := _cast(DOUBLE_DIAMOND, 8)
	var n: Array = r[1]
	assert_almost_eq(_first_power(r[2], n[4]), 2.0 * _innate(), 0.0001, "first convergence: 2")
	assert_almost_eq(_first_power(r[2], n[7]), 2.0 * _innate(), 0.0001, "second convergence: 2, never 4")
	for hit in _statuses_on(r[2], n[7]):
		assert_lte(hit.power, 2.0 * _innate(), "no landing on the far node compounds")


func test_a_hub_total_is_bounded_by_degree_times_visits() -> void:
	if not _ready_def():
		return
	var visits: int = _def.propagation.max_visits_per_node
	for seed_idx in [1, 2, 4]:
		var r := _cast(WHEEL, 8, seed_idx)
		var graph: Graph = r[0]
		var n: Array = r[1]
		for i in range(1, 8):
			var node: SkillNode = n[i]
			var total := 0.0
			for hit in _statuses_on(r[2], node):
				total += hit.power
			var bound := node.get_entity_degree(graph) * visits * _innate()
			assert_lte(total, bound, "seed %d, node %d: total within degree × visits × innate" % [seed_idx, i])
		assert_gt(_first_power(r[2], n[seed_idx]), 0.0, "fixture: the seed is poisoned")


func test_the_def_is_the_pure_status_sum_fan() -> void:
	if not _ready_def():
		return
	assert_eq(_def.on_hit_effects.size(), 0, "no damage — the poison does the work")
	assert_not_null(_def.propagation.reducer)
	assert_eq(_def.propagation.reducer.stack_fold, IncidentReducer.StackFold.SUM)
	assert_string_contains(_def.propagation.get_description(), _def.propagation.reducer.fold_description())
