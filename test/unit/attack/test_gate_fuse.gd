extends GutTest

## The melee timed gate fuse (#1209, amendment: one fuse per gate). A fuse is
## plan data resolved with the swing on the shadow world: at its sample the
## blade's copy of the gate edge parts (free flight), the real gate flips with
## its cascade as a timed outcome entry, and a peer replays the host-stamped
## stranded set through the same AllocationSystem path ToggleGatesCommand uses.
##
## Board, all owned by the attacker, core = Pivot:
##   Pivot – B1 =G1= B2 – B3        (G1 an open gate on B1–B2)
##   Pivot – C1 =G2= C2             (G2 an open gate on C1–C2)
## `Frozen` belongs to another entity; gate GF on C2–Frozen is not toggleable.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPACING := 150.0

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _attacker: Entity
var _other: Entity
var _n: Dictionary = {}
var _g1: Gate
var _g2: Gate
var _gf: Gate


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	_n[nm] = sn
	return sn


func _make_entity() -> Entity:
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


func before_each() -> void:
	_n = {}
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_alloc.turn_manager = _tm

	_attacker = _make_entity()
	_attacker.stat_board.blade_size.base_value = 5.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_tm.start_turn(_attacker)
	_other = _make_entity()

	_spawn("Pivot", Vector2.ZERO)
	_spawn("B1", Vector2(_SPACING, 0.0))
	_spawn("B2", Vector2(_SPACING * 2.0, 0.0))
	_spawn("B3", Vector2(_SPACING * 3.0, 0.0))
	_spawn("C1", Vector2(0.0, _SPACING))
	_spawn("C2", Vector2(0.0, _SPACING * 2.0))
	_spawn("Frozen", Vector2(0.0, _SPACING * 3.0))
	_graph.add_edge(_n["Pivot"], _n["B1"])
	_graph.add_edge(_n["B2"], _n["B3"])
	_graph.add_edge(_n["Pivot"], _n["C1"])
	_g1 = _graph.add_gate(_n["B1"], _n["B2"], true)
	_g2 = _graph.add_gate(_n["C1"], _n["C2"], true)
	_gf = _graph.add_gate(_n["C2"], _n["Frozen"], true)

	await get_tree().process_frame
	await get_tree().physics_frame

	for id in ["Pivot", "B1", "B2", "B3", "C1", "C2"]:
		_alloc.force_allocate(_attacker, _n[id])
	_attacker.core_location = _n["Pivot"]
	_alloc.force_allocate(_other, _n["Frozen"])
	_other.core_location = _n["Frozen"]


func _plan(members: Array[String]) -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _n["Pivot"]
	var blade: Array[SkillNode] = []
	for id in members:
		blade.append(_n[id])
	plan.blade_nodes = blade
	return plan


## The blade edge index for the pair a–b, in [param state]'s own edge list.
func _edge_idx(plan: MeleeAttackPlan, state: BladeState, a: String, b: String) -> int:
	var selection: Array[SkillNode] = [plan.source]
	selection.append_array(plan.blade_nodes)
	var ia := selection.find(_n[a])
	var ib := selection.find(_n[b])
	for i in state.edges.size():
		var e := state.edges[i]
		if (e.x == ia and e.y == ib) or (e.x == ib and e.y == ia):
			return i
	return -1


func _fuse_t(frac: float) -> float:
	var total := int(ceil(MeleeAttackPlan.SWING_DURATION / BladeSim.DEFAULT_DT))
	var step := clampi(int(round(frac * float(total))), 1, total)
	return float(step) * BladeSim.DEFAULT_DT


func _flips(outcome: AttackOutcome) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit.kind == HitInstance.Kind.GATE_FLIP:
			out.append(hit)
	return out


func _dealloc_names(hit: HitInstance) -> Array[String]:
	var out: Array[String] = []
	for e in hit.deallocations:
		out.append(String(e.node.name) if e.node != null else "<null>")
	out.sort()
	return out


## Resolve on a shadow, capture the record, free the shadow — the authority's
## compute half, as BattleSystem._compute_record runs it.
func _resolve(plan: MeleeAttackPlan) -> Array:
	var world := CombatWorld.shadow()
	var outcome := plan.resolve_against(world)
	var record := AttackRecord.capture(outcome, _graph)
	world.free_shadow()
	return [outcome, record]


# ── acceptance 1 + 2: one fuse at 0.5 ────────────────────────────────────────

func test_a_fuse_severs_the_blade_edge_and_flips_the_real_gate_on_replay() -> void:
	var plan := _plan(["B1", "B2", "B3"])
	assert_true(plan.is_valid(), "fixture: the plan must be valid")
	assert_true(plan.set_gate_fuse(_g1, 0.5), "G1 is fusable")
	var edge := _edge_idx(plan, plan.build_blade_state(), "B1", "B2")
	assert_gt(edge, -1, "fixture: B1–B2 is a blade edge")
	# Acceptance 2: the plan-time warning is the preview on the world at t —
	# nothing lands before t on this board, so that is the world as it stands.
	var warned := _alloc.gate_flip_cascade([_g1] as Array[Gate], _attacker)

	var res := _resolve(plan)
	var outcome: AttackOutcome = res[0]
	var record: Dictionary = res[1]

	var t := _fuse_t(0.5)
	assert_true(plan.last_pops.severed_at.has(edge), "the fuse severs B1–B2 on the blade")
	assert_almost_eq(float(plan.last_pops.severed_at.get(edge, -1.0)), t, 1e-6,
			"at the fuse sample")
	var coasting := {}
	for sev in plan.last_pops.severances:
		for v in sev.vertices:
			coasting[v] = true
	assert_true(coasting.has(2) and coasting.has(3), "B2 and B3 fly free past the cut")

	var flips := _flips(outcome)
	assert_eq(flips.size(), 1, "one gate-flip entry")
	if flips.is_empty():
		return
	assert_almost_eq(flips[0].structural_key, t / MeleeAttackPlan.SWING_DURATION, 1e-6,
			"the entry sits at the fuse t")
	assert_eq(_dealloc_names(flips[0]), ["B2", "B3"] as Array[String],
			"the host stamps what the flip strands")
	var warned_names: Array[String] = []
	for n in warned:
		warned_names.append(String(n.name))
	warned_names.sort()
	assert_eq(_dealloc_names(flips[0]), warned_names,
			"acceptance 2: the stamped set equals gate_flip_cascade at t")
	assert_true(_g1.is_open(), "resolve never touches the real world")

	var rebuilt := AttackRecord.rebuild(record, _graph)
	@warning_ignore("redundant_await")
	await OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	assert_false(_g1.is_open(), "the real gate flipped on replay")
	assert_eq(_n["B1"].owned_by, _attacker, "B1 stays")
	assert_null(_n["B2"].owned_by, "B2 stranded and deallocated")
	assert_null(_n["B3"].owned_by, "B3 stranded and deallocated")
	assert_true(_g2.is_open(), "an unfused gate is never touched")


# ── amendment: two gates fused at 0.3 and 0.6 ────────────────────────────────

func test_two_fuses_sever_twice_and_flip_in_time_order() -> void:
	var plan := _plan(["B1", "B2", "C1", "C2"])
	assert_true(plan.set_gate_fuse(_g1, 0.3), "G1 is fusable")
	assert_true(plan.set_gate_fuse(_g2, 0.6), "G2 is fusable")
	var state := plan.build_blade_state()
	var e1 := _edge_idx(plan, state, "B1", "B2")
	var e2 := _edge_idx(plan, state, "C1", "C2")

	var res := _resolve(plan)
	var outcome: AttackOutcome = res[0]
	var record: Dictionary = res[1]

	assert_almost_eq(float(plan.last_pops.severed_at.get(e1, -1.0)), _fuse_t(0.3), 1e-6,
			"G1's blade edge parts at 0.3")
	assert_almost_eq(float(plan.last_pops.severed_at.get(e2, -1.0)), _fuse_t(0.6), 1e-6,
			"G2's blade edge parts at 0.6")
	var flips := _flips(outcome)
	assert_eq(flips.size(), 2, "one flip entry per distinct t")
	if flips.size() != 2:
		return
	assert_lt(flips[0].schedule_index, flips[1].schedule_index, "in time order")
	assert_eq(_dealloc_names(flips[0]), ["B2", "B3"] as Array[String], "t=0.3 strands B2, B3")
	assert_eq(_dealloc_names(flips[1]), ["C2"] as Array[String], "t=0.6 strands C2")

	var rebuilt := AttackRecord.rebuild(record, _graph)
	@warning_ignore("redundant_await")
	await OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	assert_false(_g1.is_open(), "G1 flipped on replay")
	assert_false(_g2.is_open(), "G2 flipped on replay")
	for id in ["B2", "B3", "C2"]:
		assert_null(_n[id].owned_by, "%s deallocated on replay" % id)
	for id in ["Pivot", "B1", "C1"]:
		assert_eq(_n[id].owned_by, _attacker, "%s stays" % id)


# ── acceptance 4: nothing toggleable is a no-op, not an error ────────────────

func test_a_fuse_on_a_gate_the_attacker_cannot_toggle_is_refused() -> void:
	var plan := _plan(["C1", "C2"])
	assert_false(plan.set_gate_fuse(_gf, 0.5), "a frozen gate is not fusable")
	assert_true(plan.gate_fuses().is_empty(), "nothing armed")


func test_a_fuse_whose_gate_became_unfusable_resolves_to_no_entry() -> void:
	var plan := _plan(["B1", "B2", "B3"])
	assert_true(plan.set_gate_fuse(_g1, 0.5), "G1 is fusable now")
	_graph.flip_gates([_g1] as Array[Gate])
	assert_false(_g1.is_open(), "fixture: G1 closed after arming")
	var res := _resolve(plan)
	assert_eq(_flips(res[0]).size(), 0, "no flip entry, no error")


# ── plan API for #1210 + wire ───────────────────────────────────────────────

func test_the_fuse_setters_invalidate_the_prediction_and_expose_the_warning() -> void:
	var plan := _plan(["B1", "B2", "B3"])
	plan.refresh_prediction()
	assert_not_null(plan.prediction(), "fixture: a prediction is cached")
	plan.set_gate_fuse(_g1, 0.5)
	assert_null(plan.prediction(), "arming a fuse invalidates the prediction")
	plan.refresh_prediction()
	var names: Array[String] = []
	for n in plan.prediction().predicted_stranded():
		names.append(String(n.name))
	names.sort()
	assert_eq(names, ["B2", "B3"] as Array[String], "the prediction carries the stranded union")
	assert_eq(plan.hot_window_duration(), MeleeAttackPlan.SWING_DURATION)
	plan.clear_gate_fuse(_g1)
	assert_null(plan.prediction(), "clearing invalidates too")


func test_fuses_ride_the_plan_dict_and_are_absent_when_unarmed() -> void:
	var plan := _plan(["B1", "B2", "B3"])
	assert_false(plan.to_dict(_graph).has("fuses"), "an unarmed plan's dict is unchanged")
	plan.set_gate_fuse(_g1, 0.25)
	var back := MeleeAttackPlan.from_dict(plan.to_dict(_graph), _graph)
	assert_eq(back.gate_fuse(_g1), 0.25, "the fuse survives the wire")

