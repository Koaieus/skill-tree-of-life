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
