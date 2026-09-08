extends GutTest

## #186 acceptance 1/2/6 end to end: a real swing, real physics, a real spiked
## defender. The mid-spine vertex pops, the tip is severed, and the tip goes on
## to hurt something — with its landings in the SAME AttackOutcome the driven
## swing's are in, which is what makes a peer replay them (acceptance 6) rather
## than re-derive a solver it does not run.
##
## Severance is by VERTEX POP, per ADR 0005 — never by driving `removed_edges`
## through the spike gate.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _spiked: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## A fixed spikes cap, bypassing SpikeRingAddon's stake-scaled curve — same
## technique test_spike_pop_budget.gd uses.
func _set_spikes_cap(node: SkillNode, cap: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spikes"
	mod.operation = StatModifier.Operation.SET
	mod.value = cap
	node.add_local_modifier(mod)


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
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_attacker.turns_taken = 1
	_graph.add_child(_attacker)
	_tm.current_entity = _attacker

	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var enemy_camp := Faction.new()
	enemy_camp.id = &"free_flight_live_enemy"
	_defender.faction = enemy_camp
	_graph.add_child(_defender)

	# A single spine, the catastrophic case: pivot - mid - tip.
	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(150, 0))
	_tip = _spawn("Tip", Vector2(300, 0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)

	# On the MID vertex's own orbit (radius 150), a quarter turn round, so the
	# pop happens well into the sweep and the tip is moving fast when it lets go.
	_spiked = _spawn("Spiked", Vector2(0, 150))

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _spiked)
	_defender.core_location = _spiked
	# EXACTLY one spike: the driven mid vertex spends it popping, so the
	# defender has nothing left when the coasting tip sails back over it. With
	# a budget to spare the spiked node pops the fragment too — correct
	# behaviour, and it would end the flight before it reaches anything else.
	_set_spikes_cap(_spiked, 1.0)
	# A real blade_damage coefficient on the vertex that gets severed — the
	# wielder's own baseline is 0, so without this the fragment would fly and
	# hit and land exactly 0, which proves nothing about acceptance 2.
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 8.0
	_tip.add_local_modifier(sharp)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _plan() -> MeleeAttackPlan:
	# Fresh plan every time: MELEE selection is a TOGGLE, so re-clicking the
	# same nodes on a surviving plan would deselect them.
	_bs.request_attack_mode(BattleSystem.AttackMode.NONE)
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_mid)
	plan._on_node_left_clicked(_tip)
	assert_true(plan.is_valid(), "fixture plan must be valid before resolving")
	assert_eq(plan.blade_nodes.size(), 2, "fixture: a pivot plus mid plus tip")
	return plan


func test_the_pop_severs_the_tip_and_the_tip_flies_on() -> void:
	var plan := _plan()
	plan.resolve()

	assert_eq(plan.last_pops.fragments.size(), 1,
			"the mid vertex popped and severed exactly one fragment")
	assert_eq(plan.last_free_flights.size(), 1, "and that fragment flew")

	var flight: BladeFreeFlight.Flight = plan.last_free_flights[0]
	assert_gt(flight.birth_t, 0.0, "severed mid-sweep, not at t=0")
	assert_lt(flight.birth_t, MeleeAttackPlan.SWING_DURATION,
			"with swing left to coast through")
	assert_true(flight.state.is_unpinned, "it flew as a free body")

	var start: Vector2 = flight.trajectory.samples[0][0]
	var end: Vector2 = flight.trajectory.samples[flight.trajectory.samples.size() - 1][0]
	assert_gt(start.distance_to(end), 100.0,
			"it kept its momentum instead of vanishing where it was cut")


## Acceptance 2 + 6: the coasting tip damages what it travels through, and that
## landing is in the outcome the record is captured from.
func test_the_coasting_tip_damages_what_it_travels_through() -> void:
	# Pass 1: learn where the tip actually goes. Nothing about the geometry of a
	# free coast is predictable enough to hand-author a target position, so the
	# victim is placed ON the recorded flight path.
	var scout := _plan()
	scout.resolve()
	assert_eq(scout.last_free_flights.size(), 1, "fixture: the tip must be severed")
	var path: BladeTrajectory = scout.last_free_flights[0].trajectory
	var mid_sample: int = int(path.samples.size() * 0.6)
	var victim_pos: Vector2 = path.samples[mid_sample][0]

	var victim := _spawn("Victim", victim_pos)
	await get_tree().process_frame
	_alloc.force_allocate(_defender, victim)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Pass 2: the same swing, now with something in the fragment's way. The
	# scout pass ran against a shadow, so the defender's spike is still unspent.
	var hp_before := victim.get_current_hp()
	var plan := _plan()
	# AGAINST THE LIVE WORLD deliberately: `resolve()` computes on a shadow (as
	# the authority does before replaying its own record), so the real node's HP
	# would be untouched and this test would be asserting nothing.
	var outcome := plan.resolve_against(CombatWorld.live())

	assert_eq(plan.last_free_flights.size(), 1, "the tip is severed again")
	var birth: float = plan.last_free_flights[0].birth_t
	var free_hits := 0
	for hit in outcome.hits:
		if hit.target != victim:
			continue
		if hit.structural_key * MeleeAttackPlan.SWING_DURATION <= birth:
			continue
		# `hp_before > hp_after` is what makes this a LANDING rather than merely
		# a candidate: the driven tip is dead after `birth`, so its own refused
		# events would otherwise satisfy a target-and-time filter alone.
		if hit.hp_before > hit.hp_after:
			free_hits += 1
	assert_gt(free_hits, 0,
			"the fragment's landing rode the SAME outcome — which is what the record captures")
	assert_lt(victim.get_current_hp(), hp_before,
			"a handle-less blade is still lethal where it travels")
