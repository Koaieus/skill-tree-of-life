class_name BladeSim
extends RefCounted

## Pure PBD solver. Stateless — all working state lives on BladeState.
## See docs/domain/melee-blade-sim.md for the algorithm and rationale.

const DEFAULT_DT: float = 1.0 / 120.0
const DEFAULT_ITERATIONS: int = 16


## Run a full sim, return a per-step trajectory.
##
## - `drivers`: BladeDriver instances, applied in order each step.
## - `velocity_iter_ref`: enables velocity-scaled iterations. When
##   max particle speed reaches this value, iteration count doubles.
##   Pass 0 to disable adaptive scaling (use base_iterations as-is).
static func simulate(
		state: BladeState,
		drivers: Array[BladeDriver],
		duration: float,
		dt: float = DEFAULT_DT,
		base_iterations: int = DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0) -> BladeTrajectory:
	state.prev_positions = state.positions.duplicate()
	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	# samples[0] is the pose BEFORE any solver step — prepended so
	# samples[k] means "pose at simulated time k*dt" for every k, matching
	# the docstring above (#633). Do not shift sample()'s indexing instead;
	# that was considered and rejected in favor of the data meaning what it says.
	traj.samples = [state.positions.duplicate()]
	var steps := int(ceil(duration / dt))
	for step in steps:
		var t := float(step) * dt
		_step(state, drivers, t + dt, dt, base_iterations, velocity_iter_ref)
		traj.samples.append(state.positions.duplicate())
	return traj


static func _step(
		state: BladeState,
		drivers: Array[BladeDriver],
		t: float,
		dt: float,
		base_iters: int,
		vel_ref: float) -> void:
	var positions := state.positions
	var prev := state.prev_positions
	var inv_masses := state.inv_masses
	var n := positions.size()
	# Verlet integrate dynamic particles; track max speed for iter scaling.
	var max_speed_sq := 0.0
	for i in n:
		if inv_masses[i] > 0.0:
			var p := positions[i]
			var v := p - prev[i]
			prev[i] = p
			positions[i] = p + v
			var sp_sq := v.length_squared() / (dt * dt)
			if sp_sq > max_speed_sq:
				max_speed_sq = sp_sq
		else:
			prev[i] = positions[i]
	# Drivers override prescribed particles.
	for d in drivers:
		d.apply(positions, t)
	# Iteration count: scale up when particles are moving fast.
	var iters := base_iters
	if vel_ref > 0.0:
		var max_speed := sqrt(max_speed_sq)
		iters = int(float(base_iters) * (1.0 + max_speed / vel_ref))
	# Project constraints.
	for _i in iters:
		for c in state.constraints:
			c.project(positions, inv_masses)
	state.positions = positions
	state.prev_positions = prev
