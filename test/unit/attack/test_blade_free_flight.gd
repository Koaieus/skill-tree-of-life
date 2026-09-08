extends GutTest

## #186 acceptance: a blade fragment severed mid-sweep keeps coasting instead
## of vanishing, armed, from its velocity at the moment of disconnection.
##
## Every fixture here severs via a VERTEX POP, never by driving
## `BladeState.removed_edges` through the spike gate: under ADR 0005 edges are
## purely structural, so a vertex pop is the only live producer of a
## disconnected fragment (bunker shatter, #781, will be the second — and
## `test_a_hand_built_fragment_flies_identically` is what pins that it needs no
## code of its own here).

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
	enemy_camp.id = &"free_flight_enemy"
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

## The severance seam records WHICH vertices left and WHEN — the whole input
## free flight consumes.
func test_a_pop_records_the_outboard_fragment() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var state := _spine_state()
	var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)

	assert_false(gate.admit(_ev(0.4, 1, ctx.spiked), CombatWorld.live()),
			"the mid-spine vertex pops")
	assert_eq(gate.result.fragments.size(), 1, "one severance event")
	var frag: BladePopResolver.Fragment = gate.result.fragments[0]
	assert_eq(frag.t, 0.4, "born at the contact time, not at t=0")
	assert_eq(Array(frag.vertices), [2, 3],
			"everything outboard of the pop, ascending; the popped vertex is not part of it")


## The fragment continues from the velocity the DRIVEN solver had it at one
## sample before separation — not from rest, which is what disintegration
## effectively was.
func test_the_fragment_starts_from_its_separation_velocity() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	var frag := BladePopResolver.Fragment.new(0.25, PackedInt32Array([2, 3]))

	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING, 0.0)
	assert_not_null(flight, "a fragment born mid-swing has swing left to fly")
	assert_eq(flight.birth_t, 0.25, "the flight's clock starts at separation")
	for v in flight.velocities:
		assert_almost_eq(v.x, 2.0 / _DT, 1.0,
				"px/s, straight off the driven trajectory")
		assert_almost_eq(v.y, 0.0, 0.001, "no velocity the driven blade did not have")


func test_a_fragment_born_after_the_swing_ends_does_not_fly() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	var frag := BladePopResolver.Fragment.new(_SWING, PackedInt32Array([2, 3]))
	assert_null(BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING),
			"no swing left to coast through")


# ---------------------------------------------------------------- acceptance 3

## No disconnection damage scale exists to apply: the fragment carries the
## IDENTICAL coefficients its vertices had while attached, and #779's speed
## curve (applied at land time, off the coasting speed) is the only thing that
## makes a free hit differ from a driven one.
func test_the_fragment_carries_its_damage_unscaled() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	var frag := BladePopResolver.Fragment.new(0.25, PackedInt32Array([2, 3]))
	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING)

	assert_eq(flight.state.vertex_damage[0], state.vertex_damage[2],
			"vertex 2's coefficient, untouched")
	assert_eq(flight.state.vertex_damage[1], state.vertex_damage[3],
			"vertex 3's coefficient, untouched")
	assert_eq(flight.state.vertex_blunting[0], state.vertex_blunting[2],
			"blunting travels with it too")


## Unpinned means unpinned: no zero inverse mass anywhere, `is_unpinned` set,
## and only the constraints whose BOTH ends came along.
func test_the_fragment_is_an_unpinned_body_with_internal_constraints_only() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	var frag := BladePopResolver.Fragment.new(0.25, PackedInt32Array([2, 3]))
	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING)

	assert_true(flight.state.is_unpinned, "no handle")
	for m in flight.state.inv_masses:
		assert_eq(m, 1.0, "every particle is dynamic, including the BFS root")
	assert_eq(flight.state.edges.size(), 1, "only the 2-3 edge is internal to the fragment")
	assert_eq(flight.state.edges[0], Vector2i(0, 1), "remapped into the fragment's own index space")
	assert_eq(flight.state.constraints.size(), 1, "the 1-2 constraint did NOT come along")
	var dc := flight.state.constraints[0] as BladeDistanceConstraint
	assert_almost_eq(dc.rest, 50.0, 0.001,
			"rest length from the SOURCE constraint, not from the deformed mid-swing distance")


# ---------------------------------------------------------------- acceptance 4

## The drag term is authored as a named constant, and 0 is a meaningful value:
## an undecelerated coast, displacement exactly velocity * time.
func test_zero_drag_coasts_undecelerated() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	# Born at 0.25, not 0.0: a fragment severed before the blade has moved has
	# no separation velocity to carry, which is a degenerate case, not a coast.
	var frag := BladePopResolver.Fragment.new(0.25, PackedInt32Array([3]))

	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING, 0.0)
	var start: Vector2 = flight.trajectory.samples[0][0]
	var end: Vector2 = flight.trajectory.samples[flight.trajectory.samples.size() - 1][0]
	var speed := 2.0 / _DT
	assert_almost_eq((end - start).x, speed * flight.trajectory.duration(),
			speed * _DT * 2.0,
			"a lone particle with no drag travels v*t, to within a sample")


func test_drag_bleeds_a_coasting_fragment() -> void:
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)

	var free_flight := BladeFreeFlight.spawn(
			state, traj, 0.0, BladePopResolver.Fragment.new(0.25, PackedInt32Array([3])),
			_SWING, 0.0)
	var dragged := BladeFreeFlight.spawn(
			state, traj, 0.0, BladePopResolver.Fragment.new(0.25, PackedInt32Array([3])),
			_SWING, BladeFreeFlight.DRAG)

	var undragged_end: Vector2 = free_flight.trajectory.samples[free_flight.trajectory.samples.size() - 1][0]
	var dragged_end: Vector2 = dragged.trajectory.samples[dragged.trajectory.samples.size() - 1][0]
	var origin: Vector2 = free_flight.trajectory.samples[0][0]
	assert_gt(undragged_end.x - origin.x, dragged_end.x - origin.x,
			"drag costs the fragment distance over the remainder of the swing")
	assert_gt(dragged_end.x - origin.x, 0.0, "a small drag, not a wall")
	assert_gt(BladeFreeFlight.DRAG, 0.0, "the shipped default is a real, small drag")


# ---------------------------------------------------------------- acceptance 5

## #781's bunker shatter is not built, so this pins the STRUCTURAL claim that
## satisfies acceptance 5: free flight consumes a Fragment and knows nothing
## about what severed it. A hand-built Fragment — exactly what a shatter will
## hand it — flies bit-identically to one a spike pop produced.
func test_a_hand_built_fragment_flies_identically() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var popped_state := _spine_state()
	var gate := BladePopResolver.LiveGate.new(popped_state, ctx.attacker)
	gate.admit(_ev(0.25, 1, ctx.spiked), CombatWorld.live())
	var from_pop: BladePopResolver.Fragment = gate.result.fragments[0]

	# Same vertices, same instant, no pop anywhere in its provenance.
	var from_shatter := BladePopResolver.Fragment.new(0.25, PackedInt32Array([2, 3]))

	var traj := _linear_traj(_spine_state().positions, Vector2(2.0, 0.0), 60)
	var a := BladeFreeFlight.spawn(_spine_state(), traj, 0.0, from_pop, _SWING)
	var b := BladeFreeFlight.spawn(_spine_state(), traj, 0.0, from_shatter, _SWING)

	assert_eq(a.trajectory.samples.size(), b.trajectory.samples.size(),
			"same flight length")
	var last := a.trajectory.samples.size() - 1
	assert_eq(a.trajectory.samples[last], b.trajectory.samples[last],
			"same flight, to the bit — the trigger is not an input")


# ---------------------------------------------------------------- acceptance 2

## A coasting fragment stays ARMED: it drains a defender's spikes and pops
## against them like any blade vertex. In particular its BFS root is NOT
## pivot-exempt — that exemption protects the wielder's grip, and a severed
## fragment has no grip.
func test_a_coasting_fragment_spends_spikes_and_its_root_is_not_exempt() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	var frag := BladePopResolver.Fragment.new(0.25, PackedInt32Array([2, 3]))
	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING)

	var free_gate := BladePopResolver.LiveGate.new(flight.state, ctx.attacker)
	var pool := _spikes_pool(ctx.spiked)
	assert_eq(pool.current, 1.0, "fixture: one spike to spend")

	# Local index 0 is the fragment's BFS root — the vertex that WOULD be
	# exempt if it were a real pivot.
	assert_false(free_gate.admit(_ev(0.5, 0, ctx.spiked), CombatWorld.live()),
			"the fragment's root pops rather than sailing through")
	assert_eq(pool.current, 0.0, "and it spent the defender's spikes doing it")
	assert_eq(free_gate.result.pops.size(), 1, "recorded as a pop like any other")


## A fragment that loses its own root re-roots and sheds a sub-fragment rather
## than silently disintegrating — the recursion #186's queue consumes.
func test_a_popped_fragment_sheds_a_sub_fragment_rather_than_vanishing() -> void:
	var ctx: Dictionary = await _setup(1.0)
	var state := _spine_state()
	var traj := _linear_traj(state.positions, Vector2(2.0, 0.0), 60)
	# All three outboard vertices, so the fragment is itself a 3-vertex chain.
	var frag := BladePopResolver.Fragment.new(0.2, PackedInt32Array([1, 2, 3]))
	var flight := BladeFreeFlight.spawn(state, traj, 0.0, frag, _SWING)
	assert_eq(flight.state.constraints.size(), 2, "fixture: a 3-vertex chain")

	var free_gate := BladePopResolver.LiveGate.new(flight.state, ctx.attacker)
	# Kill the MIDDLE of the fragment: local 1.
	assert_false(free_gate.admit(_ev(0.5, 1, ctx.spiked), CombatWorld.live()),
			"the fragment's middle vertex pops")
	assert_eq(free_gate.result.fragments.size(), 1, "the far end is severed again")
	assert_eq(Array(free_gate.result.fragments[0].vertices), [2],
			"and it is the far end, not the root's own side")
