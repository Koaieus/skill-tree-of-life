extends GutTest

## #692 follow-up — swing DIRECTION is part of a melee candidate's identity.
##
## A blade sweeps a full TAU either way, so direction never changes what it can
## REACH. It changes two other things:
##
##   - the ORDER of contact. A defensive spike pop kills the vertex and severs
##     everything downstream from that instant ([BladePopResolver]), so one
##     direction can bank a hit the other pops before ever arriving at.
##   - the PATH. The blade is a PBD chain that lags its driver, so reversing
##     the sweep is not the same circle traversed backwards.
##
## Every AI swing used to run at [member MeleeAttackPlan.swing_cw]'s `false`
## default, so half the move set was unreachable.
##
## Deliberately its own fixture rather than a case bolted onto
## `test_ai_scoring_spike_pop.gd`: this geometry is angular, and that file's
## nodes sit at radii close enough to the sweep circle to pop the arm at t~=0
## from the side, in BOTH directions, which silently makes the test vacuous.
##
## [b]On `best.swing_cw` (#822, investigated 2026-09-10): deliberately NOT
## asserted.[/b] Every owned node is a candidate PIVOT
## ([AiBladeRollout]'s own class doc, `ai_blade_rollout.gd:13`), and the owner
## ruled the attacker's own core is a legitimate blade member too — [i]"sure it
## can, its an owned node, AND MORE. possibly later we'd even add bonuses on
## copy to blade node"[/i] (Koaieus, 2026-09-10, on #822). This fixture only
## ever allocates the attacker two nodes, so "Arm" is ALSO a viable pivot —
## sweeping "Pivot" (the attacker's own core, per [member Entity.core_location]
## below) as its one member — and that swing genuinely lands `PlainBehind` for
## real damage before it ever meets the spike, legitimately outscoring the
## canonical `pivot=Pivot, members=[Arm], cw=true` swing below.
## `gather_melee_candidates`' overall winner therefore has `swing_cw == false`
## correctly: the rollout found a better attack, not a fabricated one — a
## drone verified this by re-resolving both candidates
## `gather_melee_candidates` returns through a fresh, independent
## `MeleeAttackPlan.resolve()` and got the identical `ev` back both times.
## What #822 is actually about — a POPPED contact fabricating EV — is asserted
## directly below, candidate-to-candidate on `pivot=Pivot`'s own two
## directions, instead of through the overall winner.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _R := 200.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _arm: SkillNode
var _spiked_ahead: SkillNode
var _plain_behind: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _polar(deg: float) -> Vector2:
	return Vector2(_R, 0.0).rotated(deg_to_rad(deg))


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)
	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var camp := Faction.new()
	camp.id = &"swing_direction_enemy"
	_defender.faction = camp
	_graph.add_child(_defender)

	# Arm starts at angle 0. The spike is 40 degrees CCW of it, the plain node
	# 40 degrees CW — so each direction meets a different one first.
	_pivot = _spawn("Pivot", Vector2.ZERO)
	_arm = _spawn("Arm", _polar(0.0))
	_graph.add_edge(_pivot, _arm)
	_spiked_ahead = _spawn("SpikedAhead", _polar(40.0))
	_plain_behind = _spawn("PlainBehind", _polar(-40.0))

	await get_tree().process_frame
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _arm)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _spiked_ahead)
	_alloc.force_allocate(_defender, _plain_behind)
	_defender.core_location = _plain_behind

	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	spike.local_modifiers = [mod]
	_spiked_ahead.add_child(spike)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _ev(cw: bool) -> float:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_arm]
	plan.swing_cw = cw
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return AiCombatScorer.expected_damage(plan.resolve(), _attacker)


func test_direction_changes_what_a_swing_banks() -> void:
	assert_eq(_ev(false), 0.0,
			"CCW meets the spike first, pops, and never reaches the plain node")
	assert_gt(_ev(true), 0.0,
			"CW takes the plain node before the spike stops it")


## The regression that matters: the rollout has to OFFER both directions, or
## the winning swing above is not in the candidate set at all.
func test_the_rollout_proposes_both_directions() -> void:
	var adjacency := AiBladeRollout._owned_adjacency(_attacker)
	var pivots := AiBladeRollout._prune_pivots(
			adjacency, [_plain_behind.global_position])
	var proposals := AiBladeRollout._propose_blade_selections(
			pivots, adjacency, _plain_behind.global_position)

	assert_gt(proposals.size(), 0, "the fixture must produce proposals at all")
	var directions: Dictionary = {}
	for p in proposals:
		directions[p[2]] = true
	assert_true(directions.has(false), "CCW is proposed")
	assert_true(directions.has(true), "CW is proposed")


## End to end: the direction the rollout scores must be the direction it hands
## back, so the launch path can carry it onto the plan.
func test_the_winning_candidate_reports_its_direction() -> void:
	var visible: Array[SkillNode] = [_spiked_ahead, _plain_behind]
	var candidates := AiBladeRollout.gather_melee_candidates(_attacker, visible, 0)

	assert_gt(candidates.size(), 0, "the rollout must find a melee candidate")
	var best := AiCombatScorer.pick_best(candidates)
	assert_gt(best.ev, 0.0,
			"the best swing banks real damage — CCW-only, every candidate scores 0")
	# `best.swing_cw` is NOT asserted here — see the class doc's "On
	# `best.swing_cw`" note for why the overall winner is the wrong thing to
	# pin, and the two tests below for the claim #822 actually cares about.


## #822: the popped candidate must score exactly what it banks — nothing —
## compared candidate-to-candidate against its own CW twin, not through
## `gather_melee_candidates`' overall winner (which a different, legitimate
## pivot wins outright — see the class doc).
func test_the_canonical_popped_swing_scores_zero_and_loses_to_its_cw_twin() -> void:
	var visible: Array[SkillNode] = [_spiked_ahead, _plain_behind]
	var popped := AiBladeRollout._resolve_and_score(
			_attacker, _pivot, [_arm], false, visible, 0)
	assert_null(popped,
			"pivot=Pivot/members=[Arm]/CCW meets the spike first and banks nothing " +
			"— _primary_target must find no landed hit to score")

	var cw := AiBladeRollout._resolve_and_score(
			_attacker, _pivot, [_arm], true, visible, 0)
	assert_not_null(cw, "pivot=Pivot/members=[Arm]/CW lands PlainBehind before the spike")
	assert_gt(cw.ev, 0.0, "and its ev is the real damage it banked")
	assert_almost_eq(cw.ev, _ev(true), 0.001,
			"the candidate's ev must equal a fresh, independent resolve of the same plan")
	# The comparison the old best.swing_cw assertion stood in for: on THIS
	# pivot/members pair, CW's positive ev beats CCW's null/0.0 on merit —
	# never on tie-break order, and never by widening a margin.


## The direct regression #822 asks for: a candidate's ev can never silently
## drift from a fresh plan.resolve() of the identical (pivot, members, cw) —
## for a POPPED candidate specifically, since a popped contact is where the
## rollout's accounting was suspected to fabricate damage. Both candidates
## this fixture's rollout actually returns pop SpikedAhead (after already
## landing PlainBehind), so both exercise the popped path.
func test_rollout_ev_matches_a_fresh_resolve_for_a_popped_candidate() -> void:
	var visible: Array[SkillNode] = [_spiked_ahead, _plain_behind]
	var candidates := AiBladeRollout.gather_melee_candidates(_attacker, visible, 0)
	assert_gt(candidates.size(), 0, "the rollout must find a melee candidate")
	for c in candidates:
		assert_gt(c.outcome.popped_nodes, 0,
				"this fixture's candidates are expected to pop SpikedAhead")
		var direct_plan := MeleeAttackPlan.new()
		direct_plan.attacker = _attacker
		direct_plan.source = c.source_node
		direct_plan.blade_nodes = c.blade_nodes
		direct_plan.swing_cw = c.swing_cw
		var direct_ev := AiCombatScorer.expected_damage(direct_plan.resolve(), _attacker)
		assert_almost_eq(c.ev, direct_ev, 0.001,
				"pivot=%s cw=%s: rollout ev must match a fresh independent resolve" % [
						c.source_node.name, c.swing_cw])
