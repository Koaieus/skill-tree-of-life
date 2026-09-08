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
	print("--- BladeSim.simulate, solver only, %.1fs swing ---" % DURATION)
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

	print("--- #790: 100-node / ~250-constraint swing, today's settings vs substepped ---")
	_bench_substep_config("braced mesh (realistic density)", 100, true)
	print("--- #790: 100-node WHIP (worst case for the length axis — pivot ecc ~99) ---")
	_bench_substep_config("pure chain (whip)", 100, false)
	quit()


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
