extends GutTest

## Targeting + range-finder coverage (#284): the gates every cast goes through
## before a spell ever propagates. `NodeTargeting`'s ownership buckets,
## `HopRangeFinder`'s reach math, and `SpellBook`'s `min_degree` source gate.
##
## The load-bearing pin is the `in_range` / `gather` divergence: `in_range`
## hardwires the GLOBAL `graph.navigator` (reach through anyone's territory),
## while `gather` traverses whatever mirror it is handed. That is deliberate
## (`.claude/rules/graph.md`) and this file exists so nobody "simplifies" it.
##
## The fixture is built through `add_skill_node` / `add_edge`, NOT by adding to
## the containers: only the former emits `node_added` / `edge_added`, so only it
## populates `graph.navigator`. `SpellTestHelper.make_graph` takes the container
## shortcut (fine for resolver tests that never touch the global mirror), which
## is why this file builds its own graph and borrows only the helper's entity
## and allocation builders.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

## Topology:
##
##     0 — 1 — 2 — 3        5   (isolated)
##         |
##         4
##
## n1 has graph degree 3 (the discriminator for the entity-degree gate), the
## 0-1-2-3 chain gives clean hop counts, n5 is unreachable from everything.
const _EDGES := [[0, 1], [1, 2], [2, 3], [1, 4]]

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _a: Entity  # attacker
var _d: Entity  # defender


func before_each() -> void:
	_h = SpellTestHelper.new()
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
	_n = []
	for i in 6:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_n.append(sn)
	for pair in _EDGES:
		_graph.add_edge(_n[pair[0]], _n[pair[1]])
	_a = _h.make_entity(_graph, "A", Color.RED)
	_d = _h.make_entity(_graph, "D", Color.BLUE)
	_h.give_big_hp(_a)
	_h.give_big_hp(_d)
	# The fixture's own tripwire: a graph populated via the containers would
	# leave this mirror empty and every reach query below would return
	# nothing, with no error.
	assert_eq(_graph.navigator.get_mirrored_nodes().size(), 6,
		"fixture must populate the global navigator")
	assert_eq(_a.navigator.graph, _graph, "attacker navigator must bind the fixture graph")


func _plan_for(attacker: Entity) -> AttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	return plan


func _targeting(ownership_filter: int, finder: RangeFinder = null) -> NodeTargeting:
	var t := NodeTargeting.new()
	t.ownership_filter = ownership_filter
	t.range_finder = finder
	return t


func _hops(max_hops: int) -> HopRangeFinder:
	var f := HopRangeFinder.new()
	f.max_hops = max_hops
	return f


## Sorted plain-String names — `Node.name` is a StringName, which neither sorts
## nor compares equal to a String literal.
func _names(nodes: Array) -> Array[String]:
	var out: Array[String] = []
	for n in nodes:
		out.append(String(n.name))
	out.sort()
	return out


## SET (priority 0) so the board's own INT threshold ladder cannot move the
## expected number out from under the assertions — same idiom as
## test_spell_tooltip_values.gd.
func _set_spell_hops(entity: Entity, value: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spell_hops"
	mod.operation = StatModifier.Operation.SET
	mod.value = value
	entity.stat_board.add_modifier(mod)


# ── NodeTargeting: ownership buckets ────────────────────────────────────────


func test_default_hostile_filter_enumerates_exactly_the_enemy_nodes() -> void:
	_h.assign_owner(_graph, _a, [0])
	_h.assign_owner(_graph, _d, [2, 3])
	var t := NodeTargeting.new()  # authored default: Hostile (8), no finder
	assert_eq(t.ownership_filter, SkillNode.Ownership.HOSTILE)
	assert_eq(_names(t.valid_targets(_plan_for(_a), _n[0])), ["N2", "N3"])


func test_ownership_buckets_partition_the_board() -> void:
	_h.assign_owner(_graph, _a, [0, 1])
	_h.assign_owner(_graph, _d, [3])
	var plan := _plan_for(_a)
	assert_eq(_names(_targeting(SkillNode.Ownership.MINE).valid_targets(plan, _n[0])),
		["N0", "N1"], "Mine")
	assert_eq(_names(_targeting(SkillNode.Ownership.NEUTRAL).valid_targets(plan, _n[0])),
		["N2", "N4", "N5"], "Neutral")
	assert_eq(_names(_targeting(SkillNode.Ownership.HOSTILE).valid_targets(plan, _n[0])),
		["N3"], "Hostile")
	const ANY := 15
	assert_eq(_names(_targeting(ANY).valid_targets(plan, _n[0])),
		["N0", "N1", "N2", "N3", "N4", "N5"], "Any (15) reaches every node")


func test_is_valid_target_is_false_on_any_null_input() -> void:
	_h.assign_owner(_graph, _a, [0])
	_h.assign_owner(_graph, _d, [1])
	var t := NodeTargeting.new()
	var plan := _plan_for(_a)
	assert_false(t.is_valid_target(null, _n[0], _n[1]), "null plan")
	assert_false(t.is_valid_target(plan, null, _n[1]), "null source")
	assert_false(t.is_valid_target(plan, _n[0], null), "null candidate")
	assert_false(t.is_valid_target(_plan_for(null), _n[0], _n[1]), "plan without attacker")
	assert_true(t.is_valid_target(plan, _n[0], _n[1]), "sanity: the real call passes")


func test_valid_targets_is_empty_without_an_attacker() -> void:
	_h.assign_owner(_graph, _d, [1])
	assert_eq(NodeTargeting.new().valid_targets(_plan_for(null), _n[0]).size(), 0)


# ── HopRangeFinder.in_range: reach over the global navigator ────────────────


func test_in_range_counts_shortest_path_edges_up_to_max_hops() -> void:
	_h.assign_owner(_graph, _a, [0])
	var f := _hops(2)
	assert_true(f.in_range(_a, _n[0], _n[0]), "source is at 0 hops of itself")
	assert_true(f.in_range(_a, _n[0], _n[1]), "1 hop")
	assert_true(f.in_range(_a, _n[0], _n[2]), "2 hops")
	assert_true(f.in_range(_a, _n[0], _n[4]), "2 hops down the branch")
	assert_false(f.in_range(_a, _n[0], _n[3]), "3 hops is out")
	assert_false(f.in_range(_a, _n[0], _n[5]), "no path at all")


func test_in_range_is_false_without_a_navigator_to_read() -> void:
	var f := _hops(2)
	assert_false(f.in_range(null, _n[0], _n[1]), "null attacker")
	assert_false(f.in_range(_a, null, _n[1]), "null source")
	assert_false(f.in_range(_a, _n[0], null), "null candidate")


func test_ranged_targeting_intersects_ownership_with_reach() -> void:
	_h.assign_owner(_graph, _a, [0])
	_h.assign_owner(_graph, _d, [2, 3])
	var t := _targeting(SkillNode.Ownership.HOSTILE, _hops(2))
	assert_eq(_names(t.valid_targets(_plan_for(_a), _n[0])), ["N2"],
		"N3 is hostile but 3 hops away; N1 is in reach but neutral")


# ── The divergence: in_range reads the GLOBAL mirror, gather reads what it's handed


func test_in_range_reaches_through_enemy_territory_but_gather_over_the_owned_mirror_stops_at_the_border() -> void:
	_h.assign_owner(_graph, _a, [0])
	_h.assign_owner(_graph, _d, [1, 2])
	var f := _hops(2)
	# in_range: global navigator — the path 0-1-2 runs through D's land and counts.
	assert_true(f.in_range(_a, _n[0], _n[2]),
		"in_range measures over graph.navigator, so enemy nodes are traversable")
	# gather over the attacker's OWNED mirror: n1 is not in it, so nothing past n0.
	var owned := f.gather(_n[0], _a.navigator)
	assert_eq(owned.size(), 1, "owned mirror holds only n0; the BFS cannot leave it")
	assert_eq(owned.get(_n[0]), 0.0)
	# gather over the global mirror agrees with in_range.
	var global := f.gather(_n[0], _graph.navigator)
	assert_true(global.has(_n[2]), "the same finder reaches n2 when handed the global mirror")


func test_gather_over_the_owned_mirror_measures_hops_through_owned_land_only() -> void:
	# A owns the whole 0-1-2 chain but not 4: hop distances follow the owned
	# induced subgraph, and 4 (a neutral neighbour of 1) is absent.
	_h.assign_owner(_graph, _a, [0, 1, 2])
	var got := _hops(3).gather(_n[0], _a.navigator)
	assert_eq(got.size(), 3)
	assert_eq(got.get(_n[0]), 0.0)
	assert_eq(got.get(_n[1]), 1.0)
	assert_eq(got.get(_n[2]), 2.0)
	assert_false(got.has(_n[4]), "n4 is adjacent to owned n1 but not owned")


# ── gather: distances, not membership ───────────────────────────────────────


func test_gather_returns_hop_distances_and_omits_nodes_past_max_hops() -> void:
	var got := _hops(2).gather(_n[0], _graph.navigator)
	assert_eq(got.size(), 4, "n0, n1, n2, n4")
	assert_eq(got.get(_n[0]), 0.0, "source at distance 0")
	assert_eq(got.get(_n[1]), 1.0)
	assert_eq(got.get(_n[2]), 2.0)
	assert_eq(got.get(_n[4]), 2.0)
	assert_false(got.has(_n[3]), "3 hops is past the cap")
	assert_false(got.has(_n[5]), "unreachable")


func test_gather_is_empty_for_a_null_source_or_mirror() -> void:
	var f := _hops(2)
	assert_eq(f.gather(null, _graph.navigator).size(), 0)
	assert_eq(f.gather(_n[0], null).size(), 0)


func test_gather_multi_keeps_sources_separate() -> void:
	var got := _hops(1).gather_multi([_n[0], _n[3]], _graph.navigator)
	assert_eq(got.size(), 2)
	assert_eq(_names(got[_n[0]].keys()), ["N0", "N1"])
	assert_eq(_names(got[_n[3]].keys()), ["N2", "N3"])
	assert_eq(got[_n[3]].get(_n[2]), 1.0, "each per-source dict still carries distances")


func test_max_reach_is_the_authored_hop_cap() -> void:
	assert_eq(_hops(4).max_reach(), 4.0)


# ── spell_hops: in_range and an attacker-aware gather agree; a null attacker stays raw


func test_spell_hops_extends_in_range_and_attacker_aware_gather_but_not_raw_gather() -> void:
	_h.assign_owner(_graph, _a, [0])
	_set_spell_hops(_a, 1.0)
	var f := _hops(2)
	assert_eq(f.effective_max_hops(_a, _n[0]), 3)
	assert_true(f.in_range(_a, _n[0], _n[3]), "2 + 1 bonus hop reaches n3")
	var scaled := f.gather(_n[0], _graph.navigator, _a)
	assert_eq(scaled.get(_n[3]), 3.0, "attacker-aware gather uses the same effective reach")
	var raw := f.gather(_n[0], _graph.navigator)
	assert_false(raw.has(_n[3]), "attacker-less gather (aura path) keeps the raw max_hops")


# ── min_degree: the source gate, measured as ENTITY degree ──────────────────


func _spell_needing_degree(min_degree: int) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "GateTest"
	spell.min_degree = min_degree
	return spell


func test_min_degree_gate_reads_entity_degree_not_graph_degree() -> void:
	# n1 has graph degree 3, but A owns only 0 and 1 so its entity degree is 1.
	_h.assign_owner(_graph, _a, [0, 1])
	var book := _a.get_spellbook()
	var spell := _spell_needing_degree(2)
	assert_eq(_n[1].get_graph_degree(_graph), 3, "sanity: graph degree is 3")
	assert_false(book.is_castable(spell, _n[1], _a),
		"entity degree 1 < min_degree 2, whatever the board says")
	assert_eq(book.eligible_sources(spell, _a).size(), 0)
	# Claim n2: n1's entity degree becomes 2 and the gate opens.
	_h.assign_owner(_graph, _a, [2])
	assert_true(book.is_castable(spell, _n[1], _a))
	assert_eq(_names(book.eligible_sources(spell, _a)), ["N1"],
		"n0 and n2 still sit at entity degree 1")


func test_min_degree_gate_rejects_unowned_sources_and_passes_a_null_source() -> void:
	_h.assign_owner(_graph, _a, [0])
	_h.assign_owner(_graph, _d, [1, 2, 4])
	var book := _a.get_spellbook()
	# min_degree 0 so the lone owned n0 (entity degree 0) passes on degree
	# alone — what fails n1 below is ownership, not the number.
	var spell := _spell_needing_degree(0)
	assert_true(book.is_castable(spell, _n[0], _a), "own node, degree gate trivially met")
	assert_false(book.is_castable(spell, _n[1], _a),
		"n1 has plenty of degree but belongs to D")
	assert_true(book.is_castable(spell, null, _a),
		"pre-source state must not grey the spell out")
	assert_false(book.is_castable(null, _n[0], _a), "no spell, no cast")
