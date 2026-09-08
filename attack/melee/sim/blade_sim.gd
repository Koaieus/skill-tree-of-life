class_name BladeSim
extends RefCounted

## Pure PBD solver. Stateless — all working state lives on BladeState.
## See docs/domain/melee-blade-sim.md for the algorithm and rationale,
## in particular "Substeps, not iterations" for why the constraint-sweep
## budget below is spent on smaller timesteps rather than more passes per
## timestep, and why blade length is measured in hops, not distance.
##
## Two interchangeable backends (#798): a GDScript one (below) and a C++
## GDExtension one (native/src/blade_solver_native.cpp). The native path is a
## strict transliteration — same expressions, same evaluation order, same
## real_t/double split — and test_blade_native_parity.gd pins the two to
## BIT-IDENTICAL output. Neither is a "fast approximate" mode.
##
## Which one runs: native when the extension loaded AND [member use_native] is
## true. A checkout with no built binary silently takes the GDScript path, so
## `mise run test` is green on a machine that has never run `scons`.

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

## Set false to force the GDScript solver even when the extension is loaded.
## This is the differential-test and bench handle — flip it, run, flip back.
## Not a project setting on purpose: the two backends agree bit-for-bit, so
## there is nothing for a player to choose between.
static var use_native: bool = true

## The BladeSolverNative instance, or null when the extension isn't loaded.
## Resolved through ClassDB rather than by name: writing `BladeSolverNative`
## as a bare identifier would make THIS SCRIPT fail to parse on any machine
## without the binary, which is exactly the fallback the extension exists to
## avoid. Instantiated eagerly (static-var init) because AiBladeRollout calls
## simulate() from WorkerThreadPool tasks; the method is pure, so one shared
## instance serves every thread.
static var _native: Object = _acquire_native()


static func _acquire_native() -> Object:
	if OS.get_environment("BLADE_SIM_BACKEND") == "gdscript":
		return null
	if not ClassDB.class_exists(&"BladeSolverNative"):
		return null
	return ClassDB.instantiate(&"BladeSolverNative")


## True when the GDExtension loaded — independent of [member use_native].
static func native_available() -> bool:
	return _native != null


## &"native" or &"gdscript" — whichever the next simulate() will actually use
## for a canonical state. Reported by the bench and the parity test.
static func backend() -> StringName:
	return &"native" if (_native != null and use_native) else &"gdscript"


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
## - `linear_damping`: per-second velocity bleed applied to every dynamic
##   particle (#186's drag on an unpinned fragment). 0 — the default, and
##   what every driven swing passes — is an exact no-op: the retention
##   factor is exactly 1.0 and the integrator is bit-identical to the
##   undamped one, so a fragment with drag 0 coasts undecelerated.
## - `initial_velocities`: optional per-particle velocity (px/s) to start
##   from, seeded into `prev_positions` instead of the usual "at rest"
##   reset. Empty (the default) means at rest. A free-flight fragment passes
##   its velocity at the moment of separation here.
static func simulate(
		state: BladeState,
		drivers: Array[BladeDriver],
		duration: float,
		dt: float = DEFAULT_DT,
		base_iterations: int = DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0,
		substeps: int = DEFAULT_SUBSTEPS,
		enable_length_scaling: bool = true,
		linear_damping: float = 0.0,
		initial_velocities: PackedVector2Array = PackedVector2Array()) -> BladeTrajectory:
	var sub_count := maxi(substeps, 1)
	if initial_velocities.is_empty():
		state.prev_positions = state.positions.duplicate()
	else:
		# Seed the Verlet history so the FIRST substep's implied velocity is
		# exactly `initial_velocities` (#186): `_step` reads velocity as
		# `positions - prev_positions` over ONE substep, so the offset is
		# scaled by the substep dt, not by `dt`. This is the whole reason a
		# free-flight fragment continues from its separation velocity instead
		# of restarting from rest.
		var sub_dt0 := dt / float(sub_count)
		var seeded := state.positions.duplicate()
		for i in seeded.size():
			var v: Vector2 = initial_velocities[i] if i < initial_velocities.size() else Vector2.ZERO
			seeded[i] = state.positions[i] - v * sub_dt0
		state.prev_positions = seeded
	# One BFS per resolve (#790 pin 3), not per step/substep — length_factor
	# is fixed for the whole swing. Computed here, ahead of the backend split,
	# so the native path consumes the SAME number rather than re-deriving the
	# BFS in C++ (#798): one implementation of the length axis, not two.
	var length_factor := _length_factor(state.pivot_eccentricity()) if enable_length_scaling else 1.0
	# The native transliteration takes neither a damping term nor a seeded
	# Verlet history (it receives `positions`, never `prev_positions`), so a
	# free-flight pass (#186) takes the GDScript path by construction rather
	# than silently losing its drag or its separation velocity. Both knobs are
	# off in every driven-swing call, so the ordinary swing is untouched.
	if _native != null and use_native \
			and is_zero_approx(linear_damping) and initial_velocities.is_empty():
		# Returns null when the state holds a constraint or driver the native
		# path doesn't know — then we just fall through to GDScript.
		var native_traj := _simulate_native(state, drivers, duration, dt,
				base_iterations, velocity_iter_ref, substeps, length_factor)
		if native_traj != null:
			return native_traj
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
	var sub := sub_count
	var sub_dt := dt / float(sub)
	for step in steps:
		var t0 := float(step) * dt
		var step_speeds := zero_speeds
		for s in sub:
			var t := t0 + float(s + 1) * sub_dt
			step_speeds = _step(state, drivers, t, sub_dt, base_iterations,
					velocity_iter_ref, sub, length_factor, linear_damping)
		traj.samples.append(state.positions.duplicate())
		# The LAST substep's speeds — the physics rate closest to this
		# sample's time, not an average or the step's max (#779).
		state.speed_history.append(step_speeds)
	return traj


## Flatten state + drivers into packed buffers and hand them to the extension.
##
## Returns null — meaning "caller, use GDScript" — if anything in the state is
## outside the transliterated subset. The type checks are deliberately EXACT
## (`get_script() ==`, not `is`): a hypothetical subclass overriding project()
## or apply() would be silently ignored by the C++ loop, so it must fall back.
##
## `length_factor` arrives precomputed (see simulate) rather than being
## re-derived in C++ — the BFS runs once per resolve, so porting it would buy
## nothing and would put the length axis's definition in two places.
static func _simulate_native(
		state: BladeState,
		drivers: Array[BladeDriver],
		duration: float,
		dt: float,
		base_iterations: int,
		velocity_iter_ref: float,
		substeps: int,
		length_factor: float) -> BladeTrajectory:
	var constraint_ab := PackedInt32Array()
	var constraint_scalars := PackedFloat64Array()
	for c in state.constraints:
		if c.get_script() != BladeDistanceConstraint:
			return null
		var dc := c as BladeDistanceConstraint
		constraint_ab.append(dc.a)
		constraint_ab.append(dc.b)
		constraint_scalars.append(dc.rest)
		constraint_scalars.append(dc.compliance)

	var driver_particles := PackedInt32Array()
	var driver_centers := PackedVector2Array()
	var driver_scalars := PackedFloat64Array()
	for d in drivers:
		if d.get_script() != BladeArcDriver:
			return null
		var ad := d as BladeArcDriver
		# Only the default sine-in-out ease is transliterated. A custom
		# Callable would need a per-step call back into GDScript, which is the
		# whole cost this port removes — so it falls back instead.
		if ad.ease.get_object() != ad or ad.ease.get_method() != &"_sine_in_out":
			return null
		driver_particles.append(ad.particle)
		driver_centers.append(ad.center)
		driver_scalars.append(ad.radius)
		driver_scalars.append(ad.start_angle)
		driver_scalars.append(ad.sweep)
		driver_scalars.append(ad.duration)

	# Dynamic call: `_native` is a plain Object here (see _acquire_native).
	var out: Dictionary = _native.call(
			&"simulate",
			state.positions, state.inv_masses,
			constraint_ab, constraint_scalars,
			driver_particles, driver_centers, driver_scalars,
			duration, dt, base_iterations, velocity_iter_ref,
			substeps, length_factor)

	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	traj.samples.assign(out["samples"])
	# simulate()'s contract is that the state advances in place — including
	# speed_history (#779), which the native loop builds on the same rule the
	# GDScript one does: zeros for sample 0, then the LAST substep's speeds.
	state.positions = out["positions"]
	state.prev_positions = out["prev_positions"]
	state.speed_history.assign(out["speed_history"])
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
		length_factor: float,
		linear_damping: float = 0.0) -> PackedFloat32Array:
	# Per-substep velocity retention. `linear_damping == 0.0` yields EXACTLY
	# 1.0, and multiplying a Vector2 by exactly 1.0 is bit-identical to not
	# multiplying at all — which is what keeps the driven-swing path (and the
	# native parity test) untouched by this knob's existence (#186).
	var damp := maxf(0.0, 1.0 - linear_damping * dt)
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
			var v := (p - prev[i]) * damp
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
