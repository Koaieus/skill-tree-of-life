extends GutTest

## Coverage for #378 slice B — [AiCombatScorer]: the shared per-candidate EV
## scorer used to rank ranged/magic (and, from slice C, melee) attack
## candidates, plus its tier-gated bonus/penalty terms.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _BLOCKER_FACTION := preload("res://entity/factions/blocker.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _ai: Entity
var _hostile: Entity
var _nodes: Array[SkillNode] # N0 (AI core) - N1 (AI leaf) ... H0 (hostile core) - H1 - H2 (hostile leaf)


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	# N0 (AI core) - N1 (AI leaf)      H0 (hostile core) - H1 - H2 (hostile leaf)
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[2], _nodes[3])
	_add_edge(_nodes[3], _nodes[4])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_ai = autofree(_make_entity("AI"))
	_graph.add_child(_ai)
	_hostile = autofree(_make_entity("Hostile", _PLAYER_FACTION))
	_graph.add_child(_hostile)

	await get_tree().process_frame

	_alloc.force_allocate(_ai, _nodes[0])
	_ai.core_location = _nodes[0]
	_alloc.force_allocate(_ai, _nodes[1])
	_alloc.force_allocate(_hostile, _nodes[2])
	_hostile.core_location = _nodes[2]
	_alloc.force_allocate(_hostile, _nodes[3])
	_alloc.force_allocate(_hostile, _nodes[4])

	# AI leaf (N1) sits within default `range` (400.0) of the hostile core (N2).
	_nodes[0].global_position = Vector2.ZERO
	_nodes[1].global_position = Vector2(100.0, 0.0)
	_nodes[2].global_position = Vector2(200.0, 0.0)
	_nodes[3].global_position = Vector2(300.0, 0.0)
	_nodes[4].global_position = Vector2(400.0, 0.0)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _resolve_ranged_at(target: SkillNode) -> AttackOutcome:
	var plan := RangedAttackPlan.new()
	plan.attacker = _ai
	plan.target = target
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return plan.resolve()


## take_damage() runs its `amount` argument back through Mitigation.apply
## (armor/floor) unless the source IS a DamageInstance of TRUE type — this is
## how fixtures set an exact HP without also modelling armor twice.
func _true_damage(target: SkillNode, amount: float) -> void:
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.amount = amount
	target.take_damage(amount, dmg)


# ---------------------------------------------------------------------------
# expected_damage
# ---------------------------------------------------------------------------

func test_expected_damage_matches_mitigation_of_each_hit() -> void:
	var outcome := _resolve_ranged_at(_nodes[2])

	var expected := 0.0
	for hit in outcome.hits:
		expected += Mitigation.apply(hit, hit.target)

	assert_almost_eq(AiCombatScorer.expected_damage(outcome), expected, 0.001)
	assert_gt(outcome.hits.size(), 0, "fixture leaf should land at least one hit")


func test_expected_damage_ignores_hits_on_blocker_owned_nodes() -> void:
	# Damage that lands on scenery must not bank EV — otherwise the AI still
	# steers into blockers via splash even though they're off its target list.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[2])
	blocker.core_location = _nodes[2]
	var outcome := _resolve_ranged_at(_nodes[2])

	assert_gt(AiCombatScorer.expected_damage(outcome), 0.0, "raw sum still counts it")
	assert_eq(AiCombatScorer.expected_damage(outcome, _ai), 0.0,
			"attacker-scoped sum drops the blocker hit")


func test_expected_damage_counts_a_blocker_hit_for_a_growth_capped_attacker() -> void:
	# #604: the unlock has to reach the SWING VALUATION too, not just the target
	# list — a candidate the AI is allowed to pick but scores 0 EV for would
	# only ever win on a kill bonus, i.e. cores it can one-shot.
	# On a node BORDERING the AI's leaf — the unlock covers the wall, not every
	# core on the board (an entity capped by its own allies has no door).
	var walled := _SKILL_NODE_SCENE.instantiate() as SkillNode
	walled.name = "Walled"
	_graph.skill_nodes_container.add_child(walled)
	_add_edge(_nodes[1], walled)
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, walled)
	blocker.core_location = walled
	var outcome := _resolve_ranged_at(walled)
	_ai.ai_growth_capped = true

	assert_almost_eq(AiCombatScorer.expected_damage(outcome, _ai),
			AiCombatScorer.expected_damage(outcome), 0.001,
			"a capped attacker banks the same EV it would on any hostile")


func test_expected_damage_still_counts_a_real_hostile() -> void:
	var outcome := _resolve_ranged_at(_nodes[2])

	assert_almost_eq(AiCombatScorer.expected_damage(outcome, _ai),
			AiCombatScorer.expected_damage(outcome), 0.001)


# ---------------------------------------------------------------------------
# score — breakout bonus (#604)
# ---------------------------------------------------------------------------

func test_no_breakout_bonus_for_an_attacker_that_can_still_grow() -> void:
	# _nodes[2] is the hostile CORE, adjacent to nothing of the AI's; and the
	# AI is not capped. Both halves have to hold for the bonus.
	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED,
			_resolve_ranged_at(_nodes[2]), _nodes[2], _ai, 0)

	assert_eq(c.breakout_bonus, 0.0)


func test_breakout_bonus_only_for_a_target_bordering_the_capped_attackers_land() -> void:
	# Hang a hostile-owned node off the AI's own leaf: depleting it force-
	# deallocates it, so it lands in the frontier next pass. That is the door.
	var door := _SKILL_NODE_SCENE.instantiate() as SkillNode
	door.name = "Door"
	_graph.add_skill_node(door)
	_graph.add_edge(_nodes[1], door)
	await get_tree().process_frame
	_alloc.force_allocate(_hostile, door)
	_ai.ai_growth_capped = true

	var at_door := AiCombatScorer.score(BattleSystem.AttackMode.RANGED,
			_resolve_ranged_at(door), door, _ai, 0)
	var far := AiCombatScorer.score(BattleSystem.AttackMode.RANGED,
			_resolve_ranged_at(_nodes[2]), _nodes[2], _ai, 0)

	assert_gt(at_door.breakout_bonus, 0.0, "the bordering node is a way out")
	assert_eq(far.breakout_bonus, 0.0, "a node bordering nothing of mine is not")
	assert_gt(at_door.total, far.total, "and the door has to win on total, not just carry a term")


# ---------------------------------------------------------------------------
# score — kill bonus
# ---------------------------------------------------------------------------

func test_kill_bonus_set_when_expected_damage_meets_target_hp() -> void:
	# Chip the target down to exactly the fixture leaf's expected output.
	var outcome := _resolve_ranged_at(_nodes[2])
	var ev := AiCombatScorer.expected_damage(outcome)
	_true_damage(_nodes[2], _nodes[2].get_current_hp() - ev)
	assert_almost_eq(_nodes[2].get_current_hp(), ev, 0.01)

	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 0)

	assert_true(c.is_kill, "expected damage meeting current HP should read as a kill")
	assert_gt(c.kill_bonus, 0.0)


func test_no_kill_bonus_when_target_survives() -> void:
	# Target is at full HP by fixture default; a single leaf's output falls short.
	var outcome := _resolve_ranged_at(_nodes[2])
	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 0)

	assert_false(c.is_kill)
	assert_eq(c.kill_bonus, 0.0)


# ---------------------------------------------------------------------------
# score — tier gating
# ---------------------------------------------------------------------------

func test_tier_zero_zeroes_cut_vertex_weak_and_risk_terms() -> void:
	_hostile.stat_board.armor.base_value = -10.0 # would otherwise score enemy_weak_bonus
	var outcome := _resolve_ranged_at(_nodes[3]) # H1: cut vertex of hostile's territory

	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[3], _ai, 0, 3)

	assert_eq(c.cut_vertex_bonus, 0.0)
	assert_eq(c.enemy_weak_bonus, 0.0)
	assert_eq(c.self_shape_risk, 0.0)


func test_tier_one_scores_cut_vertex_bonus_for_enemy_cut_vertex() -> void:
	# H0 (core) - H1 - H2: depleting H1 islands H2 from the hostile's core ->
	# H1 is the cut vertex. H0 (core, excluded by definition) and H2 (a leaf,
	# islands nobody) are not.
	var outcome := _resolve_ranged_at(_nodes[3])

	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[3], _ai, 1)

	assert_gt(c.cut_vertex_bonus, 0.0, "H1 islands H2 if depleted -> cut vertex")


func test_tier_one_scores_enemy_weak_bonus_for_low_armor_target() -> void:
	_hostile.stat_board.armor.base_value = -10.0
	var outcome := _resolve_ranged_at(_nodes[2])

	var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 1)

	assert_gt(c.enemy_weak_bonus, 0.0)


func test_shape_risk_tier_gated_prefers_safer_candidate_at_equal_ev() -> void:
	var outcome := _resolve_ranged_at(_nodes[2])

	var risky := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 1, 5)
	var safe := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 1, 0)

	assert_gt(safe.total, risky.total, "equal EV, fewer thinned nodes must score higher at tier > 0")

	var naive_risky := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 0, 5)
	var naive_safe := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, _nodes[2], _ai, 0, 0)
	assert_almost_eq(naive_risky.total, naive_safe.total, 0.001,
			"ai_tier = 0 must not penalize thin-shape reach candidates")


# ---------------------------------------------------------------------------
# pick_best
# ---------------------------------------------------------------------------

func test_pick_best_returns_highest_total() -> void:
	var low := AiCombatScorer.ScoredCandidate.new()
	low.total = 1.0
	var high := AiCombatScorer.ScoredCandidate.new()
	high.total = 99.0
	var mid := AiCombatScorer.ScoredCandidate.new()
	mid.total = 50.0

	var best := AiCombatScorer.pick_best([low, high, mid])

	assert_eq(best, high)


func test_pick_best_of_empty_array_is_null() -> void:
	var empty: Array[AiCombatScorer.ScoredCandidate] = []
	assert_null(AiCombatScorer.pick_best(empty))


# ---------------------------------------------------------------------------
# score_frontier — near-miss tactical enable vs. plain directional
# ---------------------------------------------------------------------------

func test_score_frontier_prefers_near_miss_enabling_candidate_over_closer_one() -> void:
	# H0 pushed out of every existing leaf's reach, then chipped to exactly
	# one shot's worth of HP — a near miss regardless of current reach, since
	# ANY leaf that reaches it now nets a kill.
	_nodes[2].global_position = Vector2(600.0, 0.0)
	var per_shot: float = float(_ai.stat_board.ranged_damage.value)
	_true_damage(_nodes[2], _nodes[2].get_current_hp() - per_shot)

	# H2 stays full-health and close to the AI's territory — a distractor a
	# purely-directional heuristic would wrongly prefer.
	_nodes[4].global_position = Vector2(120.0, 0.0)

	var far_enabler := _SKILL_NODE_SCENE.instantiate() as SkillNode
	far_enabler.name = "FarEnabler"
	_graph.skill_nodes_container.add_child(far_enabler)
	_add_edge(_nodes[1], far_enabler)
	far_enabler.global_position = Vector2(250.0, 0.0) # within `range` (400) of H0

	var near_other := _SKILL_NODE_SCENE.instantiate() as SkillNode
	near_other.name = "NearOther"
	_graph.skill_nodes_container.add_child(near_other)
	_add_edge(_nodes[1], near_other)
	near_other.global_position = Vector2(115.0, 0.0) # next to H2, out of range of H0

	var visible: Array[SkillNode] = [_nodes[2], _nodes[4]]
	var near_miss := AiCombatScorer.near_miss_targets(_ai, visible)
	var enabling_score := AiCombatScorer.score_frontier(far_enabler, _ai, visible, near_miss)
	var non_enabling_score := AiCombatScorer.score_frontier(near_other, _ai, visible, near_miss)

	assert_gt(enabling_score, non_enabling_score,
			"a frontier pick that lands a near-miss kill must beat a merely-closer one")


func test_score_frontier_falls_back_to_directional_without_a_near_miss() -> void:
	var near := _SKILL_NODE_SCENE.instantiate() as SkillNode
	near.name = "Near"
	_graph.skill_nodes_container.add_child(near)
	_add_edge(_nodes[1], near)
	near.global_position = Vector2(150.0, 0.0)

	var far := _SKILL_NODE_SCENE.instantiate() as SkillNode
	far.name = "Far"
	_graph.skill_nodes_container.add_child(far)
	_add_edge(_nodes[1], far)
	far.global_position = Vector2(150.0, 5000.0)

	var visible: Array[SkillNode] = [_nodes[2]]
	var near_miss := AiCombatScorer.near_miss_targets(_ai, visible)
	assert_true(near_miss.is_empty(), "H0 is at full HP — nothing to enable")
	assert_gt(AiCombatScorer.score_frontier(near, _ai, visible, near_miss),
			AiCombatScorer.score_frontier(far, _ai, visible, near_miss),
			"with no near-miss to enable, closer-to-the-enemy wins")


func test_near_miss_targets_excludes_targets_already_lethal_or_full_health() -> void:
	# H0 at full HP, out of `range` for the fixture's single leaf -> current
	# ranged EV against it is 0, and 0 < full HP by more than one shot: not a
	# near miss.
	var visible: Array[SkillNode] = [_nodes[2]]
	assert_true(AiCombatScorer.near_miss_targets(_ai, visible).is_empty())
