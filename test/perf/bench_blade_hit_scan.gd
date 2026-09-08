extends GutTest

## #785 acceptance 6: what [method BladeHitScan.scan] costs at the scale the
## owner named — [i]"STR can be raised to 1000 or more if you get the right
## stuff, blade size per STR modifiers can be looted so expect potentially up to
## 100 size blade possibly more"[/i] — i.e. 100+ vertices and ~200 edges, not 21.
##
## Run: [code]mise run test:one -- res://test/perf/bench_blade_hit_scan.gd[/code]
##
## [b]Not collected by the suite[/b] — same double opt-out as its siblings:
## `test/perf/` is outside `.gutconfig.json`'s `test/unit/`, and `bench_` keeps
## even `test:dir` from finding it. It is a GutTest rather than a bare
## SceneTree script (as `bench_blade_sim.gd` is) for one reason: the scan needs
## a live [PhysicsDirectSpaceState2D], which only exists inside a scene tree.
## That is exactly why `bench_blade_sim.gd` excluded the scan and told you to
## "measure it separately, in a scene, if it becomes the suspect." It became
## the suspect the moment edges started colliding, so here it is.
##
## [b]The broad phase is the variable.[/b] Per substep the narrow phase issues
## one shape query per particle plus one per edge — ~300 at this scale, times
## ~72 substeps, ~21600 queries per resolve. The broad phase spends ONE query
## per substep on the blade's whole bounding box and skips the rest when it
## comes back empty, which is the overwhelmingly common substep. Both settings
## must produce the IDENTICAL event list (the box is a strict superset of every
## narrow-phase shape) — this file asserts that too, because a broad phase that
## changes the answer is a determinism bug, not an optimisation.
##
## Numbers move with the machine — record the CPU alongside any result you cite.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

const _VERTICES := 100
const _SWING_DURATION := 1.2
const _REPS := 5


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## A braced ladder: two parallel rails of `_VERTICES / 2` vertices each, rungs
## between them and a diagonal per cell. 100 vertices, ~245 edges — the
## "realistic density" shape `bench_blade_sim.gd` already benches the solver on,
## so the two numbers compose into one per-resolve cost.
func _ladder(pivot_at: Vector2) -> Dictionary:
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	var edges: Array[Vector2i] = []
	var rungs := _VERTICES / 2
	for i in rungs:
		positions.append(pivot_at + Vector2(float(i) * 40.0, -20.0))
		positions.append(pivot_at + Vector2(float(i) * 40.0, 20.0))
		radii.append(14.0)
		radii.append(14.0)
	for i in rungs:
		var lo := i * 2
		edges.append(Vector2i(lo, lo + 1))          # the rung
		if i + 1 < rungs:
			edges.append(Vector2i(lo, lo + 2))      # top rail
			edges.append(Vector2i(lo + 1, lo + 3))  # bottom rail
			edges.append(Vector2i(lo, lo + 3))      # diagonal brace
	return {"positions": positions, "radii": radii, "edges": edges}


## A defender field the blade actually sweeps through, so the measurement is
## not "how fast is an empty query" — 40 nodes scattered across the arc.
func _populate_defenders(graph: Graph, origin: Vector2) -> void:
	for k in 40:
		var angle := TAU * float(k) / 40.0
		var r := 200.0 + float(k % 7) * 180.0
		_spawn(graph, "D%d" % k, origin + Vector2.RIGHT.rotated(angle) * r)


func _elapsed_ms(
		trajectory: BladeTrajectory,
		state: BladeState,
		space_state: PhysicsDirectSpaceState2D,
		graph: Graph,
		exclude: Array[RID],
		broad_phase: bool) -> Array:
	var events: Array[BladeHitEvent] = []
	var start := Time.get_ticks_usec()
	for _r in _REPS:
		events = BladeHitScan.scan(
				trajectory, state, space_state, graph, 0xFFFFFFFF, exclude, broad_phase)
	var total := Time.get_ticks_usec() - start
	return [float(total) / float(_REPS) / 1000.0, events]


## `defenders_at` is the free variable. Parked on the blade's own arc, every
## substep's bounding box hits something and the broad phase can never reject —
## the worst case for it. Parked far away, every substep rejects on one query
## and the ~300 narrow-phase queries are never issued — the best case. A real
## level lives between the two, and which end it lives at is a property of the
## MAP, not of this code, which is why both are reported rather than averaged.
func _bench_case(label: String, defenders_at: Vector2, expect_contact: bool) -> void:
	# NOT add_child_autofree: autofree holds every case's graph until the test
	# ENDS, and they all share one World2D — so case 2 would still be querying
	# case 1's colliders and measuring the opposite of what it claims to.
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child(graph)
	var shape := _ladder(Vector2.ZERO)
	var positions: Array[Vector2] = shape["positions"]
	# The blade's OWN nodes are colliders too. MeleeAttackPlan excludes them via
	# collect_target_excludes(); without that the blade spends the whole sweep
	# hitting itself and this measures the wrong thing entirely.
	var exclude: Array[RID] = []
	for i in positions.size():
		exclude.append(_spawn(graph, "B%d" % i, positions[i]).get_rid())
	_populate_defenders(graph, defenders_at)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var state := BladeState.build(positions, 0, shape["edges"], shape["radii"])
	var drivers: Array[BladeDriver] = []
	for e in state.edges:
		var other := -1
		if e.x == 0:
			other = e.y
		elif e.y == 0:
			other = e.x
		if other >= 0:
			drivers.append(BladeArcDriver.new(
					other, positions[0], positions[0].distance_to(positions[other]),
					(positions[other] - positions[0]).angle(), TAU, _SWING_DURATION))
	var trajectory := BladeSim.simulate(state, drivers, _SWING_DURATION)
	var space_state := graph.get_world_2d().direct_space_state

	var with_bp := _elapsed_ms(trajectory, state, space_state, graph, exclude, true)
	var without_bp := _elapsed_ms(trajectory, state, space_state, graph, exclude, false)

	gut.p("--- %s: %d vertices / %d edges, %d substeps, 40 defenders ---"
			% [label, positions.size(), state.edges.size(), trajectory.samples.size()])
	gut.p("  broad phase ON : %.2f ms/resolve" % with_bp[0])
	gut.p("  broad phase OFF: %.2f ms/resolve" % without_bp[0])
	gut.p("  speedup        : %.2fx" % (float(without_bp[0]) / maxf(float(with_bp[0]), 0.0001)))

	# The claim that makes the knob safe to leave on: it is a pure reject, so
	# it cannot change the answer.
	var a: Array[BladeHitEvent] = with_bp[1]
	var b: Array[BladeHitEvent] = without_bp[1]
	assert_eq(a.size(), b.size(),
			"the broad phase must be a strict superset reject — same events either way")
	for i in mini(a.size(), b.size()):
		assert_eq(a[i].target, b[i].target, "same collider at index %d" % i)
		assert_almost_eq(a[i].t, b[i].t, 0.0001, "same contact time at index %d" % i)
		assert_eq(a[i].edge_idx, b[i].edge_idx, "same element at index %d" % i)
		assert_eq(a[i].particle_idx, b[i].particle_idx, "same element at index %d" % i)
	if expect_contact:
		assert_gt(a.size(), 0, "the fixture must actually connect, or this measures nothing")
	else:
		assert_eq(a.size(), 0, "the empty-sweep case must genuinely sweep empty space")

	graph.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func test_bench_scan_at_a_hundred_vertices_with_and_without_broad_phase() -> void:
	await _bench_case("dense field (defenders on the arc)", Vector2.ZERO, true)
	await _bench_case("empty sweep (defenders off-map)", Vector2(80000.0, 80000.0), false)
