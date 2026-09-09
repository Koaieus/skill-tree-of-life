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
	var native: Object = ClassDB.instantiate(&"BladeSolverNative")
	# A binary built before #803 loads fine and has no `simulate_range` — and a
	# `call()` on a missing method is null, not an error, so the crash would be
	# `out["samples"]` a line later on every swing. Treat a stale binary as no
	# binary: the GDScript fallback is a supported state, a half-loaded
	# extension is not. `mise run native:build` cures it.
	if native == null or not native.has_method(&"simulate_range"):
		push_warning("BladeSolverNative predates #803 (no simulate_range) — "
				+ "using the GDScript solver. Rebuild: `mise run native:build`.")
		return null
	return native


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
	var sub_count := maxi(substeps, 1)
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
	var length_factor := _length_factor(state.pivot_eccentricity()) if enable_length_scaling else 1.0
	var damping := state.damping
	# Bunker field (#781): bind it to THIS call's driver list and edge set —
	# both change after a severance — so it meters the right particles.
	var obstacles := state.obstacles
	if obstacles != null:
		# The clock goes in with it (#811): a wall contact is sensed by the
		# field's projection pass and banked straight onto the clock, so the
		# field needs the swing's accumulator, not just its geometry.
		obstacles.prepare(state, drivers, clock)
	# The native transliteration continues from `prev_positions`, takes the
	# integer step offset and the per-particle damping array (#803), so a
	# re-baked tail after a severance (#801) runs native like the head did. The
	# two things it does not model are a warpable clock — it derives `f` from
	# `t` inline, and a dragged swing (#780) accumulates `_f` in float by
	# design — and a bunker field (#781), whose pushout and strain accumulator
	# live in GDScript. Either in range and the swing takes GDScript, whole.
	if _native != null and use_native and clock == null and obstacles == null:
		# Returns null when the state holds a constraint or driver the native
		# path doesn't know — then we just fall through to GDScript.
		var native_traj := _simulate_native(state, drivers, step_offset, step_count, dt,
				base_iterations, velocity_iter_ref, substeps, length_factor)
		if native_traj != null:
			return native_traj
	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	# samples[0] is the pose BEFORE any solver step of THIS chunk — prepended so
	# samples[j] means "pose at simulated time (step_offset + j)*dt" for every j,
	# matching the docstring above (#633). Do not shift sample()'s indexing
	# instead; that was considered and rejected in favor of the data meaning
	# what it says.
	traj.samples = [state.positions.duplicate()]
	# prev_samples[0] parallels it: the Verlet history on entry (#803).
	traj.prev_samples = [state.prev_positions.duplicate()]
	# The clock's per-sample history is chunk-local for the same reason
	# speed_history is — see BladeSwingClock.history.
	if clock != null:
		clock.history = [clock.capture()]
	# The bunker field banks the same way, and for the same rewind (#781/#803):
	# the bank at the severance sample already holds the ARMED break, so
	# `restore` + `consume_break` lands it without re-running the head.
	if obstacles != null:
		obstacles.history = [obstacles.capture()]
	# speed_history[0] parallels samples[0]: zero for every particle, since
	# nothing has stepped yet (#779). Freshly rebuilt every call, never
	# accumulated across calls — see BladeState.speed_history's docstring.
	var zero_speeds := PackedFloat32Array()
	zero_speeds.resize(state.positions.size())
	state.speed_history = [zero_speeds]
	var sub := sub_count
	var sub_dt := dt / float(sub)
	for local_step in step_count:
		# The INTEGER global step index — never an accumulated float offset.
		var t0 := float(step_offset + local_step) * dt
		var step_speeds := zero_speeds
		if obstacles != null:
			obstacles.begin_sample(step_offset + local_step + 1)
		for s in sub:
			var t := t0 + float(s + 1) * sub_dt
			step_speeds = _step(state, drivers, t, sub_dt, base_iterations,
					velocity_iter_ref, sub, length_factor, damping, clock)
		# Drag is no longer sensed here (#811): BladeObstacleField.project tests
		# both zone kinds against one geometry, inside the substep, and banks a
		# wall contact on the clock as it finds it. What is left is the per-sample
		# bank the resolve loop rewinds to. Whatever was banked slows the arc from
		# the NEXT substep on — never the approach to the zone itself.
		if clock != null:
			clock.history.append(clock.capture())
		if obstacles != null:
			obstacles.history.append(obstacles.capture())
		traj.samples.append(state.positions.duplicate())
		traj.prev_samples.append(state.prev_positions.duplicate())
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
##
## `step_offset` / `step_count` cross the boundary as the INTEGERS they are
## (#803). The earlier shape passed `float(step_count) * dt` and let the C++
## `ceil` it back — a float round trip that happened to be exact for a run
## from 0 and would not have been for an offset.
static func _simulate_native(
		state: BladeState,
		drivers: Array[BladeDriver],
		step_offset: int,
		step_count: int,
		dt: float,
		base_iterations: int,
		velocity_iter_ref: float,
		substeps: int,
		length_factor: float) -> BladeTrajectory:
	# The GDScript loop would index-error on these; the C++ refuses them with
	# an error and an empty Dictionary. Decline up front so the GDScript path
	# produces the error, not a null-Dictionary crash a line later.
	if state.prev_positions.size() != state.positions.size():
		return null
	if not state.damping.is_empty() and state.damping.size() != state.positions.size():
		return null
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
			&"simulate_range",
			state.positions, state.prev_positions, state.inv_masses,
			constraint_ab, constraint_scalars,
			driver_particles, driver_centers, driver_scalars,
			state.damping, step_offset, step_count,
			dt, base_iterations, velocity_iter_ref,
			substeps, length_factor)

	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	traj.samples.assign(out["samples"])
	traj.prev_samples.assign(out["prev_samples"])
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
		damping: PackedFloat32Array = PackedFloat32Array(),
		clock: BladeSwingClock = null) -> PackedFloat32Array:
	# Per-particle, per-substep velocity retention (#801). An EMPTY array — every
	# ordinary swing — skips the multiply outright, so the driven path and the
	# native parity test are untouched by this knob's existence; and a zero entry
	# yields EXACTLY 1.0, and multiplying a Vector2 by exactly 1.0 is
	# bit-identical to not multiplying at all, so "drag 0 coasts undecelerated"
	# survives per particle rather than only for a whole body (#186).
	var has_damping := not damping.is_empty()
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
			if has_damping:
				v *= maxf(0.0, 1.0 - float(damping[i]) * dt)
			prev[i] = p
			positions[i] = p + v
			var sp_sq := v.length_squared() / (dt * dt)
			speeds[i] = sqrt(sp_sq)
			if sp_sq > max_speed_sq:
				max_speed_sq = sp_sq
		else:
			prev[i] = positions[i]
	# Open the substep on the swing clock BEFORE the drivers read it, so a
	# warping clock hands them this substep's advanced progress (#780). Before
	# the blade's first fortified contact this only records `t` and the drivers
	# fall through to their original expression.
	if clock != null:
		clock.tick(t, dt)
	# Drivers override prescribed particles.
	for d in drivers:
		d.apply(positions, t)
	var obstacles := state.obstacles
	if obstacles != null:
		obstacles.after_drivers(positions)
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
	# Project constraints. The bunker field goes LAST in every iteration so the
	# pass ends outside every plate (#781) — that ordering is what makes
	# SHATTER_DISTANCE a visual penetration budget and not just a gameplay one.
	for _i in iters:
		for c in state.constraints:
			c.project(positions, inv_masses)
		if obstacles != null:
			obstacles.project(positions, inv_masses)
	if obstacles != null:
		obstacles.end_substep(positions, clock)
	state.positions = positions
	state.prev_positions = prev
	return speeds
