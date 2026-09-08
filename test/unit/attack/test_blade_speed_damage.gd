extends GutTest

## #779 — speed-scaled blade damage: damage = blade_damage x f(speed), where
## f(v) = 1 + (M-1)*v/(v+v_half), floored at 1.0. Characterization tests pin
## the SHAPE (monotonic, bounded by M, never below 1.0, f(0) == 1) per the
## issue's acceptance #4 — NEVER the tuned M / v_half values themselves,
## which stay the owner's to retune.
##
## See docs/domain/melee-blade-sim.md's "Speed-scaled damage" section and
## `.claude/rules/multiplayer-sync.md` / `.claude/rules/attack-timeline.md`
## for why this is safe under host-authoritative sync (acceptance #5, pinned
## below via a direct capture/rebuild round trip — the general "a record
## replays identically" claim end to end is already covered by
## test_attack_record_replay.gd's melee case and is not re-proven here).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


# ── The curve itself, isolated from the sim (acceptance #2, #3, #4) ─────────

func test_zero_speed_deals_exactly_the_base_coefficient() -> void:
	assert_eq(BladeState.speed_damage_multiplier(0.0, 2.0, 800.0), 1.0,
			"f(0) must be exactly 1 — a stationary vertex, never a penalty")


func test_multiplier_is_monotonic_increasing_in_speed() -> void:
	var prev := BladeState.speed_damage_multiplier(0.0, 3.0, 800.0)
	for v in [1.0, 50.0, 200.0, 800.0, 3000.0, 50000.0]:
		var f := BladeState.speed_damage_multiplier(v, 3.0, 800.0)
		assert_gt(f, prev, "f must rise as speed rises (v=%s)" % v)
		prev = f


func test_multiplier_never_drops_below_one() -> void:
	# Even a degenerate M < 1.0 (a misconfigured stat) must not turn into a
	# penalty — floored unconditionally, per the owner's post-filing pin.
	for v in [0.0, 10.0, 800.0, 999999.0]:
		assert_gte(BladeState.speed_damage_multiplier(v, 0.3, 800.0), 1.0,
				"floor must hold even under a sub-1.0 M")


func test_an_artificially_huge_speed_lands_at_the_configured_max_not_a_proportional_number() -> void:
	var m := 4.0
	var huge := BladeState.speed_damage_multiplier(1.0e9, m, 800.0)
	assert_almost_eq(huge, m, 0.001,
			"an astronomically large speed must land at M, not scale past it")
	var large := BladeState.speed_damage_multiplier(1.0e6, m, 800.0)
	assert_lte(large, m, "the multiplier must never exceed M")
	assert_gt(large, m - 0.01, "and must already sit close to M well before infinity")


func test_v_half_is_exactly_the_half_bonus_point() -> void:
	var m := 5.0
	var v_half := 800.0
	var f := BladeState.speed_damage_multiplier(v_half, m, v_half)
	assert_almost_eq(f, 1.0 + (m - 1.0) * 0.5, 0.0001,
			"f(v_half) must collect exactly half of (M-1)")


func test_degenerate_v_half_does_not_divide_by_zero() -> void:
	# A misconfigured board (v_half == 0, speed == 0) must fall back to the
	# floor rather than crash on 0/0.
	assert_eq(BladeState.speed_damage_multiplier(0.0, 3.0, 0.0), 1.0)


# ── BladeSim retains per-particle speed at the PHYSICS rate ─────────────────

## Pivot(0,0) + one arm particle driven around it — the same minimal shape
## test_blade_sim_substep.gd's fixtures use. Distance from pivot is the
## calibration axis the issue's tuning note names, so the radius is what
## varies across the tests below rather than node count.
func _arm_state(radius: float) -> BladeState:
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(radius, 0.0)]
	var radii: Array[float] = [10.0, 10.0]
	return BladeState.build(positions, 0, [Vector2i(0, 1)], radii)


func _arm_driver(state: BladeState, radius: float, duration: float) -> Array[BladeDriver]:
	return [BladeArcDriver.new(1, state.positions[0], radius, 0.0, TAU, duration)]


func test_speed_history_is_zero_at_the_pre_step_pose() -> void:
	var state := _arm_state(150.0)
	BladeSim.simulate(state, _arm_driver(state, 150.0, 1.2), 1.2)
	assert_eq(state.speed_history[0][0], 0.0, "pivot never moves")
	assert_eq(state.speed_history[0][1], 0.0,
			"speed_history[0] is the pre-step pose — nothing has stepped yet (#633 parity)")


func test_speed_history_has_one_entry_per_trajectory_sample() -> void:
	var state := _arm_state(150.0)
	var traj := BladeSim.simulate(state, _arm_driver(state, 150.0, 1.2), 1.2)
	assert_eq(state.speed_history.size(), traj.samples.size(),
			"speed_history must parallel samples index for index")


func test_pivot_speed_is_always_zero() -> void:
	var state := _arm_state(150.0)
	BladeSim.simulate(state, _arm_driver(state, 150.0, 1.2), 1.2)
	for step_speeds in state.speed_history:
		assert_eq(step_speeds[0], 0.0, "the pivot is kinematic-zero, never a speed source")


## Measures, does not tune — the owner's call per the issue's tuning note.
## Reports actual apex speeds so a future calibration pass has real numbers.
func test_a_longer_radius_swings_a_faster_apex_at_the_same_duration() -> void:
	var short_state := _arm_state(150.0)
	BladeSim.simulate(short_state, _arm_driver(short_state, 150.0, 1.2), 1.2)
	var long_state := _arm_state(900.0)
	BladeSim.simulate(long_state, _arm_driver(long_state, 900.0, 1.2), 1.2)
	var short_apex := 0.0
	for step_speeds in short_state.speed_history:
		short_apex = maxf(short_apex, step_speeds[1])
	var long_apex := 0.0
	for step_speeds in long_state.speed_history:
		long_apex = maxf(long_apex, step_speeds[1])
	assert_gt(long_apex, short_apex,
			"a farther-from-pivot particle must swing through a faster apex")
	gut.p("measured apex speed — 150px arm: %.1f px/s, 900px arm: %.1f px/s"
			% [short_apex, long_apex])


# ── BladeHitScan stamps per-particle speed onto BladeHitEvent (mechanism) ───

func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## Pivot(0,0)-Arm(150,0), target coincident with the arm's swing START — the
## same trick test_attack_determinism.gd's melee fixture and
## test_hitscan_stable_sort.gd use to land a hit without depending on
## physics-server sync timing. Proves the WIRING (the event's stamped speed
## is read off BladeState.speed_history, not invented or left at the
## BladeHitEvent default), not a specific numeric value.
func test_hitscan_stamps_the_events_speed_from_speed_history() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(150, 0))
	var target := _spawn(graph, "Target", Vector2(150, 0))
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var positions: Array[Vector2] = [pivot.global_position, arm.global_position]
	var radii: Array[float] = [pivot.radius, arm.radius]
	var state := BladeState.build(positions, 0, [Vector2i(0, 1)], radii)
	var drivers: Array[BladeDriver] = [
			BladeArcDriver.new(1, positions[0], 150.0, 0.0, TAU, 1.2)]
	var trajectory := BladeSim.simulate(state, drivers, 1.2)
	var space_state := pivot.get_world_2d().direct_space_state
	var events := BladeHitScan.scan(trajectory, state, space_state, graph)
	assert_false(events.is_empty(), "fixture must register at least one contact")

	var particle_ev: BladeHitEvent = null
	for ev in events:
		if not ev.is_edge_hit():
			particle_ev = ev
			break
	assert_not_null(particle_ev, "must have a particle contact to check")
	var i := int(round(particle_ev.t / trajectory.sample_dt))
	assert_almost_eq(particle_ev.speed, state.speed_history[i][particle_ev.particle_idx], 0.0001,
			"the event's stamped speed must equal speed_history at its own sample index")


# ── End to end: a real swing's landed damage actually scales (acceptance #1) ─

## A pivot + one arm whose radius (distance the driver sweeps it around the
## pivot) is the free variable — a bigger radius means a faster tip at the
## same swing duration, exactly the tuning axis the issue names. Target sits
## coincident with the arm's start (guaranteed contact regardless of physics
## timing, as above); node_health is huge so the hit never triggers a death
## cascade that would complicate reading `amount` back.
## `origin`: like test_attack_record_replay.gd's `_PEER_ORIGIN` — GUT hosts one
## PhysicsDirectSpaceState2D, so two fixtures built at the same coordinates
## would have each swing's pivot particle collide with the OTHER fixture's
## same-position Pivot node. Offsetting the second fixture is what keeps two
## calls to this in one test from cross-hitting each other's colliders.
func _melee_swing(radius: float, origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)

	var attacker := Entity.new()
	attacker.display_name = "A"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.blade_size.base_value = 2.0
	attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.add_child(attacker)
	var defender := Entity.new()
	defender.display_name = "D"
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	defender.stat_board.get_stat(&"node_health").base_value = 9999.0
	graph.add_child(defender)

	var pivot := _spawn(graph, "Pivot", origin)
	var arm := _spawn(graph, "Arm", origin + Vector2(radius, 0))
	graph.add_edge(pivot, arm)
	var target := _spawn(graph, "Target", origin + Vector2(radius, 0))
	await get_tree().process_frame
	alloc.force_allocate(attacker, pivot)
	alloc.force_allocate(attacker, arm)
	attacker.core_location = pivot
	alloc.force_allocate(defender, target)
	defender.core_location = target
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan._on_node_left_clicked(pivot)
	plan._on_node_left_clicked(arm)
	plan.resolve_seed = 0xA11CE
	return {"graph": graph, "plan": plan, "attacker": attacker, "target": target}


## Melee never emits an edge DamageInstance — resolve() skips edge
## BladeHitEvents entirely ("D-1 MVP: edges are inert", skill_blade.gd /
## melee_attack_plan.gd) — so every hit this fixture's outcome holds is
## already a particle hit; the first one is enough.
func _first_hit(outcome: AttackOutcome) -> HitInstance:
	return outcome.hits[0] if not outcome.hits.is_empty() else null


func test_a_faster_swing_lands_more_damage_than_an_identical_slower_one() -> void:
	var slow: Dictionary = await _melee_swing(150.0)
	var fast: Dictionary = await _melee_swing(900.0, Vector2(100000, 100000))
	var slow_world := CombatWorld.shadow()
	var fast_world := CombatWorld.shadow()
	var slow_outcome: AttackOutcome = (slow.plan as MeleeAttackPlan).resolve_against(slow_world)
	var fast_outcome: AttackOutcome = (fast.plan as MeleeAttackPlan).resolve_against(fast_world)
	var slow_hit := _first_hit(slow_outcome)
	var fast_hit := _first_hit(fast_outcome)
	assert_not_null(slow_hit, "the slow fixture must land a hit")
	assert_not_null(fast_hit, "the fast fixture must land a hit")
	var base: float = float((slow.attacker as Entity).stat_board.get_stat(&"blade_damage").get_value())
	assert_gt(base, 0.0, "fixture must actually deal base damage or this proves nothing")
	assert_gte(slow_hit.amount, base - 0.001,
			"even the slow swing must never land LESS than the base coefficient (floor)")
	assert_gt(fast_hit.amount, slow_hit.amount,
			"a farther-from-pivot (faster-tipped) swing must land strictly more damage")
	slow_world.free_shadow()
	fast_world.free_shadow()


# ── The determinism contract (acceptance #5) ─────────────────────────────────

## The authority resolves once; the peer never recomputes `f(speed)` — it
## replays the captured `effective_amount`. Proven directly here via a
## capture/rebuild round trip (AttackRecord.rebuild never constructs a
## BladeDamageInstance, so a peer physically cannot re-run this multiply).
func test_a_captured_and_rebuilt_landing_carries_the_authoritys_speed_scaled_amount() -> void:
	var ctx: Dictionary = await _melee_swing(900.0)
	var graph: Graph = ctx.graph
	var world := CombatWorld.shadow()
	var outcome: AttackOutcome = (ctx.plan as MeleeAttackPlan).resolve_against(world)
	var hit := _first_hit(outcome)
	assert_not_null(hit, "fixture must land a hit")
	var base: float = float((ctx.attacker as Entity).stat_board.get_stat(&"blade_damage").get_value())
	assert_gt(hit.effective_amount, base,
			"fixture must actually exercise the speed bonus or this proves nothing")

	var record := AttackRecord.capture(outcome, graph)
	var rebuilt := AttackRecord.rebuild(record, graph)
	var rebuilt_hit := _first_hit(rebuilt)
	assert_not_null(rebuilt_hit, "rebuild must reproduce the landing")
	assert_almost_eq(rebuilt_hit.effective_amount, hit.effective_amount, 0.0001,
			"a replayed landing must carry the EXACT speed-scaled amount the "
			+ "authority computed, not a fresh f(speed) evaluation")
	world.free_shadow()
