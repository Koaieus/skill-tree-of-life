extends SceneTree

## Per-candidate cost of [BladeSim.simulate] — the number that bounds how many
## blade formations #378's melee AI can afford to evaluate per turn.
##
## Run: [code]godot --headless --path . --script res://test/perf/bench_blade_sim.gd[/code]
##
## Solver ONLY — [BladeHitScan.scan] is deliberately excluded: it needs a live
## [PhysicsDirectSpaceState2D], so it cannot run from a headless SceneTree and
## (see docs/domain/melee-blade-sim.md) carries its own threading constraint.
## Measure it separately, in a scene, if it becomes the suspect.
##
## Numbers move with the machine — record the CPU alongside any result you cite.

const SPACING := 60.0
const DURATION := 1.2
const REPS := 20


## Counts constraint projections without touching blade_distance_constraint.gd
## (not owned by this unit) — shares a counter box across every constraint
## in a state. Mirrors test/unit/attack/test_blade_sim_substep.gd's copy;
## kept separate on purpose (perf harness vs correctness test, different
## lifetimes) rather than a shared prod dependency for two measurement tools.
class _CountingConstraint extends BladeDistanceConstraint:
	var _counter: Array

	func _init(a_: int, b_: int, rest_: float, counter: Array) -> void:
		super(a_, b_, rest_)
		_counter = counter

	func project(positions: PackedVector2Array, inv_masses: PackedFloat32Array) -> void:
		_counter[0] += 1
		super.project(positions, inv_masses)


func _initialize() -> void:
	# #798: both backends in one invocation, so the before/after is a single
	# table on a single machine rather than two runs you have to trust.
	if BladeSim.native_available():
		_table("gdscript", false)
		_table("native (C++ GDExtension)", true)
	else:
		print("BladeSolverNative not loaded — GDScript only. Build it with `mise run native:build`.")
		_table("gdscript", false)
	# #790's sweep-count rows count constraint projections through a
	# BladeDistanceConstraint SUBCLASS, which the native path deliberately
	# refuses (see BladeSim._simulate_native's exact get_script() check) — so
	# they are a GDScript measurement by construction and run once, outside
	# the per-backend tables, rather than printing the same numbers twice.
	# #803: a pop swing is one whole bake plus one re-baked tail, on whichever
	# backend is live — so its solver cost is bounded by "no-pop swing + tail",
	# and this row is the measurement acceptance 5 asks for. Both backends.
	if BladeSim.native_available():
		_bench_pop_swing("native (C++ GDExtension)", true)
	_bench_pop_swing("gdscript", false)
	BladeSim.use_native = false
	print("")
	print("--- #790: 100-node / ~250-constraint swing, today's settings vs substepped ---")
	_bench_substep_config("braced mesh (realistic density)", 100, true)
	print("--- #790: 100-node WHIP (worst case for the length axis — pivot ecc ~99) ---")
	_bench_substep_config("pure chain (whip)", 100, false)
	print("--- #796: what a k=100 swing costs on the backend that actually runs it ---")
	_bench_k100_backends("braced mesh", 100, true)
	_bench_k100_backends("pure chain (whip)", 100, false)
	quit()


func _table(backend: String, native: bool) -> void:
	BladeSim.use_native = native
	print("")
	print("=== backend: %s === (%.1fs swing, solver only)" % [backend, DURATION])
	for k in [5, 10, 20, 30]:
		_bench("chain", k, false, 0.0)
	for k in [5, 10, 20, 30]:
		_bench("chain, adaptive iters", k, false, 400.0)
	for k in [5, 10, 20]:
		_bench("triangulated mesh", k, true, 0.0)

	print("--- coarse scoring tier: k=20 chain, cheaper knobs ---")
	_bench_knobs("full fidelity", 20, 1.0 / 120.0, 16)
	_bench_knobs("half rate", 20, 1.0 / 60.0, 16)
	_bench_knobs("quarter rate", 20, 1.0 / 30.0, 16)
	_bench_knobs("quarter rate, 4 iters", 20, 1.0 / 30.0, 4)
	_bench_knobs("quarter rate, 2 iters", 20, 1.0 / 30.0, 2)


## #803 — the cost of a severance. A k=20 chain, severed at vertex 8 one
## third of the way through the swing: the resolve loop bakes the whole swing
## once (optimistically), reads the state at the severance sample off the bake,
## mutates, and re-bakes the tail. So a pop swing's SOLVER cost is exactly
## whole + tail, and the row states all three so the bound is visible. Before
## #803 the tail ran GDScript regardless of backend (and a head replay ran too).
func _bench_pop_swing(backend: String, native: bool) -> void:
	BladeSim.use_native = native
	var k := 20
	var steps := int(ceil(DURATION / (1.0 / 120.0)))
	var cut := steps / 3
	var whole_us := 0.0
	var tail_us := 0.0
	var pop_us := 0.0
	for _r in REPS:
		# No-pop swing: one whole bake.
		var w := _chain(k)
		var wd: Array[BladeDriver] = [BladeArcDriver.new(1, w.positions[0], SPACING, 0.0, TAU, DURATION)]
		var t0 := Time.get_ticks_usec()
		BladeSim.simulate(w, wd, DURATION)
		whole_us += float(Time.get_ticks_usec() - t0)
		# Pop swing, as resolve_against runs it: whole bake, rewind to the
		# severance sample off prev_samples, sever, re-bake the tail.
		var s := _chain(k)
		var sd: Array[BladeDriver] = [BladeArcDriver.new(1, s.positions[0], SPACING, 0.0, TAU, DURATION)]
		t0 = Time.get_ticks_usec()
		var bake := BladeSim.simulate(s, sd, DURATION)
		s.positions = bake.samples[cut].duplicate()
		s.prev_positions = bake.prev_samples[cut].duplicate()
		s.remove_vertex(8)
		for i in range(9, k):
			s.set_damping(i, BladeState.SEVERED_DRAG)
		var t1 := Time.get_ticks_usec()
		BladeSim.simulate_range(s, sd, cut, steps - cut)
		var t2 := Time.get_ticks_usec()
		tail_us += float(t2 - t1)
		pop_us += float(t2 - t0)
	print("--- #803: k=20 chain severed at vertex 8, sample %d of %d [%s] ---" % [cut, steps, backend])
	print("  no-pop swing (whole bake)        %9.1f us" % (whole_us / float(REPS)))
	print("  re-baked tail alone              %9.1f us" % (tail_us / float(REPS)))
	print("  pop swing (bake + rewind + tail) %9.1f us   bound: whole + tail = %.1f us" % [
			pop_us / float(REPS), (whole_us + tail_us) / float(REPS)])


## Straight chain from the pivot — the whippy extreme.
func _chain(k: int) -> BladeState:
	var pos: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in k:
		pos.append(Vector2(float(i) * SPACING, 0.0))
		radii.append(20.0)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(pos, 0, edges, radii)


## Chain plus an i-2 brace on every particle — the rigid extreme, ~2x constraints.
func _mesh(k: int) -> BladeState:
	var s := _chain(k)
	for i in range(2, k):
		s.edges.append(Vector2i(i - 2, i))
		var rest: float = s.positions[i - 2].distance_to(s.positions[i])
		s.constraints.append(BladeDistanceConstraint.new(i - 2, i, rest))
	return s


## `_mesh(100)` alone lands at 197 constraints (99 chain + 98 i-2 braces);
## this adds a sparser i-3 brace pass to reach the issue's "~250" target
## (246 for k=100) — closer to what a real triangulated blade carries.
func _dense_mesh(k: int) -> BladeState:
	var s := _mesh(k)
	for i in range(3, k, 2):
		s.edges.append(Vector2i(i - 3, i))
		var rest: float = s.positions[i - 3].distance_to(s.positions[i])
		s.constraints.append(BladeDistanceConstraint.new(i - 3, i, rest))
	return s


func _run(k: int, meshed: bool, dt: float, iters: int, vel_ref: float) -> float:
	var t0 := Time.get_ticks_usec()
	for _r in REPS:
		var s: BladeState = _mesh(k) if meshed else _chain(k)
		var drivers: Array[BladeDriver] = [
			BladeArcDriver.new(1, s.positions[0], SPACING, 0.0, TAU, DURATION)
		]
		BladeSim.simulate(s, drivers, DURATION, dt, iters, vel_ref)
	return float(Time.get_ticks_usec() - t0) / float(REPS)


func _bench(label: String, k: int, meshed: bool, vel_ref: float) -> void:
	print("%-24s k=%-3d %9.1f us/eval" % [label, k, _run(k, meshed, 1.0 / 120.0, 16, vel_ref)])


func _bench_knobs(label: String, k: int, dt: float, iters: int) -> void:
	print("%-24s dt=1/%-4d it=%-3d %9.1f us/eval" % [
		label, int(round(1.0 / dt)), iters, _run(k, false, dt, iters, 0.0)])


## Sum of |current distance - rest length| across every constraint — how far
## the blade drifted from rigid by the end of the swing. Lower is better.
func _total_stretch_error(state: BladeState) -> float:
	var positions := state.positions
	var total := 0.0
	for c in state.constraints:
		var dc := c as BladeDistanceConstraint
		total += absf(positions[dc.a].distance_to(positions[dc.b]) - dc.rest)
	return total


## Builds `k` nodes densely-braced (if `dense`) or as a pure whip, with every
## constraint counted, then runs it at TODAY's flat settings and at the
## substepped + length-scaled config (#790), reporting wall-clock, total
## constraint-projection count, and the shape-holding metric for both.
func _bench_substep_config(label: String, k: int, dense: bool) -> void:
	var old_counter: Array = [0]
	var old_state := _dense_or_chain(k, dense, old_counter)
	var old_ecc := old_state.pivot_eccentricity()
	var t0 := Time.get_ticks_usec()
	BladeSim.simulate(
			old_state, _drivers_for(old_state), DURATION,
			1.0 / 120.0, 16, 0.0, 1, false)
	var old_us := Time.get_ticks_usec() - t0
	var old_error := _total_stretch_error(old_state)

	var new_counter: Array = [0]
	var new_state := _dense_or_chain(k, dense, new_counter)
	t0 = Time.get_ticks_usec()
	BladeSim.simulate(
			new_state, _drivers_for(new_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true)
	var new_us := Time.get_ticks_usec() - t0
	var new_error := _total_stretch_error(new_state)

	print("%s: k=%d constraints=%d pivot_ecc=%d" % [label, k, old_state.constraints.size(), old_ecc])
	print("  today   (dt=1/120, 16 it, substeps=1, length off): %6d us, %8d projections, stretch_error=%.3f"
			% [old_us, old_counter[0], old_error])
	print("  #790    (dt=1/120, %d it, substeps=%d, length on): %6d us, %8d projections, stretch_error=%.3f"
			% [BladeSim.DEFAULT_ITERATIONS, BladeSim.DEFAULT_SUBSTEPS, new_us, new_counter[0], new_error])
	print("  projection ratio (new/old): %.2fx   wall-clock ratio (new/old): %.2fx"
			% [float(new_counter[0]) / float(old_counter[0]), float(new_us) / float(old_us)])


func _dense_or_chain(k: int, dense: bool, counter: Array) -> BladeState:
	var s: BladeState = _dense_mesh(k) if dense else _chain(k)
	var counted: Array[BladeConstraint] = []
	for c in s.constraints:
		var dc := c as BladeDistanceConstraint
		counted.append(_CountingConstraint.new(dc.a, dc.b, dc.rest, counter))
	s.constraints = counted
	return s


func _drivers_for(state: BladeState) -> Array[BladeDriver]:
	return [BladeArcDriver.new(1, state.positions[0], SPACING, 0.0, TAU, DURATION)]


## The #790 rows above count projections through a constraint SUBCLASS, which
## `_simulate_native` refuses by an exact `get_script()` check — so they are a
## GDScript measurement BY CONSTRUCTION and say nothing about what a k=100 swing
## costs today. This row runs the same #790 configuration on the plain
## constraints the native backend accepts, on both backends.
##
## It exists because #796's body quotes the GDScript numbers (324 ms / 792 ms) as
## the main-thread stall, and #798 landed a backend after those were measured.
## Read THIS row as that issue's "before", not the table in its body.
func _bench_k100_backends(label: String, k: int, dense: bool) -> void:
	for native in [false, true]:
		if native and not BladeSim.native_available():
			continue
		BladeSim.use_native = native
		var state: BladeState = _dense_mesh(k) if dense else _chain(k)
		var t0 := Time.get_ticks_usec()
		BladeSim.simulate(state, _drivers_for(state), DURATION,
				BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
				BladeSim.DEFAULT_SUBSTEPS, true)
		var us := Time.get_ticks_usec() - t0
		print("  %-20s %-26s %7d us" % [
				label, "native (C++ GDExtension)" if native else "gdscript", us])
	BladeSim.use_native = false
