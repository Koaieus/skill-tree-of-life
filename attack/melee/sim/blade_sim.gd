class_name BladeSim
extends RefCounted

## Pure PBD solver. Stateless — all working state lives on BladeState.
## See docs/domain/melee-blade-sim.md for the algorithm and rationale,
## in particular "Substeps, not iterations" for why the constraint-sweep
## budget below is spent on smaller timesteps rather than more passes per
## timestep, and why blade length is measured in hops, not distance.
##
## One backend (#847): the C++ GDExtension in native/src/blade_solver_native.cpp,
## reached through [method _simulate_native]. The GDScript solver that used to
## live here was a bit-identical mirror of it and is gone — every melee feature
## was being written twice. The binary is MANDATORY: `mise run native:fetch`
## (or `native:build`) puts it in native/bin/, and a checkout without it gets a
## `push_error` naming that command the first time a swing is simulated — never
## a parse error (see [member _native]) and never a silent stand-in.
##
## What stays GDScript-side: BladeState / drivers / constraints as descriptors,
## the pop-gate loop, and `_length_factor`'s BFS, computed here and passed in.
## The determinism pin is test_blade_goldens.gd: twenty recorded trajectories
## the shipped binary must reproduce bit-for-bit.

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

## The BladeSolverNative instance, or null when the extension isn't loaded.
## Resolved through ClassDB rather than by name: writing `BladeSolverNative`
## as a bare identifier would make THIS SCRIPT fail to parse on any machine
## without the binary, which would turn "run `mise run native:fetch`" into a
## name-resolution error under `mise run check`. Instantiated eagerly
## (static-var init) because AiBladeRollout calls simulate() from
## WorkerThreadPool tasks; the method is pure, so one shared instance serves
## every thread.
static var _native: Object = _acquire_native()

## The one-line cure, spelled the same way in every error this file raises.
const _FETCH_HINT := "run `mise run native:fetch` (or `mise run native:build`), then `mise run refresh`"


static func _acquire_native() -> Object:
	if not ClassDB.class_exists(&"BladeSolverNative"):
		return null
	var native: Object = ClassDB.instantiate(&"BladeSolverNative")
	# A binary built before #803 loads fine and has no `simulate_range`; one
	# built before #813 has no `simulate_range_field`. A `call()` on a missing
	# method is null, not an error, so the crash would be `out["samples"]` a
	# line later on every swing. A stale binary is no binary — same error, same
	# cure — rather than a half-loaded extension.
	if (native == null or not native.has_method(&"simulate_range")
			or not native.has_method(&"simulate_range_field")):
		push_error("BladeSolverNative is stale (built before #813) — " + _FETCH_HINT)
		return null
	return native


## True when the GDExtension loaded. False is a broken checkout, not a mode:
## every simulate() will push_error and return null.
static func native_available() -> bool:
	return _native != null


## &"native" when the extension loaded, &"missing" otherwise. The only backend
## there is; kept as a name because the bench and the goldens' before_each
## report it.
static func backend() -> StringName:
	return &"native" if _native != null else &"missing"


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
## - `damping` lives on the state ([member BladeState.damping]), not here: a
##   severance leaves SOME particles coasting and the rest driven, so the bleed
##   is per-particle (#801). An empty array — what every ordinary swing has —
##   skips the multiply entirely, and a zero entry multiplies by exactly 1.0,
##   so "drag 0 is bit-identical to undamped" holds per particle.
## - `clock`: optional [BladeSwingClock] (#780). Present whenever the swing has
##   a defender field at all — every [BladeArcDriver] then reads its angular
##   progress instead of deriving progress from `t`, and [BladeObstacleField]
##   banks a wall contact onto it as its projection pass finds one (#811). Null
##   — what a fieldless swing passes — leaves both the drivers and this loop on
##   the exact expressions they used before drag existed. A field with walls in
##   it and a null clock senses no drag at all, so the two travel together.
static func simulate(
		state: BladeState,
		drivers: Array[BladeDriver],
		duration: float,
		dt: float = DEFAULT_DT,
		base_iterations: int = DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0,
		substeps: int = DEFAULT_SUBSTEPS,
		enable_length_scaling: bool = true,
		clock: BladeSwingClock = null) -> BladeTrajectory:
	return simulate_range(
			state, drivers, 0, int(ceil(duration / dt)), dt, base_iterations,
			velocity_iter_ref, substeps, enable_length_scaling, clock)


## Run `step_count` steps of the swing starting at GLOBAL step `step_offset`,
## and return the trajectory for exactly that span (#801).
##
## [b]This is the only stepping loop.[/b] [method simulate] is
## `simulate_range(0, ceil(duration / dt))` — there is no second integrator for
## a continued chunk, which is the whole point: a chunk is the same function
## called with a different offset.
##
## [b]`step_offset` is an INTEGER and that is load-bearing.[/b] Every substep's
## time is `float(step_offset + local_step) * dt + float(s + 1) * sub_dt`, so a
## run split into chunks is BIT-IDENTICAL to the unchunked one. Carrying a float
## `t_start` across chunks instead would drift in the last bits, and
## `test_blade_chunked_parity.gd` pins that it does not.
##
## `step_offset == 0` resets the Verlet history (`prev_positions = positions`,
## i.e. at rest). Any other offset [b]trusts [member BladeState.prev_positions]
## as it stands[/b] — that is the continue-from-state path, and the caller is
## responsible for the state being exactly what the previous chunk left (see
## [method MeleeAttackPlan.resolve_against], which reads it off the previous
## bake's [member BladeTrajectory.prev_samples] at the severance sample).
##
## The returned trajectory's `samples[0]` is the pose AT `step_offset` — before
## this chunk's first step — so local sample `j` is global sample
## `step_offset + j`, and the two chunks of a split run overlap in exactly one
## sample. Same for [member BladeState.speed_history], which this rebuilds
## chunk-local (zeros for `samples[0]`, then the last substep's speeds) rather
## than accumulating across calls.
static func simulate_range(
		state: BladeState,
		drivers: Array[BladeDriver],
		step_offset: int,
		step_count: int,
		dt: float = DEFAULT_DT,
		base_iterations: int = DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0,
		substeps: int = DEFAULT_SUBSTEPS,
		enable_length_scaling: bool = true,
		clock: BladeSwingClock = null) -> BladeTrajectory:
	# One clock per SWING, shared by every arc driver: they all describe one
	# rigid body turning about one pivot, so a per-driver clock would shear the
	# blade. Assigned here rather than by the caller so `simulate` stays the only
	# thing that has to know a clock exists. A CONTINUED chunk is handed the same
	# clock instance the previous chunk ticked (#780 is sim state: `_f`, banked
	# `drag` and `touched` all carry) — building a fresh one mid-swing would
	# un-bank a Fortification wall's drag and stop it sheltering what is behind it.
	if clock != null:
		for d in drivers:
			if d is BladeArcDriver:
				(d as BladeArcDriver).clock = clock
	if step_offset == 0:
		state.prev_positions = state.positions.duplicate()
	# One BFS per resolve (#790 pin 3), not per step/substep — length_factor
	# is fixed for the whole swing. Computed here, ahead of the backend split,
	# so the native path consumes the SAME number rather than re-deriving the
	# BFS in C++ (#798): one implementation of the length axis, not two.
	# `enable_length_scaling` is a budget-shaping knob and crosses as this
	# factor; `substeps` crosses as itself (the C++ clamps it to >= 1).
	var length_factor := _length_factor(state.pivot_eccentricity()) if enable_length_scaling else 1.0
	# Bunker field (#781): bind it to THIS call's driver list and edge set —
	# both change after a severance — so it meters the right particles.
	var obstacles := state.obstacles
	if obstacles != null:
		# The clock goes in with it (#811): a wall contact is sensed by the
		# field's projection pass and banked straight onto the clock, so the
		# field needs the swing's accumulator, not just its geometry.
		obstacles.prepare(state, drivers, clock)
	if _native == null:
		push_error("BladeSim: no native blade solver in this checkout — " + _FETCH_HINT)
		return null
	var traj := _simulate_native(state, drivers, step_offset, step_count, dt,
			base_iterations, velocity_iter_ref, substeps, length_factor,
			clock, obstacles)
	if traj == null:
		# `_simulate_native` explains which check declined; this names the swing.
		push_error("BladeSim: the native solver declined this swing (%d particles, "
				% state.positions.size()
				+ "%d constraints, %d drivers) — see the error above"
				% [state.constraints.size(), drivers.size()])
	# Null is DELIBERATE. A synthesised zero-step trajectory would turn a missing
	# binary into a swing that hits nothing — green for every "nothing severed"
	# test and invisible in play — which is the #823 failure (26 cases reviewed
	# as verified off a fallback) that #816 exists to kill. The callers
	# (MeleeAttackPlan.resolve_against, AiBladeRollout, SkillBlade) deref it on
	# the next line and stop there, with the push_error above as the cause.
	return traj


## Flatten state + drivers into packed buffers and hand them to the extension.
##
## Returns null — after a push_error saying why — if anything in the state is
## outside the transliterated subset. The type checks are deliberately EXACT
## (`get_script() ==`, not `is`): a subclass overriding project() or apply()
## would be silently ignored by the C++ loop, and there is no second solver to
## hand it to, so it is refused rather than approximated. Every decline below
## is a programming error at the call site, not a supported state.
##
## `length_factor` arrives precomputed (see simulate) rather than being
## re-derived in C++ — the BFS runs once per resolve, so porting it would buy
## nothing and would put the length axis's definition in two places.
##
## `step_offset` / `step_count` cross the boundary as the INTEGERS they are
## (#803). The earlier shape passed `float(step_count) * dt` and let the C++
## `ceil` it back — a float round trip that happened to be exact for a run
## from 0 and would not have been for an offset.
##
## A `clock` and/or an `obstacles` field routes to `simulate_range_field`
## instead (#813), with the clock's six mutable fields and the field's eight
## crossing as plain values and coming back advanced, plus one Bank-shaped
## Dictionary per sample for each. That is the alternative to a per-iteration
## constraint callback into GDScript, which would fire in the solver's
## innermost loop and cost more than the backend saves.
static func _simulate_native(
		state: BladeState,
		drivers: Array[BladeDriver],
		step_offset: int,
		step_count: int,
		dt: float,
		base_iterations: int,
		velocity_iter_ref: float,
		substeps: int,
		length_factor: float,
		clock: BladeSwingClock = null,
		obstacles: BladeObstacleField = null) -> BladeTrajectory:
	# The C++ refuses these with an error and an empty Dictionary; decline up
	# front with a message that names the array, not a null crash a line later.
	if state.prev_positions.size() != state.positions.size():
		return _decline("prev_positions does not parallel positions")
	if not state.damping.is_empty() and state.damping.size() != state.positions.size():
		return _decline("damping does not parallel positions")
	var constraint_ab := PackedInt32Array()
	var constraint_scalars := PackedFloat64Array()
	for c in state.constraints:
		if c.get_script() != BladeDistanceConstraint:
			return _decline("constraint %s is not a plain BladeDistanceConstraint" % c)
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
			return _decline("driver %s is not a plain BladeArcDriver" % d)
		var ad := d as BladeArcDriver
		# Only the default sine-in-out ease is transliterated. A custom
		# Callable would need a per-step call back into GDScript, which is the
		# whole cost the backend removes — a new ease is a C++ change.
		if ad.ease.get_object() != ad or ad.ease.get_method() != &"_sine_in_out":
			return _decline("BladeArcDriver.ease is not the built-in _sine_in_out")
		driver_particles.append(ad.particle)
		driver_centers.append(ad.center)
		driver_scalars.append(ad.radius)
		driver_scalars.append(ad.start_angle)
		driver_scalars.append(ad.sweep)
		driver_scalars.append(ad.duration)

	# Dynamic call: `_native` is a plain Object here (see _acquire_native).
	var out: Dictionary
	var defended := clock != null or obstacles != null
	if not defended:
		out = _native.call(
				&"simulate_range",
				state.positions, state.prev_positions, state.inv_masses,
				constraint_ab, constraint_scalars,
				driver_particles, driver_centers, driver_scalars,
				state.damping, step_offset, step_count,
				dt, base_iterations, velocity_iter_ref,
				substeps, length_factor)
		if out.is_empty():
			return _decline("BladeSolverNative.simulate_range refused the inputs")
	else:
		var field_inputs: Dictionary
		if obstacles != null:
			# Exact, like the constraint and driver checks above and for the
			# same reason: a subclass overriding project() or end_substep()
			# would be silently ignored by the C++ loop.
			if obstacles.get_script() != BladeObstacleField:
				return _decline("obstacles %s is not a plain BladeObstacleField" % obstacles)
			if not obstacles.native_supported():
				return _decline("BladeObstacleField.trace is diagnostic-only and outside "
						+ "the native solver's subset since #847")
			# The C++ capsule pass indexes `radii[e.x]` unguarded — a short
			# array would be a read past the end, so decline instead.
			if state.radii.size() != state.positions.size():
				return _decline("radii does not parallel positions")
			field_inputs = obstacles.native_inputs()
		else:
			# A clock with no field: nothing can bank drag, so this is the
			# plain loop plus `_last_t` bookkeeping — but the clock's history
			# still has to come back, so it goes through the same entry point.
			field_inputs = {
				"has_field": false,
				"has_clock": true,
				"clock_duration": clock.duration,
			}
		var sim_state: Dictionary = {}
		if clock != null:
			sim_state["clock_state"] = clock.native_state()
		if obstacles != null:
			sim_state["field_state"] = obstacles.native_state()
		out = _native.call(
				&"simulate_range_field",
				state.positions, state.prev_positions, state.inv_masses,
				constraint_ab, constraint_scalars,
				driver_particles, driver_centers, driver_scalars,
				state.damping, step_offset, step_count,
				dt, base_iterations, velocity_iter_ref,
				substeps, length_factor, field_inputs, sim_state)
		# The C++ ERR_FAILs to an empty Dictionary on a malformed boundary,
		# having printed its own reason.
		if out.is_empty():
			return _decline("BladeSolverNative.simulate_range_field refused the inputs")
		# `history[0]` is the bank ON ENTRY, and it is GDScript's to take —
		# captured here, before apply_native_state moves the objects on. The
		# C++ returns [1..step_count], parallel to `samples[1..]`.
		if clock != null:
			var clock_hist: Array[BladeSwingClock.Bank] = [clock.capture()]
			for h: Dictionary in (out["clock_history"] as Array):
				clock_hist.append(BladeSwingClock.bank_from_native(h))
			clock.apply_native_state(out["clock_state"])
			clock.history = clock_hist
		if obstacles != null:
			var field_hist: Array[BladeObstacleField.Bank] = [obstacles.capture()]
			for h: Dictionary in (out["field_history"] as Array):
				field_hist.append(BladeObstacleField.bank_from_native(h))
			obstacles.apply_native_state(out["field_state"])
			obstacles.history = field_hist

	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	traj.samples.assign(out["samples"])
	traj.prev_samples.assign(out["prev_samples"])
	# simulate()'s contract is that the state advances in place — including
	# speed_history (#779): zeros for sample 0, then the LAST substep's speeds.
	state.positions = out["positions"]
	state.prev_positions = out["prev_positions"]
	state.speed_history.assign(out["speed_history"])
	return traj


## Every refusal in [method _simulate_native] goes through here so the reason
## is printed once, at the check that knows it. Always returns null.
static func _decline(why: String) -> BladeTrajectory:
	push_error("BladeSim: cannot simulate natively — " + why)
	return null


## Multiplier on the total sweep budget for one sample interval. 1.0 at or
## below LENGTH_BASELINE_HOPS (a short blade costs no more than it does
## today); rises linearly with hop count past that, clamped at
## LENGTH_ECC_CEILING.
static func _length_factor(eccentricity: int) -> float:
	var over := maxi(0, mini(eccentricity, LENGTH_ECC_CEILING) - LENGTH_BASELINE_HOPS)
	return 1.0 + LENGTH_ITER_SCALE * float(over)
