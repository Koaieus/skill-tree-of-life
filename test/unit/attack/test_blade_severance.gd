extends GutTest

## #186's acceptance, re-pointed onto #801's model: a blade remainder severed
## mid-sweep keeps coasting instead of vanishing, armed, from the velocity it
## already had — [b]in the same state and the same trajectory[/b]. There is no
## second body, no second sim and no separation-velocity seeding, because the
## velocity was never lost: a severance is a CONSTRAINT REMOVAL, and Verlet
## carries a particle nothing is pulling on.
##
## The behaviour these pin is #186's and must survive unchanged; only the
## mechanism moved. The drag half lives in test_blade_chunked_parity.gd, where
## the per-particle array is pinned alongside its bit-exactness claim.
##
## Every fixture here severs via a VERTEX POP, never by driving
## `BladeState.removed_edges` through the spike gate: under ADR 0005 edges are
## purely structural, so a vertex pop is the only live producer of a severance
## (bunker break, #781, will be the second — and
## `test_the_continuation_is_a_function_of_topology_not_of_trigger` is what pins
## that it needs no code of its own here).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

const _DT := 1.0 / 120.0
const _SWING := 1.2


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _make_entity(graph: Node) -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.turns_taken = 1
	graph.add_child(entity)
	return entity


func _set_spikes_cap(node: SkillNode, cap: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spikes"
	mod.operation = StatModifier.Operation.SET
	mod.value = cap
	node.add_local_modifier(mod)


func _spikes_pool(node: SkillNode) -> PoolStat:
	return node.get_combat().board().get_stat(&"spikes") as PoolStat


## A graph with an attacker, a hostile defender, and one allocated spiked node.
func _setup(cap: float) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var enemy_camp := Faction.new()
	enemy_camp.id = &"severance_enemy"
	defender.faction = enemy_camp
	var spiked := _spawn_node(graph, "Spiked")
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(defender, spiked)
	_set_spikes_cap(spiked, cap)
	return {"graph": graph, "attacker": attacker, "defender": defender, "spiked": spiked}


## A four-vertex spine: pivot(0) - 1 - 2 - 3. Popping vertex 1 severs {2, 3},
## which is the catastrophic single-spine case #186 exists to soften.
func _spine_state() -> BladeState:
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(50, 0), Vector2(100, 0), Vector2(150, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)]
	var s := BladeState.build(positions, 0, edges, radii)
	for i in 4:
		s.vertex_damage[i] = 3.0 + float(i)
		s.vertex_blunting[i] = 1.0
	return s


## A trajectory of `count` samples in which every particle translates by
## `per_sample` each sample — so its velocity is exactly `per_sample / _DT`
## and the separation velocity a fragment picks up is known in closed form.
func _linear_traj(start: PackedVector2Array, per_sample: Vector2, count: int) -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = _DT
	traj.samples = []
	for k in count:
		var pose := PackedVector2Array()
		for p in start:
			pose.append(p + per_sample * float(k))
		traj.samples.append(pose)
	return traj


func _ev(t: float, particle_idx: int, target: SkillNode) -> BladeHitEvent:
	return BladeHitEvent.new(t, particle_idx, -1, target)


# ---------------------------------------------------------------- acceptance 1

## The severance seam records WHICH vertices left and WHEN — and records them as
## COASTING, not dead. That distinction is the whole issue: under #186 an orphan
## went into `dead_at` and had to be re-armed by a second gate over a second
## body; here it never stops being part of the blade.
func test_a_pop_records_the_outboard_set_as_coasting_not_dead() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var state := _spine_state()
	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)

	assert_false(gate.admit(_ev(0.4, 1, ctx.spiked), CombatWorld.live()),
			"the mid-spine vertex pops")
	assert_eq(gate.result.severances.size(), 1, "one severance event")
	var sev: BladePopResolver.Severance = gate.result.severances[0]
	assert_eq(sev.t, 0.4, "born at the contact time, not at t=0")
	assert_eq(Array(sev.vertices), [2, 3],
			"everything outboard of the pop, ascending; the popped vertex is not part of it")
	assert_true(gate.result.is_dead(1, 0.4), "the POPPED vertex is destroyed")
	assert_false(gate.result.is_dead(2, 0.5), "an orphan is not — it coasts on, armed")
	assert_false(gate.result.is_dead(3, 0.5), "nor is the one behind it")
	assert_eq(gate.result.vertex_pop_count(), 1,
			"one vertex destroyed, whatever it orphaned (#799)")
	assert_eq(gate.result.dead_at.size(), 1,
			"and `dead_at` agrees by construction now, not by filter")


## The velocity was never lost, and this is the exact form of that claim.
## Severing the vertex ahead of it leaves particle 3 with nothing pulling on it,
## so the very next step is pure Verlet: `p + substeps * (p - prev)`, to the
## bit. #186 approximated this by seeding a fresh body from a ONE-SAMPLE
## difference; here there is nothing to approximate.
func test_a_severed_vertex_continues_from_its_exact_verlet_velocity() -> void:
	var state := _spine_state()
	var drivers: Array[BladeDriver] = [BladeArcDriver.new(
			1, state.positions[0], 50.0, 0.0, TAU, _SWING)]
	BladeSim.simulate_range(state, drivers, 0, 40, 1.0 / 120.0)
	var p: Vector2 = state.positions[3]
	var v: Vector2 = p - state.prev_positions[3]
	assert_gt(v.length(), 0.0, "fixture: the tip must actually be moving")

	# The whole of a severance: freeze vertex 2, drop its constraints (which
	# takes the 2-3 constraint with it), drop nothing else.
	state.remove_vertex(2)
	assert_eq(state.constraints.size(), 1, "only the pivot's own 0-1 link is left")

	var tail := BladeSim.simulate_range(
			state, drivers, 40, 1, 1.0 / 120.0)
	var expected := p + v * float(BladeSim.DEFAULT_SUBSTEPS)
	assert_eq(tail.samples[1][3], expected,
			"one step of free coasting is exactly substeps * its stored velocity")
	assert_eq(tail.samples[1][2], state.positions[2],
			"and the corpse has not moved at all")


## A pop on the final sample re-bakes nothing — there is no swing left to
## continue, and `simulate_range` says so without a special case.
func test_a_severance_on_the_final_sample_re_bakes_nothing() -> void:
	var state := _spine_state()
	var drivers: Array[BladeDriver] = []
	var steps := int(ceil(_SWING / _DT))
	var pose := state.positions.duplicate()
	# A non-zero offset trusts `prev_positions` as the previous chunk left it —
	# a fresh state has none, and the solver refuses the mismatch (#847).
	state.prev_positions = state.positions.duplicate()
	var tail := BladeSim.simulate_range(state, drivers, steps, 0, _DT)
	assert_eq(tail.samples.size(), 1, "the pose it started at, and nothing after it")
	assert_eq(tail.samples[0], pose, "which is exactly where the swing had got to")


# ---------------------------------------------------------------- acceptance 3

## No disconnection damage scale exists to apply, and now there is nowhere for
## one to hide: the coasting vertices are the SAME entries of the SAME state, so
## their coefficients cannot be rescaled on the way out. #779's speed curve
## (applied at land time, off the coasting speed) is the only thing that makes a
## coasting hit differ from a driven one.
func test_severance_rescales_no_damage() -> void:
	var state := _spine_state()
	var damage_before := state.vertex_damage.duplicate()
	var blunting_before := state.vertex_blunting.duplicate()
	state.remove_vertex(1)
	state.set_damping(2, BladeState.SEVERED_DRAG)
	state.set_damping(3, BladeState.SEVERED_DRAG)
	assert_eq(state.vertex_damage, damage_before, "every coefficient, untouched")
	assert_eq(state.vertex_blunting, blunting_before, "blunting too")


## What a death IS, in full: a frozen corpse, its constraints gone, the pivot
## still pinned, and every surviving constraint still having both ends alive.
## The `is_unpinned` flag this replaces existed only because #186 had to build a
## STANDALONE fragment state whose index 0 would otherwise have been pinned.
func test_a_death_is_a_frozen_corpse_and_a_dropped_constraint_set() -> void:
	var state := _spine_state()
	state.remove_vertex(2)

	assert_eq(state.inv_masses[0], 0.0, "the pivot is still the pinned handle")
	assert_eq(state.inv_masses[2], 0.0, "the corpse is frozen where it died")
	assert_eq(state.inv_masses[3], 1.0, "the orphan is still dynamic — it coasts")
	assert_true(state.is_vertex_removed(2), "recorded, so the scan stops querying it")
	assert_eq(state.edges.size(), 3,
			"`edges` is NOT spliced — a BladeHitEvent carries an index into it (#785)")
	assert_eq(state.constraints.size(), 1, "both constraints touching the corpse are gone")
	var dc := state.constraints[0] as BladeDistanceConstraint
	assert_eq(Vector2i(dc.a, dc.b), Vector2i(0, 1), "the surviving link is the pivot's own")


## The one dropped driver: a driven neighbour that dies must stop being driven,
## or its corpse would be swung around by an arm it is no longer attached to.
func test_a_dead_or_coasting_vertex_keeps_no_driver() -> void:
	var ctx: Dictionary = await _setup(2.0)  # two pops, one defender
	var state := _spine_state()
	var drivers: Array[BladeDriver] = [BladeArcDriver.new(
			1, state.positions[0], 50.0, 0.0, TAU, _SWING)]
	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)
	gate.admit(_ev(0.4, 1, ctx.spiked), CombatWorld.live())
	state.remove_vertex(1)
	assert_eq(MeleeAttackPlan._surviving_drivers(drivers, state, gate).size(), 0,
			"the dead driven neighbour's driver goes with it")

	# And the same for a vertex that is merely coasting: alive, but no longer
	# attached to the handle, so nothing may keep swinging it.
	var state2 := _spine_state()
	var drivers2: Array[BladeDriver] = [BladeArcDriver.new(
			2, state2.positions[0], 100.0, 0.0, TAU, _SWING)]
	var gate2 := BladePopResolver.LiveGate.new(state2, ctx.attacker)
	gate2.admit(_ev(0.4, 1, ctx.spiked), CombatWorld.live())
	assert_eq(Array(gate2.result.severances[0].vertices), [2, 3], "fixture: 2 is coasting")
	assert_eq(MeleeAttackPlan._surviving_drivers(drivers2, state2, gate2).size(), 0,
			"a coasting vertex is not driven either")


# ---------------------------------------------------------------- acceptance 5

## #781's bunker break is not built, so this pins the STRUCTURAL claim that
## satisfies acceptance 5: the continuation is a pure function of the RESULTING
## topology and knows nothing about what produced it. Reaching the same
## constraint set / inverse masses by `remove_vertex` and by hand (the shape a
## `remove_edge` break will leave) continues bit-identically.
func test_the_continuation_is_a_function_of_topology_not_of_trigger() -> void:
	var by_vertex := _spine_state()
	var by_hand := _spine_state()
	var drivers_a: Array[BladeDriver] = [BladeArcDriver.new(
			1, by_vertex.positions[0], 50.0, 0.0, TAU, _SWING)]
	var drivers_b: Array[BladeDriver] = [BladeArcDriver.new(
			1, by_hand.positions[0], 50.0, 0.0, TAU, _SWING)]
	BladeSim.simulate_range(by_vertex, drivers_a, 0, 30, _DT)
	BladeSim.simulate_range(by_hand, drivers_b, 0, 30, _DT)

	by_vertex.remove_vertex(2)
	# The same end state, reached without ever calling remove_vertex: the two
	# incident edges cut, the vertex frozen.
	by_hand.remove_edge(1)
	by_hand.remove_edge(2)
	by_hand.inv_masses[2] = 0.0

	var a := BladeSim.simulate_range(by_vertex, drivers_a, 30, 60, _DT)
	var b := BladeSim.simulate_range(by_hand, drivers_b, 30, 60, _DT)
	assert_eq(a.samples[60], b.samples[60],
			"same continuation, to the bit — the trigger is not an input")


# ---------------------------------------------------------------- acceptance 2

## A coasting vertex stays ARMED: it drains a defender's spikes and pops against
## them like any blade vertex. Only the PIVOT is exempt, and it is exempt because
## it is the wielder's grip — #186's "the fragment's root is not exempt" is now
## true for the plainer reason that there is no second root to exempt.
func test_a_coasting_vertex_spends_spikes_and_is_not_exempt() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var state := _spine_state()
	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)
	var pool := _spikes_pool(ctx.spiked)
	assert_eq(pool.current, 2.0, "fixture: two spikes to spend")

	assert_false(gate.admit(_ev(0.3, 1, ctx.spiked), CombatWorld.live()),
			"the mid-spine vertex pops, severing 2 and 3")
	assert_eq(pool.current, 1.0, "one spike spent")
	# Vertex 2 is coasting. It arrives later and pops like anything else.
	assert_false(gate.admit(_ev(0.6, 2, ctx.spiked), CombatWorld.live()),
			"the coasting vertex pops rather than sailing through")
	assert_eq(pool.current, 0.0, "and it spent the defender's remaining spikes doing it")
	assert_eq(gate.result.vertex_pop_count(), 2, "recorded as a pop like any other")
	# The pivot, by contrast, is exempt and spends nothing.
	assert_true(gate.admit(_ev(0.9, 0, ctx.spiked), CombatWorld.live()),
			"the wielder's own grip is never popped")


## A second pop inside the coasting remainder kills THAT vertex only; whatever
## is behind it keeps coasting. #186 had to re-root a fragment and shed a
## fragment-of-a-fragment for this; here it falls out of there being one state.
func test_a_second_pop_in_the_remainder_kills_only_that_vertex() -> void:
	var ctx: Dictionary = await _setup(2.0)
	var state := _spine_state()
	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)

	gate.admit(_ev(0.2, 1, ctx.spiked), CombatWorld.live())
	assert_eq(Array(gate.result.severances[0].vertices), [2, 3], "2 and 3 coast")
	gate.admit(_ev(0.5, 2, ctx.spiked), CombatWorld.live())

	assert_true(gate.result.is_dead(2, 0.5), "the coasting vertex that was hit dies")
	assert_false(gate.result.is_dead(3, 0.9),
			"the one behind it does not — it was already coasting and still is")
	assert_eq(gate.result.severances.size(), 1,
			"and it is not re-reported: it never stopped coasting")
	assert_eq(gate.result.vertex_pop_count(), 2, "two vertices destroyed in total")


# ---------------------------------------------------------------- determinism

## The crit stream survives the interleave (#801, and #507's one-stream rule).
##
## `resolve_against` no longer builds every DamageInstance and rolls every crit
## up front — it mints, rolls and LANDS one sample at a time, because a pop
## decision needs the world as the earlier landings left it. One RNG object
## handed to every batch's `decide_all` in turn must therefore consume the
## stream in exactly the order a single `decide_all` over the finished hit list
## would have: batches run in `t` order, and `OutcomeSchedule._sorted` breaks a
## same-`t` tie on insertion index, so per-batch order is the global order's
## blocks. If that ever stops holding, the same `resolve_seed` deals different
## crits on the authority than a peer reproduces from the record — a desync no
## test of the sim itself would see. #186's per-round crit salt is gone with the
## rounds it existed for.
func test_batched_crit_rolls_equal_one_global_roll() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var attacker: Entity = ctx.attacker
	attacker.stat_board.crit_chance.base_value = 0.5
	const _SEED := 0x5EED_1234
	# Several samples, several hits landing on the same one — the tie case.
	var batches := [[0.10, 0.10], [0.25], [0.40, 0.40, 0.40], [0.75], [0.90, 0.90]]

	var whole := AttackOutcome.new()
	whole.cadence = ScheduleEntry.Cadence.SWING
	for batch in batches:
		for key in batch:
			whole.hits.append(_crit_hit(attacker, key))
	whole.schedule = OutcomeSchedule.compile(whole)
	CritRoll.decide_all(whole, CritRoll.stream_for(_SEED))
	var expected: Array[int] = []
	for hit in whole.hits:
		expected.append(hit.crit_tier)

	var rng := CritRoll.stream_for(_SEED)
	var batched: Array[int] = []
	for batch in batches:
		var sub := AttackOutcome.new()
		sub.cadence = ScheduleEntry.Cadence.SWING
		for key in batch:
			sub.hits.append(_crit_hit(attacker, key))
		sub.schedule = OutcomeSchedule.compile(sub)
		CritRoll.decide_all(sub, rng)
		for hit in sub.hits:
			batched.append(hit.crit_tier)

	assert_true(expected.has(1), "fixture: the stream must actually crit sometimes")
	assert_true(expected.has(0), "fixture: and must not crit every time")
	assert_eq(batched, expected,
			"one stream, consumed batch by batch, deals the identical crits")


func _crit_hit(attacker: Entity, structural_key: float) -> DamageInstance:
	var di := DamageInstance.new()
	di.amount = 5.0
	di.type = DamageInstance.Type.PHYSICAL
	di.attacker = attacker
	di.structural_key = structural_key
	return di
