extends GutTest

## #982 — the one real-clock keeper for the staged melee wind-up (#559). The
## unit tier (`test/unit/attack/test_melee_staging.gd`) asserts the beat ORDER
## and the DURATIONS the tempo resolves to on `BeatClock.instant_clock()`;
## this file is the single "the clock really consumes that schedule" check
## (docs/domain/testing-tiers.md §1.4): `instant_mutation` stays false, the
## wind-up runs on a real tree timer, and the first hit must land strictly
## after the form beat ends. Order only — no pacing assert, generous budget.
##
## Fixture is the staging file's (one arm, one coincident hostile target, so
## the swing lands exactly one hit and "the first hit" is unambiguous).

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
	# The real clock — the point of this file.
	_bs.instant_mutation = false
	add_child(_bs)
	_preview._ready()

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 2.0
	_attacker.stat_board.action_points.base_value = 2.0
	_attacker.stat_board.action_points.current = 2.0
	_graph.entities_container.add_child(_attacker)
	_tm.start_turn(_attacker)

	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var enemy_camp := Faction.new()
	enemy_camp.id = &"keeper_enemy"
	_defender.faction = enemy_camp
	_graph.entities_container.add_child(_defender)

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


func test_the_first_hit_lands_strictly_after_the_form_beat_ends_on_the_real_clock() -> void:
	# The SHAPE is injected, not read off the authored `.tres` — authored
	# durations are the owner's to tune. Stretched past
	# [member PresentationTempo.swing_duration] on purpose: WITHOUT the staging
	# the first hit lands somewhere inside a 1.2 s swing, comfortably before the
	# 2.0 s bound, so a hit that satisfies this bound is one that waited.
	var tempo := PresentationTempo.new()
	tempo.melee_windup_pivot_focus = 0.6
	tempo.melee_windup_form_span = 1.4
	tempo.melee_windup_stamp_time = 0.0
	tempo.melee_windup_glow_ramp = 0.0
	tempo.melee_windup_flare = 0.0
	_bs.presentation_tempo = tempo
	var form_beat_end := tempo.windup_lead(BattleSystem.AttackMode.MELEE) + tempo.melee_windup_form_span
	assert_gt(form_beat_end, tempo.swing_duration,
			"the injected form beat must outlast the whole swing, or a hit "
			+ "landing late inside an unstaged swing would satisfy this vacuously")

	# Wall clock against a LOGICAL boundary, so it needs slop: the form beat
	# runs on a [BeatClock] tree timer, which fires on accumulated frame deltas
	# — landing at 1.9973 s against a 2.0 s bound is quantization, not a
	# staging failure (a zero-tolerance bound failed intermittently, 2026-09-10).
	# 50 ms cannot make it vacuous: an unstaged hit is 800 ms below the bound.
	var first_hit_at := [-1.0]
	var started_at := [0]
	var probe := func(_n: SkillNode, _amount: float, _src: Variant) -> void:
		if first_hit_at[0] < 0.0:
			first_hit_at[0] = float(Time.get_ticks_usec() - started_at[0]) / 1000000.0
	Events.skill_node_damaged.connect(probe)

	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_arm)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")

	started_at[0] = Time.get_ticks_usec()
	_bs.launch_attack()
	# Generous: the whole action is ~2 s of wind-up + a 1.2 s swing + a fade.
	await wait_until(func() -> bool: return not _bs.is_launching, 15.0)
	# `Events` is an autoload that outlives this test; the bus hook must go.
	Events.skill_node_damaged.disconnect(probe)

	assert_false(_bs.is_launching, "the launch settled inside the budget")
	assert_gt(first_hit_at[0], 0.0, "the fixture swing must land a hit at all")
	var slop := 0.05
	assert_gt(first_hit_at[0], form_beat_end - slop,
			"on the real clock the swing's first hit lands after the form beat "
			+ "ends (form beat ends at %.3fs, hit landed at %.3fs, slop %.3fs)"
			% [form_beat_end, first_hit_at[0], slop])


# --- #1041 (ADR 0027): the same clock, any mode's presenter -------------------

## A presenter that stages a dictated wind-up and draws nothing — what a
## ranged coordinator becomes once #1042 authors its picture.
class _StubPresenter:
	extends VFXCoordinator
	var lead: float = 0.0
	func play(_payload: Variant) -> void:
		pass
	func begin_windup(_plan: AttackPlan, _tempo: PresentationTempo) -> float:
		return lead


## An [AttackVFX] that mounts the stub instead of the real volley scene.
class _StubAttackVFX:
	extends AttackVFX
	var lead: float = 0.0
	func mount(_scene: PackedScene) -> VFXCoordinator:
		var coord := _StubPresenter.new()
		coord.lead = lead
		add_child(coord)
		return coord


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func test_a_ranged_first_hit_lands_after_the_presenters_windup_on_the_real_clock() -> void:
	# Acceptance 2 (#1041): `_apply_outcome` starts no earlier than the seconds
	# the presenter's `begin_windup` returned — melee's path, now for a
	# coordinator. The volley's own beats are zeroed so that WITHOUT the
	# staging the first hit would land at ~0 s; a hit that clears the 0.6 s
	# bound is one that waited on the wind-up.
	var vfx := _StubAttackVFX.new()
	vfx.lead = 0.6
	add_child_autofree(vfx)
	_bs.attack_vfx = vfx
	var tempo := PresentationTempo.new()
	tempo.volley_draw_time = 0.0
	tempo.volley_stagger_span = 0.0
	tempo.volley_flight_time = 0.0
	_bs.presentation_tempo = tempo
	assert_eq(tempo.windup_lead(BattleSystem.AttackMode.RANGED), 0.0,
			"the tempo authors no ranged lead — the wait below is the presenter's alone")
	_attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 10)
	_set_stat(_arm, &"range", 100.0)
	_set_stat(_arm, &"ranged_damage", 5.0)

	var first_hit_at := [-1.0]
	var started_at := [0]
	var probe := func(_n: SkillNode, _amount: float, _src: Variant) -> void:
		if first_hit_at[0] < 0.0:
			first_hit_at[0] = float(Time.get_ticks_usec() - started_at[0]) / 1000000.0
	Events.skill_node_damaged.connect(probe)

	_bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := _bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(_target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")

	started_at[0] = Time.get_ticks_usec()
	_bs.launch_attack()
	await wait_until(func() -> bool: return not _bs.is_launching, 15.0)
	Events.skill_node_damaged.disconnect(probe)

	assert_false(_bs.is_launching, "the launch settled inside the budget")
	assert_gt(first_hit_at[0], 0.0, "the fixture volley must land a hit at all")
	var slop := 0.05
	assert_gt(first_hit_at[0], 0.6 - slop,
			"the first hit waited out the presenter's 0.6 s wind-up "
			+ "(hit landed at %.3fs, slop %.3fs)" % [first_hit_at[0], slop])
