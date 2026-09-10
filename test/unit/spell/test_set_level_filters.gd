extends GutTest

## Set-level narrowing on the filter (#850, hub #849 Seam A): the `narrow`
## seam itself, the two filters that replaced the deleted `RankPass` chain
## ([RankThresholdFilter], [TopTiesFilter]), [method CompositeFilter.narrow]
## chaining a set-level child behind a pairwise one, and the resolver-side
## ordering fact that the visit cap runs BEFORE the filter.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

var _helper: SpellTestHelper
var _graph: Graph
var _ctx: PropagationContext


## Star: hub 0 owned by the defender with three leaves 1/2/3, plus a fourth
## leaf 4 hanging off leaf 1 — so leaf 1 has ENTITY degree 2 and leaves 2/3
## degree 1, which is what separates "ties for lowest" from "all neighbours".
##
##   4 — 1 — 0 — 2
##           |
##           3
func before_each() -> void:
	_helper = H.new()
	_graph = _helper.make_graph([[0, 1], [0, 2], [0, 3], [1, 4]], self)
	var atk := _helper.make_entity(_graph, "A")
	var def := _helper.make_entity(_graph, "D")
	_helper.give_big_hp(def)
	_helper.assign_owner(_graph, def, [0, 1, 2, 3, 4])
	_ctx = PropagationContext.new()
	_ctx.graph = _graph
	_ctx.caster = atk


func _n() -> Array[SkillNode]:
	return _graph.get_skill_nodes()


## The hub's neighbours, in scene order: [1, 2, 3].
func _hub_neighbours() -> Array[SkillNode]:
	var n := _n()
	return [n[1], n[2], n[3]] as Array[SkillNode]


func _names(nodes: Array[SkillNode]) -> Array[String]:
	var out: Array[String] = []
	for x in nodes:
		out.append(x.name)
	return out


# ── The `narrow` seam itself ───────────────────────────────────────────────


func test_base_narrow_is_the_pairwise_allows_loop_and_keeps_order() -> void:
	# OwnerFilter is pairwise-only; its inherited `narrow` must reproduce the
	# loop the resolver used to run inline, order preserved.
	var f := _helper.owner_enemy()
	var kept := f.narrow(_n()[0], _hub_neighbours(), null, _ctx)
	assert_eq(_names(kept), ["N1", "N2", "N3"] as Array[String],
			"every neighbour is enemy-owned, order preserved")


func test_base_narrow_drops_exactly_what_allows_rejects() -> void:
	# Nodes 1/2/3 belong to the defender; give node 2 to the caster so the
	# enemy-only filter must drop it and only it.
	_helper.assign_owner(_graph, _ctx.caster, [2])
	var kept := _helper.owner_enemy().narrow(_n()[0], _hub_neighbours(), null, _ctx)
	assert_eq(_names(kept), ["N1", "N3"] as Array[String], "the caster's own node is out")


# ── RankThresholdFilter: candidate vs CURRENT, four ways ───────────────────


## Hub 0 has entity degree 3; leaf 1 has 2; leaves 2 and 3 have 1. So from the
## hub every neighbour is strictly lower, and from leaf 1 the hub is strictly
## higher and leaf 4 strictly lower.
func test_rank_threshold_less_keeps_only_strictly_lower() -> void:
	var f := _helper.rank_threshold_filter(RankThresholdFilter.Compare.LESS)
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N1", "N2", "N3"] as Array[String], "hub deg 3 > every neighbour")
	assert_false(f.allows(_n()[1], _n()[0], null, _ctx), "hub is not below leaf 1")
	assert_true(f.allows(_n()[1], _n()[4], null, _ctx), "leaf 4 (deg 1) is below leaf 1 (deg 2)")


func test_rank_threshold_less_rejects_a_tie() -> void:
	var f := _helper.rank_threshold_filter(RankThresholdFilter.Compare.LESS)
	assert_false(f.allows(_n()[2], _n()[3], null, _ctx),
			"two degree-1 leaves tie, and LESS is strict")


func test_rank_threshold_less_or_equal_admits_the_tie() -> void:
	var f := _helper.rank_threshold_filter(RankThresholdFilter.Compare.LESS_OR_EQUAL)
	assert_true(f.allows(_n()[2], _n()[3], null, _ctx), "a tie passes ≤")
	assert_true(f.allows(_n()[1], _n()[4], null, _ctx), "and so does strictly lower")
	assert_false(f.allows(_n()[1], _n()[0], null, _ctx), "but not strictly higher")


func test_rank_threshold_greater_keeps_only_strictly_higher() -> void:
	var f := _helper.rank_threshold_filter(RankThresholdFilter.Compare.GREATER)
	assert_true(f.allows(_n()[1], _n()[0], null, _ctx), "hub (3) is above leaf 1 (2)")
	assert_false(f.allows(_n()[2], _n()[3], null, _ctx), "a tie fails strict >")
	assert_eq(f.narrow(_n()[0], _hub_neighbours(), null, _ctx).size(), 0,
			"nothing is above the hub")


func test_rank_threshold_greater_or_equal_admits_the_tie() -> void:
	var f := _helper.rank_threshold_filter(RankThresholdFilter.Compare.GREATER_OR_EQUAL)
	assert_true(f.allows(_n()[2], _n()[3], null, _ctx), "a tie passes ≥")
	assert_true(f.allows(_n()[1], _n()[0], null, _ctx), "and so does strictly higher")
	assert_false(f.allows(_n()[1], _n()[4], null, _ctx), "but not strictly lower")


func test_rank_threshold_without_a_ranker_admits_nothing() -> void:
	var f := RankThresholdFilter.new()  # ranker left null
	assert_false(f.allows(_n()[0], _n()[1], null, _ctx))


# ── TopTiesFilter: set-level ───────────────────────────────────────────────


func test_top_ties_highest_keeps_every_node_tying_for_max() -> void:
	# Among [1 (deg 2), 2 (deg 1), 3 (deg 1)] the max is leaf 1, alone.
	var f := _helper.top_ties_filter(TopTiesFilter.Direction.HIGHEST)
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N1"] as Array[String])


func test_top_ties_lowest_keeps_every_node_tying_for_min() -> void:
	# The min is degree 1, and BOTH leaves 2 and 3 sit there — ties, plural,
	# is the whole point of the class.
	var f := _helper.top_ties_filter(TopTiesFilter.Direction.LOWEST)
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N2", "N3"] as Array[String], "both minima survive, in candidate order")


func test_top_ties_empty_in_empty_out() -> void:
	var f := _helper.top_ties_filter()
	assert_eq(f.narrow(_n()[0], [] as Array[SkillNode], null, _ctx).size(), 0)


func test_top_ties_allows_is_derived_from_narrow_not_asserted() -> void:
	# A set of one trivially ties for first, so the pairwise question is true
	# for any scorable node — and false once the ranker cannot score at all.
	var f := _helper.top_ties_filter()
	assert_true(f.allows(_n()[0], _n()[2], null, _ctx), "a lone candidate ties with itself")
	assert_false(TopTiesFilter.new().allows(_n()[0], _n()[2], null, _ctx),
			"no ranker → narrow returns empty → allows is false, by derivation")


# ── CompositeFilter.narrow ─────────────────────────────────────────────────


func test_composite_and_chains_a_set_level_child_behind_a_pairwise_one() -> void:
	# Give leaf 3 to the caster. The pairwise OwnerFilter cuts it first, so
	# the set-level TopTies(LOWEST) then sees only [1, 2] and answers "2" —
	# not node 3, which scores lower still on the unnarrowed set (see the next
	# test). Sequential narrowing is what makes that true.
	_helper.assign_owner(_graph, _ctx.caster, [3])
	var f := _helper.composite_filter([
		_helper.owner_enemy(),
		_helper.top_ties_filter(TopTiesFilter.Direction.LOWEST),
	] as Array[PropagationFilter])
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N2"] as Array[String])


func test_composite_and_order_matters_once_a_set_level_child_is_present() -> void:
	# Same two children, reversed. Node 3 handed to the caster scores entity
	# degree 0 (it is isolated inside the caster's own territory), so a
	# TopTies(LOWEST) that runs on the UNNARROWED set answers [3] alone — and
	# the owner gate behind it then rejects that, leaving nothing. Pairwise
	# first, set-level after, is therefore not a style preference.
	_helper.assign_owner(_graph, _ctx.caster, [3])
	var set_level_first := _helper.composite_filter([
		_helper.top_ties_filter(TopTiesFilter.Direction.LOWEST),
		_helper.owner_enemy(),
	] as Array[PropagationFilter])
	assert_eq(set_level_first.narrow(_n()[0], _hub_neighbours(), null, _ctx).size(), 0,
			"the set-level child picked a node the pairwise child was always going to cut")


func test_composite_or_is_the_union_in_candidate_order() -> void:
	_helper.assign_owner(_graph, _ctx.caster, [3])
	var f := _helper.composite_filter([
		_helper.owner_enemy(),                                        # → 1, 2
		_helper.top_ties_filter(TopTiesFilter.Direction.LOWEST),      # → 2, 3
	] as Array[PropagationFilter], CompositeFilter.Mode.OR)
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N1", "N2", "N3"] as Array[String], "union, deduped, in candidate order")


func test_composite_with_no_children_narrows_nothing() -> void:
	var f := _helper.composite_filter([] as Array[PropagationFilter])
	assert_eq(_names(f.narrow(_n()[0], _hub_neighbours(), null, _ctx)),
			["N1", "N2", "N3"] as Array[String])


# ── Resolver ordering: the visit cap runs BEFORE the filter ────────────────


func test_visit_cap_runs_before_the_filter_so_a_spent_node_cannot_win_a_tie() -> void:
	# A shape where the already-visited node is the UNIQUE winner of the
	# set-level rule, which is the only case that tells the two orders apart.
	#
	#   4 — 1 — 0 — 2        entity degrees: 0→3, 1→2, 2→1, 3→3, 4/5/6→1
	#           | \
	#           3 — 5
	#           |
	#           6
	#
	# Seed on leaf 2, hop to hub 0. At the hub the candidates are 1, 2 and 3;
	# node 2 has been visited and is at its cap.
	#   cap FIRST  → tie over {1 (deg 2), 3 (deg 3)} → 1 wins → a third hit.
	#   cap SECOND → tie over {1, 2 (deg 1), 3} → 2 wins → the cap then
	#                deletes it → the walk dies at the hub, two hits.
	var helper := H.new()
	var graph := helper.make_graph(
			[[0, 1], [0, 2], [0, 3], [1, 4], [3, 5], [3, 6]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4, 5, 6])
	var n := graph.get_skill_nodes()
	var config := helper.make_config(
			helper.fan_all(),
			helper.composite_filter([
				helper.owner_enemy(),
				helper.top_ties_filter(TopTiesFilter.Direction.LOWEST),
			] as Array[PropagationFilter]),
			helper.max_reducer(),
			{max_hops = 2, max_visits_per_node = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[2], n[0], atk, graph)
	var targets: Array[String] = []
	for hit in outcome.hits:
		targets.append((hit.target as SkillNode).name)
	assert_eq(targets, ["N2", "N0", "N1"] as Array[String],
			"the spent node never enters the tie, so the live joint-lowest wins")
