extends GutTest

## #474 characterization test — captures TODAY's live-swing melee behaviour
## (a real BattleSystem.launch_attack() through a real MeleePreview, real
## physics scan) before the world-mutation-vs-VFX split refactor. Locks in
## the hit target set + amounts and the spike-pop count/target so the
## refactored synchronous apply can be checked against it byte-for-byte.
##
## One arm per scenario (not a multi-arm star) — a full swing sweeps a
## complete TAU circle, so a second arm would cross the SAME target's angle
## again later in its own rotation and double the event count. Isolating one
## arm per scenario keeps each characterization unambiguous.
##
## Positions coincide at t=0 (same trick as test_ai_blade_rollout.gd's
## test_gather_melee_candidates_scores_a_real_hit) so the outcome doesn't
## depend on physics-server sync timing.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _arm: SkillNode
var _target: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_preview = MeleePreview.new()
	add_child_autofree(_preview)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.melee_preview = _preview
	_preview.battle_system = _bs
	add_child(_bs)
	_preview._ready()

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 2.0
	_attacker.stat_board.action_points.set_base_ratcheted(2.0)
	_attacker.stat_board.action_points.current = 2.0
	_graph.add_child(_attacker)
	_tm.current_entity = _attacker

	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_defender)

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_arm = _spawn("Arm", Vector2(150, 0))
	_graph.add_edge(_pivot, _arm)

	_target = _spawn("Target", Vector2(150, 0))

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _arm)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _target)
	_defender.core_location = _target

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _arm_spike(power: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = power
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	spike.local_modifiers = [mod]
	_target.add_child(spike)


func _launch() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_arm)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	_bs.launch_attack()
	await _await_launch_settle()


func _await_launch_settle(max_ticks: int = 300) -> int:
	var ticks := 0
	while _bs.is_launching and ticks < max_ticks:
		await get_tree().process_frame
		ticks += 1
	return ticks


func test_live_swing_plain_hit_deals_damage() -> void:
	var hp_before := _target.get_current_hp()
	watch_signals(Events)

	await _launch()

	assert_signal_emit_count(Events, "skill_node_damaged", 1,
			"one contact against the coincident target")
	assert_signal_emit_count(Events, "blade_vertex_popped", 0,
			"an un-spiked target never pops the blade")
	assert_true(_target.get_current_hp() < hp_before,
			"the arm's contact must deal real damage")


## #502: every melee HitInstance carries its BladeHitEvent.t as arrival_time —
## it used to be hardcoded 0.0 for every mode but ranged.
func test_last_hits_stamp_arrival_time_from_the_event() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_arm)
	assert_true(plan.is_valid(), "fixture plan must be valid before resolving")

	var outcome := plan.resolve()
	assert_gt(outcome.hits.size(), 0, "the coincident target must produce a hit")
	var non_edge_ts: Array[float] = []
	for ev in plan.last_events:
		if not ev.is_edge_hit():
			non_edge_ts.append(ev.t)
	for i in plan.last_hits.size():
		assert_eq(plan.last_hits[i].arrival_time, non_edge_ts[i],
				"HitInstance.arrival_time mirrors the BladeHitEvent.t it came from")
	assert_gt(plan.last_hits[0].arrival_time, 0.0,
			"a real contact time, not the old hardcoded 0.0")


func test_live_swing_spike_pops_the_arm() -> void:
	_arm_spike(5.0)
	var hp_before := _target.get_current_hp()
	watch_signals(Events)

	await _launch()

	assert_signal_emit_count(Events, "blade_vertex_popped", 1,
			"exactly one spike pop for a single-arm blade")
	assert_eq(get_signal_parameters(Events, "blade_vertex_popped", 0)[0], _target,
			"the pop is recorded against the spiked target")
	# Characterizing today's actual outcome, whatever it is — the pop
	# resolver's "no damage to the popper" contract is asserted separately in
	# test_spike_pop.gd; this test's job is byte-for-byte parity across the
	# refactor, not re-litigating that contract.
	var hp_after := _target.get_current_hp()
	assert_almost_eq(hp_after, hp_before, 0.001,
			"today's live swing: the popping contact deals no damage")
