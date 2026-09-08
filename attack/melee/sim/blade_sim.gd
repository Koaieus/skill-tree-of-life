class_name BladeSim
extends RefCounted

## Pure PBD solver. Stateless — all working state lives on BladeState.
## See docs/domain/melee-blade-sim.md for the algorithm and rationale,
## in particular "Substeps, not iterations" for why the constraint-sweep
## budget below is spent on smaller timesteps rather than more passes per
## timestep, and why blade length is measured in hops, not distance.

const DEFAULT_DT: float = 1.0 / 120.0
const DEFAULT_ITERATIONS: int = 16
## Physics substeps per trajectory sample interval. The sample rate (`dt`,
## still `DEFAULT_DT` = 1/120 by default) and the physics rate are
## independent knobs — this is the physics one. `DEFAULT_ITERATIONS` sweeps
## are spent across these substeps rather than all at the coarse `dt`, per
## the XPBD small-steps result (Macklin et al. 2019): constraint error
## scales with dt^2, so four passes at dt/4 converge far better than one
## pass at dt for the same total sweep count.
const DEFAULT_SUBSTEPS: int = 4

## Blade-length axis (#790). "Length" is hop count from the pivot — the
## eccentricity of the pivot within `state.constraints` — never neighbour
## spacing (one constraint's rest length, irrelevant to convergence) and
## never euclidean pivot distance (that's what `velocity_iter_ref` already
## covers). Gauss-Seidel propagates a correction roughly one constraint per
## sweep, so a long blade needs proportionally more total sweeps to
## transmit stiffness pivot-to-tip regardless of how fast it's moving.
##
## A blade at or below this many hops pays the length axis nothing — the
## owner's own example of a blade that already converges at today's budget.
const LENGTH_BASELINE_HOPS: int = 3
## Hop counts beyond this buy no further budget — the ceiling that keeps a
## 100+ member blade from running the sweep budget away. Named here, not
## buried in the scaling expression, so raising it is a deliberate edit.
## Owner-tunable: chosen so a maximally-long, ceiling-clamped blade costs
## roughly 4x today's flat baseline — a starting point, not a spec. See
## bench_blade_sim.gd's worst-case row for the measured multiple; raise or
## lower this (and/or LENGTH_ITER_SCALE below) once there's a felt opinion
## on whether that cost is acceptable.
const LENGTH_ECC_CEILING: int = 40
## Budget multiplier added per hop beyond LENGTH_BASELINE_HOPS, up to the
## ceiling. Tuned alongside LENGTH_ECC_CEILING for the ~4x target above.
const LENGTH_ITER_SCALE: float = 0.08


## Run a full sim, return a per-step trajectory.
##
## - `drivers`: BladeDriver instances, applied in order each step.
## - `velocity_iter_ref`: enables velocity-scaled iterations. When
##   max particle speed reaches this value, iteration count doubles.
##   Pass 0 to disable adaptive scaling (use base_iterations as-is).
## - `substeps`: how many physics steps run per trajectory sample interval
##   (`dt`). `base_iterations` sweeps are split across them, not multiplied
##   by them — see DEFAULT_SUBSTEPS. Trajectory samples are still emitted
##   once per `dt`, never once per substep (hit-scan cost stays independent
##   of this knob). Pass 1 to get today's one-step-per-sample behaviour.
## - `enable_length_scaling`: the blade-length axis (see LENGTH_* consts).
##   Defaults on. Exists as an explicit off-switch so a caller — chiefly the
##   substeps-vs-iterations regression test — can isolate the substep-only
##   claim on a long blade without the length axis also adding budget, which
##   would conflate two separate effects.
static func simulate(
		state: BladeState,
		drivers: Array[BladeDriver],
		duration: float,
		dt: float = DEFAULT_DT,
		base_iterations: int = DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0,
		substeps: int = DEFAULT_SUBSTEPS,
		enable_length_scaling: bool = true) -> BladeTrajectory:
	state.prev_positions = state.positions.duplicate()
	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	# samples[0] is the pose BEFORE any solver step — prepended so
	# samples[k] means "pose at simulated time k*dt" for every k, matching
	# the docstring above (#633). Do not shift sample()'s indexing instead;
	# that was considered and rejected in favor of the data meaning what it says.
	traj.samples = [state.positions.duplicate()]
	# speed_history[0] parallels samples[0]: zero for every particle, since
	# nothing has stepped yet (#779). Freshly rebuilt every simulate() call,
	# never accumulated across calls — see BladeState.speed_history's docstring.
	var zero_speeds := PackedFloat32Array()
	zero_speeds.resize(state.positions.size())
	state.speed_history = [zero_speeds]
	var steps := int(ceil(duration / dt))
	var sub := maxi(substeps, 1)
	var sub_dt := dt / float(sub)
	# One BFS per resolve (#790 pin 3), not per step/substep — length_factor
	# is fixed for the whole swing.
	var length_factor := _length_factor(state.pivot_eccentricity()) if enable_length_scaling else 1.0
	for step in steps:
		var t0 := float(step) * dt
		var step_speeds := zero_speeds
		for s in sub:
			var t := t0 + float(s + 1) * sub_dt
			step_speeds = _step(state, drivers, t, sub_dt, base_iterations, velocity_iter_ref, sub, length_factor)
		traj.samples.append(state.positions.duplicate())
		# The LAST substep's speeds — the physics rate closest to this
		# sample's time, not an average or the step's max (#779).
		state.speed_history.append(step_speeds)
	return traj


## Multiplier on the total sweep budget for one sample interval. 1.0 at or
## below LENGTH_BASELINE_HOPS (a short blade costs no more than it does
## today); rises linearly with hop count past that, clamped at
## LENGTH_ECC_CEILING.
static func _length_factor(eccentricity: int) -> float:
	var over := maxi(0, mini(eccentricity, LENGTH_ECC_CEILING) - LENGTH_BASELINE_HOPS)
	return 1.0 + LENGTH_ITER_SCALE * float(over)


## Returns this substep's per-particle speed (px/s), 0.0 for a static
## particle (the pivot). #779: the caller retains only the LAST substep's
## return per sample interval — see BladeState.speed_history's docstring for
## why an average or this step's max (`max_speed_sq` below, a SEPARATE,
## pre-existing concept feeding the velocity-scaled sweep budget, not this)
## would be the wrong value to carry onto a hit event.
static func _step(
		state: BladeState,
		drivers: Array[BladeDriver],
		t: float,
		dt: float,
		base_iters: int,
		vel_ref: float,
		substeps: int,
		length_factor: float) -> PackedFloat32Array:
	var positions := state.positions
	var prev := state.prev_positions
	var inv_masses := state.inv_masses
	var n := positions.size()
	var speeds := PackedFloat32Array()
	speeds.resize(n)
	# Verlet integrate dynamic particles; track max speed for iter scaling.
	var max_speed_sq := 0.0
	for i in n:
		if inv_masses[i] > 0.0:
			var p := positions[i]
			var v := p - prev[i]
			prev[i] = p
			positions[i] = p + v
			var sp_sq := v.length_squared() / (dt * dt)
			speeds[i] = sqrt(sp_sq)
			if sp_sq > max_speed_sq:
				max_speed_sq = sp_sq
		else:
			prev[i] = positions[i]
	# Drivers override prescribed particles.
	for d in drivers:
		d.apply(positions, t)
	# Sweep budget for this SAMPLE INTERVAL: scale up when particles are
	# moving fast, and when the blade is long (hop count), then split that
	# budget across the substeps composing this interval — spending it on
	# smaller steps rather than more passes per step (#790).
	var budget := float(base_iters)
	if vel_ref > 0.0:
		var max_speed := sqrt(max_speed_sq)
		budget *= 1.0 + max_speed / vel_ref
	budget *= length_factor
	var iters := maxi(1, int(round(budget / float(substeps))))
	# Project constraints.
	for _i in iters:
		for c in state.constraints:
			c.project(positions, inv_masses)
	state.positions = positions
	state.prev_positions = prev
	return speeds
