extends GutTest

## #846 — golden recorded trajectories: the blade solver's determinism contract.
##
## The GDScript solver was the native solver's reference, and
## `test_blade_native_parity.gd` pinned the two bit-identical. #847 deletes that
## reference. What keeps catching the bug class the parity test existed for —
## an FMA contraction slipping back in, a compiler or flag change, a "harmless"
## refactor of the solver loop — is this file: every world below is REPLAYED on
## the shipped native backend and compared, sample for sample, to the fixture
## recorded under `test/unit/attack/fixtures/blade_goldens/`. A drift of one
## ulp anywhere fails it. The tolerance is ZERO and stays zero: `BladeHitScan`
## turns positions into a hit SET, so a last-bit drift near a shape boundary is
## a different attack, not a smaller error. If this goes red, do NOT widen it —
## find out what moved.
##
## This is NOT a cross-machine or multiplayer pin (owner correction on #846,
## 2026-09-10): a peer replays a recorded `AttackRecord` and never re-runs the
## solver for anything authoritative. The claim here is only that the build
## under test reproduces its own recorded trajectories.
##
## Coverage — the axes the parity test covered: the swing clock, the defender
## field (wall, plate, both, a multi-zone cluster), all three entry points
## (`simulate`, `simulate_range` continued and seeded, `simulate_range_field`
## whole and chunked), a bare spine, a clamped (welded) spine, an induced truss,
## a swing that severs, plus every budget knob (substeps, adaptive iterations,
## length scaling on / off / past the ceiling, the coarse AI tier).
##
## FIXTURE FORMAT, two tiers so a regeneration diff stays reviewable: readable
## rows at 6 decimals (one sample per line), and a `DIGEST <section>` line per
## section — SHA-256 over the EXACT float32 / float64 / int byte stream of that
## section (`HashingContext`, not `sha256_text`) — which is the bit-exact
## assertion. A diff that touches only DIGEST lines means sub-1e-6 drift: the
## FMA class exactly.
##
## Regenerating is a DELIBERATE act, never a way to turn a red test green:
## `mise run native:goldens` flips [constant _REGENERATE], runs this script
## alone in its own process, and flips it back; the rewritten fixtures then show
## up as a reviewable diff, and the commit that carries them must say WHY the
## solver's output was supposed to change.
##
## A missing native binary is a FAILURE here, never PENDING — see
## [method before_each]. `mise run native:fetch` cures it.

const _REGENERATE := false
const _FIXTURE_DIR := "res://test/unit/attack/fixtures/blade_goldens/"

const SPACING := 60.0
const DURATION := 0.4
const DT := 1.0 / 120.0

const _DEF_DURATION := 1.2
const _DEF_RADIUS := 24.0
const _ZONE_RADIUS := 32.0

## Every world this file records, in fixture order. Each builder returns a
## world Dictionary: `trajs: Array[Array]` of `[label, BladeTrajectory]`,
## `state: BladeState`, optional `clock` and `field`.
const _CASES: Array[StringName] = [
	&"chain",
	&"truss",
	&"adaptive_iterations",
	&"coarse_ai_tier",
	&"substeps_1",
	&"substeps_8",
	&"substepped_adaptive_truss",
	&"length_scaling_off",
	&"long_blade_clamped_factor",
	&"range_chunked",
	&"range_seeded_from_prev_samples",
	&"severed_coasting_tail",
	&"uniform_damping_tail",
	&"wall_drag",
	&"untouched_wall",
	&"plate_pushout",
	&"clamped_spine_break",
	&"wall_and_plate",
	&"zone_cluster",
	&"defended_chunked",
]

## When true, the `_range` helper bypasses `BladeSim.simulate_range`'s fallback
## and calls `_simulate_native` directly, asserting it did NOT decline. That is
## the vacuity guard: `simulate_range` silently falls through to GDScript for a
## state outside the transliterated subset, and a golden recorded off that
## fallback would pin the wrong solver while reading as native.
var _direct_native := false


func before_each() -> void:
	_direct_native = false
	# The binary is mandatory (#816). A checkout without it must FAIL here, not
	# report PENDING while the suite prints green — that is how #823 shipped 26
	# unverified cases. One command fixes it.
	assert_eq(BladeSim.backend(), &"native",
			"the native blade solver is loaded — run `mise run native:fetch` "
			+ "(or `mise run native:build`) and `mise run refresh`")


# ── Fixtures ──────────────────────────────────────────────────────────────────


func _chain(k: int, radius: float = 20.0) -> BladeState:
	var pos: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in k:
		pos.append(Vector2(float(i) * SPACING, 0.0))
		radii.append(radius)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(pos, 0, edges, radii)


## Chain plus an i-2 brace on every vertex — an induced truss, so constraint
## ORDER matters, not just a line.
func _truss(k: int) -> BladeState:
	var s := _chain(k)
	for i in range(2, k):
		s.edges.append(Vector2i(i - 2, i))
		var rest: float = s.positions[i - 2].distance_to(s.positions[i])
		s.constraints.append(BladeDistanceConstraint.new(i - 2, i, rest))
	return s


func _drivers(s: BladeState) -> Array[BladeDriver]:
	var d: Array[BladeDriver] = [
		BladeArcDriver.new(1, s.positions[0], SPACING, 0.0, TAU, DURATION)
	]
	return d


## The straight arm the defender cases swing, at radii the plate can meet.
func _arm(n: int) -> BladeState:
	return _chain(n, _DEF_RADIUS)


## The same arm welded at every joint — the rigid body that JAMS on a plate
## instead of folding around it, which is the only thing that meters strain.
func _clamped_arm(n: int) -> BladeState:
	var s := _arm(n)
	for i in range(1, n - 1):
		ClampAddon.append_weld_braces(s, i)
	return s


func _arm_drivers(state: BladeState) -> Array[BladeDriver]:
	var out: Array[BladeDriver] = []
	var pivot := state.positions[state.pivot_index]
	for e in state.edges:
		var other := -1
		if e.x == state.pivot_index:
			other = e.y
		elif e.y == state.pivot_index:
			other = e.x
		if other < 0:
			continue
		var offset := state.positions[other] - pivot
		out.append(BladeArcDriver.new(
				other, pivot, offset.length(), offset.angle(), TAU, _DEF_DURATION))
	return out


## One zone `turns` of a turn round the arc the tip sweeps, read off the
## blade's own reach (`.claude/rules/melee-fixtures.md`).
func _zone_on_arc(state: BladeState, turns: float, drag: float, deflect: bool,
		reach: float = 1.0) -> BladeObstacleField:
	var f := BladeObstacleField.new()
	var pivot := state.positions[state.pivot_index]
	var r := pivot.distance_to(state.positions[state.positions.size() - 1])
	f.add_defender_zone(pivot + Vector2.from_angle(turns * TAU) * (r * reach),
			_ZONE_RADIUS, drag, deflect)
	return f


## Five zones straddling particles 2 and 3 at `pose`: two walls and three
## OVERLAPPING plates — the shared-edge summation order and the two-zones-in-one
## iteration overwrite both live here and nowhere else.
func _cluster_field(pose: PackedVector2Array) -> BladeObstacleField:
	var f := BladeObstacleField.new()
	var a := pose[2]
	var b := pose[3]
	f.add_defender_zone(a.lerp(b, -0.4), 30.0, 0.75, false)
	f.add_defender_zone(a, 30.0, 0.0, true)
	f.add_defender_zone(a.lerp(b, 0.5), 34.0, 0.0, true)
	f.add_defender_zone(b, 30.0, 0.0, true)
	f.add_defender_zone(b.lerp(a, -0.4), 30.0, 0.5, false)
	return f


static func _steps(dur: float, dt: float = DT) -> int:
	return int(ceil(dur / dt))


# ── The one stepping seam ─────────────────────────────────────────────────────


## Every case steps through here. Normally that is `BladeSim.simulate_range`
## verbatim (so `simulate`, which is `simulate_range(0, ceil(dur/dt))`, is
## covered by the same call). Under [member _direct_native] it reproduces the
## preamble `simulate_range` runs ahead of the backend split and then calls
## `_simulate_native` itself, failing if the C++ declined the state.
func _range(state: BladeState, drivers: Array[BladeDriver], offset: int, count: int,
		dt: float = DT, iters: int = BladeSim.DEFAULT_ITERATIONS, vel_ref: float = 0.0,
		substeps: int = BladeSim.DEFAULT_SUBSTEPS, length_scaling: bool = true,
		clock: BladeSwingClock = null) -> BladeTrajectory:
	if not _direct_native:
		return BladeSim.simulate_range(state, drivers, offset, count, dt, iters, vel_ref,
				substeps, length_scaling, clock)
	if clock != null:
		for d in drivers:
			if d is BladeArcDriver:
				(d as BladeArcDriver).clock = clock
	if offset == 0:
		state.prev_positions = state.positions.duplicate()
	var length_factor := BladeSim._length_factor(state.pivot_eccentricity()) \
			if length_scaling else 1.0
	var obstacles := state.obstacles
	if obstacles != null:
		obstacles.prepare(state, drivers, clock)
	var traj := BladeSim._simulate_native(state, drivers, offset, count, dt, iters,
			vel_ref, substeps, length_factor, clock, obstacles)
	assert_not_null(traj, "the C++ accepted the state (offset %d, %d steps)" % [offset, count])
	return traj


func _whole(state: BladeState, drivers: Array[BladeDriver], dur: float = DURATION,
		dt: float = DT, iters: int = BladeSim.DEFAULT_ITERATIONS, vel_ref: float = 0.0,
		substeps: int = BladeSim.DEFAULT_SUBSTEPS, length_scaling: bool = true,
		clock: BladeSwingClock = null) -> BladeTrajectory:
	return _range(state, drivers, 0, _steps(dur, dt), dt, iters, vel_ref, substeps,
			length_scaling, clock)


func _world(state: BladeState, trajs: Array, clock: BladeSwingClock = null,
		field: BladeObstacleField = null) -> Dictionary:
	return {state = state, trajs = trajs, clock = clock, field = field}


# ── Cases ─────────────────────────────────────────────────────────────────────


func _build(case_name: StringName) -> Dictionary:
	match case_name:
		&"chain":
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s))]])
		&"truss":
			var s := _truss(8)
			return _world(s, [["swing", _whole(s, _drivers(s))]])
		&"adaptive_iterations":
			# vel_ref > 0 makes the iteration count itself a computed float.
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, DT, 16, 400.0)]])
		&"coarse_ai_tier":
			# The knobs AiBladeRollout's coarse pass uses.
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, 1.0 / 30.0, 4)]])
		&"substeps_1":
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, DT, 16, 0.0, 1)]])
		&"substeps_8":
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, DT, 16, 0.0, 8)]])
		&"substepped_adaptive_truss":
			var s := _truss(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, DT, 16, 400.0, 4)]])
		&"length_scaling_off":
			var s := _chain(8)
			return _world(s, [["swing", _whole(s, _drivers(s), DURATION, DT, 16, 0.0,
					BladeSim.DEFAULT_SUBSTEPS, false)]])
		&"long_blade_clamped_factor":
			# k=48: pivot eccentricity past LENGTH_ECC_CEILING, so length_factor
			# is the clamped value, precomputed GDScript-side and passed in.
			var s := _chain(48)
			return _world(s, [["swing", _whole(s, _drivers(s))]])
		&"range_chunked":
			var steps := _steps(DURATION)
			var cut := steps / 3
			var s := _chain(8)
			var d := _drivers(s)
			var head := _range(s, d, 0, cut)
			var tail := _range(s, d, cut, steps - cut)
			return _world(s, [["head", head], ["tail", tail]])
		&"range_seeded_from_prev_samples":
			# A fresh state seeded from a finished bake's samples[k] /
			# prev_samples[k] — how MeleeAttackPlan.resolve_against lands on a
			# severance sample. The seed pose is recorded too (`head`).
			var k := 37
			var whole_state := _chain(8)
			var whole := _whole(whole_state, _drivers(whole_state))
			var s := _chain(8)
			s.positions = whole.samples[k].duplicate()
			s.prev_positions = whole.prev_samples[k].duplicate()
			var tail := _range(s, _drivers(s), k, _steps(DURATION) - k)
			return _world(s, [["whole", whole], ["seeded_tail", tail]])
		&"severed_coasting_tail":
			# A severance at vertex 3 mid-swing: corpse frozen, 4..7 coast with
			# per-particle drag behind a dead vertex — what a severance writes.
			var steps := _steps(DURATION)
			var cut := 20
			var s := _chain(8)
			var d := _drivers(s)
			var head := _range(s, d, 0, cut)
			s.remove_vertex(3)
			for i in range(4, s.positions.size()):
				s.set_damping(i, BladeState.SEVERED_DRAG)
			var tail := _range(s, d, cut, steps - cut)
			return _world(s, [["head", head], ["severed_tail", tail]])
		&"uniform_damping_tail":
			var steps := _steps(DURATION)
			var cut := 20
			var s := _chain(8)
			var d := _drivers(s)
			var head := _range(s, d, 0, cut)
			for i in s.positions.size():
				s.set_damping(i, BladeState.SEVERED_DRAG)
			var tail := _range(s, d, cut, steps - cut)
			return _world(s, [["head", head], ["damped_tail", tail]])
		&"wall_drag":
			# A wall: sensed, banked on the clock, never pushed out of.
			return _defended(false, 4, 0.15, 1.5, false)
		&"untouched_wall":
			# The clock exists but its zone sits where the blade never goes.
			return _defended(false, 4, 0.15, 1.5, false, 10.0)
		&"plate_pushout":
			return _defended(false, 4, 0.15, 0.0, true)
		&"clamped_spine_break":
			# A welded arm cannot fold, so the driver residual accumulates and
			# an edge breaks — load share, `_pick_edge`'s tie-break, the GLOBAL
			# step the break is stamped with.
			return _defended(true, 4, 0.15, 0.0, true)
		&"wall_and_plate":
			return _defended(true, 4, 0.15, 1.5, true)
		&"zone_cluster":
			var pose := _probe_pose(true, 4, 0.2)
			var s := _clamped_arm(4)
			var field := _cluster_field(pose)
			s.obstacles = field
			var clock := BladeSwingClock.new(_DEF_DURATION)
			var traj := _whole(s, _arm_drivers(s), _DEF_DURATION, DT,
					BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
			return _world(s, [["swing", traj]], clock, field)
		&"defended_chunked":
			# simulate_range_field in two halves: the clock's accumulator and
			# the field's banks cross the chunk boundary.
			var total := _steps(_DEF_DURATION)
			var head_len := total / 2
			var s := _clamped_arm(4)
			var field := _zone_on_arc(s, 0.15, 1.5, true)
			s.obstacles = field
			var clock := BladeSwingClock.new(_DEF_DURATION)
			var drivers := _arm_drivers(s)
			var head := _range(s, drivers, 0, head_len, DT, BladeSim.DEFAULT_ITERATIONS,
					0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
			var tail := _range(s, drivers, head_len, total - head_len, DT,
					BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
			return _world(s, [["head", head], ["tail", tail]], clock, field)
	assert_true(false, "unknown golden case %s" % case_name)
	return {}


func _defended(clamped: bool, k: int, turns: float, drag: float, deflect: bool,
		reach: float = 1.0) -> Dictionary:
	var s: BladeState = _clamped_arm(k) if clamped else _arm(k)
	var field := _zone_on_arc(s, turns, drag, deflect, reach)
	s.obstacles = field
	var clock := BladeSwingClock.new(_DEF_DURATION)
	var traj := _whole(s, _arm_drivers(s), _DEF_DURATION, DT, BladeSim.DEFAULT_ITERATIONS,
			0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	return _world(s, [["swing", traj]], clock, field)


## The pose the blade really passes through at `frac` of a FREE swing, so the
## cluster is built where the blade actually goes. Stepped on whatever backend
## is current — it is part of the recorded world either way.
func _probe_pose(clamped: bool, k: int, frac: float) -> PackedVector2Array:
	var s: BladeState = _clamped_arm(k) if clamped else _arm(k)
	var traj := _whole(s, _arm_drivers(s), _DEF_DURATION)
	return traj.samples[int(float(traj.samples.size() - 1) * frac)]


# ── Serialisation ─────────────────────────────────────────────────────────────
# Text rows for the reviewer, exact bytes for the digest. Both are produced by
# ONE walk over the world (`_Sink`), so a value can never be in one and not the
# other.


class _Sink extends RefCounted:
	var lines: PackedStringArray = []
	var _bytes := PackedByteArray()

	func line(text: String) -> void:
		lines.append(text)

	## One row: a label, then every value both rendered and hashed.
	func row(label: String, values: Array) -> void:
		var parts: PackedStringArray = [label]
		for v in values:
			parts.append(_render(v))
			_bytes.append_array(_exact(v))
		lines.append(" ".join(parts))

	func flush_digest(section: String) -> void:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(_bytes)
		lines.append("DIGEST %s %s" % [section, ctx.finish().hex_encode()])
		_bytes = PackedByteArray()

	static func _render(v: Variant) -> String:
		match typeof(v):
			TYPE_FLOAT:
				return String.num(v, 6)
			TYPE_INT, TYPE_BOOL:
				return str(int(v))
			TYPE_STRING, TYPE_STRING_NAME:
				return String(v)
			TYPE_PACKED_VECTOR2_ARRAY:
				var out: PackedStringArray = []
				for p: Vector2 in v:
					out.append("%s,%s" % [String.num(p.x, 6), String.num(p.y, 6)])
				return "[" + " ".join(out) + "]"
			TYPE_PACKED_FLOAT32_ARRAY:
				var out: PackedStringArray = []
				for f: float in v:
					out.append(String.num(f, 6))
				return "[" + " ".join(out) + "]"
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
				var out: PackedStringArray = []
				for i: int in v:
					out.append(str(i))
				return "[" + " ".join(out) + "]"
		assert(false, "unrenderable golden value type %d" % typeof(v))
		return ""

	## The exact bytes of a value: float32 payloads stay float32, scalar floats
	## are the doubles GDScript holds them as, ints are 64-bit.
	static func _exact(v: Variant) -> PackedByteArray:
		match typeof(v):
			TYPE_FLOAT:
				return PackedFloat64Array([v]).to_byte_array()
			TYPE_INT, TYPE_BOOL:
				return PackedInt64Array([int(v)]).to_byte_array()
			TYPE_STRING, TYPE_STRING_NAME:
				return String(v).to_utf8_buffer()
			TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
				return v.to_byte_array()
		return PackedByteArray()


func _serialize(case_name: StringName, w: Dictionary) -> String:
	var sink := _Sink.new()
	sink.line("CASE %s" % case_name)
	var state: BladeState = w.state
	for entry: Array in w.trajs:
		var label: String = entry[0]
		var traj: BladeTrajectory = entry[1]
		sink.row("TRAJ", [label, "sample_dt", traj.sample_dt, "samples", traj.samples.size(),
				"prev_samples", traj.prev_samples.size()])
		for k in traj.samples.size():
			sink.row("S %d" % k, [traj.samples[k]])
		for k in traj.prev_samples.size():
			sink.row("P %d" % k, [traj.prev_samples[k]])
		sink.flush_digest("traj:" + label)
	# The state as the last call left it: what a caller re-simulating from it
	# starts from, and the chunk-local speed_history (#779) speed-scaled damage
	# reads.
	sink.row("STATE", ["particles", state.positions.size(), "edges", state.edges.size(),
			"constraints", state.constraints.size()])
	sink.row("POS", [state.positions])
	sink.row("PREV", [state.prev_positions])
	sink.row("DAMPING", [state.damping])
	var alive := PackedInt32Array()
	for i in state.positions.size():
		alive.append(0 if state.is_vertex_removed(i) else 1)
	sink.row("ALIVE", [alive])
	sink.row("SPEEDS", ["samples", state.speed_history.size()])
	for k in state.speed_history.size():
		sink.row("V %d" % k, [state.speed_history[k]])
	sink.flush_digest("state")
	var clock: BladeSwingClock = w.clock
	if clock != null:
		sink.row("CLOCK", ["drag", clock.drag, "progress", clock.progress(),
				"warping", clock.is_warping(), "stalled", clock.is_stalled(),
				"banks", clock.history.size()])
		for k in clock.history.size():
			var b: BladeSwingClock.Bank = clock.history[k]
			# keys() in insertion order — the first-wins tie-break the zones'
			# stable-id ordering exists to make reproducible.
			var touched := PackedInt64Array()
			for z in b.touched.keys():
				touched.append(int(z))
			sink.row("C %d" % k, [b.f, b.drag, b.last_t, b.warping, b.stalled, touched])
		sink.flush_digest("clock")
	var field: BladeObstacleField = w.field
	if field != null:
		sink.row("FIELD", ["zones", field.zones.size(), "banks", field.history.size()])
		for k in field.history.size():
			var b: BladeObstacleField.Bank = field.history[k]
			sink.row("F %d" % k, [b.current_step, b.break_edge, b.break_step, b.break_zone,
					b.strain, b.driven_last, b.driven_last_target])
			for z in b.edge_residual.size():
				var d: Dictionary = b.edge_residual[z]
				if d.is_empty():
					continue
				var keys := PackedInt64Array()
				var loads := PackedFloat32Array()
				for e_idx in d.keys():
					keys.append(int(e_idx))
					loads.append(float(d[e_idx]))
				sink.row("R %d %d" % [k, z], [keys, loads])
		# consume_break() stays in GDScript; what the backend does is ARM it.
		var brk: BladeObstacleField.Break = field.consume_break()
		if brk == null:
			sink.row("BREAK", ["none"])
		else:
			sink.row("BREAK", ["edge", brk.edge_idx, "step", brk.step])
		sink.flush_digest("field")
	return "\n".join(sink.lines) + "\n"


static func _header() -> String:
	var out: PackedStringArray = []
	out.append("# GOLDEN BLADE TRAJECTORY — recorded by test_blade_goldens.gd (#846). DO NOT HAND-EDIT.")
	out.append("# Rows are rendered at 6 decimals for review; each `DIGEST <section>` line is SHA-256 over")
	out.append("# that section's EXACT byte stream (float32 payloads as float32, scalars as float64,")
	out.append("# ints as int64) and is the bit-exact assertion. A diff touching only DIGEST lines means")
	out.append("# the solver drifted below 1e-6 — the FMA / compiler-flag class exactly.")
	out.append("#")
	out.append("# Regenerating is a DELIBERATE act, never a way to turn a red test green: run")
	out.append("# `mise run native:goldens` (flips `_REGENERATE`, records in its own process, flips it back)")
	out.append("# and justify WHY the solver's output was supposed to change in the commit message.")
	return "\n".join(out) + "\n"


static func _fixture_path(case_name: StringName) -> String:
	return _FIXTURE_DIR + String(case_name) + ".golden.txt"


## The committed fixture's body: comment lines stripped, so the header is free
## to change without touching a single recorded value.
static func _read_fixture(case_name: StringName) -> String:
	var path := _fixture_path(case_name)
	if not FileAccess.file_exists(path):
		return ""
	var raw := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for l in raw.split("\n"):
		if l.begins_with("#"):
			continue
		kept.append(l)
	return "\n".join(kept).strip_edges(true, true) + "\n"


func _write_fixture(case_name: StringName, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_FIXTURE_DIR))
	var f := FileAccess.open(_fixture_path(case_name), FileAccess.WRITE)
	assert_not_null(f, "opened %s for writing" % _fixture_path(case_name))
	if f == null:
		return
	f.store_string(_header() + body)
	f.close()


## The comparison every case runs: exact text equality, reported as the FIRST
## differing line so a failure names the sample (or the section digest).
func _assert_matches_golden(case_name: StringName, actual: String, what: String) -> void:
	var expected := _read_fixture(case_name)
	if expected.is_empty():
		fail_test("%s: no golden at %s — record it with `mise run native:goldens`"
				% [case_name, _fixture_path(case_name)])
		return
	if actual == expected:
		pass_test("%s: %s reproduces the golden" % [case_name, what])
		return
	var a := actual.split("\n")
	var e := expected.split("\n")
	for i in mini(a.size(), e.size()):
		if a[i] != e[i]:
			fail_test("%s: %s diverges from the golden at line %d\n  golden: %s\n  actual: %s"
					% [case_name, what, i + 1, e[i].left(200), a[i].left(200)])
			return
	fail_test("%s: %s has %d lines, the golden %d" % [case_name, what, a.size(), e.size()])


# ── Tests ─────────────────────────────────────────────────────────────────────


## Acceptance 2: every golden, replayed on the native backend, bit for bit.
## Under `_REGENERATE` this rewrites the fixtures instead and fails on purpose,
## so a regeneration run can never read as green.
func test_the_native_solver_reproduces_every_golden() -> void:
	for case_name in _CASES:
		var text := _serialize(case_name, _build(case_name))
		if _REGENERATE:
			_write_fixture(case_name, text)
			continue
		_assert_matches_golden(case_name, text, "native replay")
	if _REGENERATE:
		fail_test("_REGENERATE is true: %d goldens rewritten under %s — review the diff, "
				% [_CASES.size(), _FIXTURE_DIR]
				+ "then flip it back (mise run native:goldens does) before committing")


## Guards the guard: every case's every chunk is INSIDE the transliterated
## subset, so `simulate_range` really did run the C++ for it. A case the native
## path declined would have been recorded off the GDScript fallback and would
## keep passing on it after #847 deleted... nothing, because the fallback would
## be gone and the call would error — but until then it would pin the wrong
## solver. `_range` asserts non-null per chunk; the output must also equal the
## fallback-capable path's, or the two preambles have diverged.
func test_every_golden_case_runs_on_the_native_path() -> void:
	for case_name in _CASES:
		_direct_native = true
		var direct := _serialize(case_name, _build(case_name))
		_direct_native = false
		var routed := _serialize(case_name, _build(case_name))
		assert_eq(direct, routed, "%s: direct native call equals the routed one" % case_name)


## The recorded worlds are not degenerate: things actually move, drag actually
## bleeds, the clamped spine actually breaks, the cluster actually meters more
## than one plate. Two solvers that both produced zeros would agree perfectly.
func test_the_goldens_are_not_vacuous() -> void:
	var chain := _build(&"chain")
	var peak := 0.0
	for h: PackedFloat32Array in (chain.state as BladeState).speed_history:
		for v in h:
			peak = maxf(peak, v)
	assert_gt(peak, 1.0, "the chain swing moves")

	var severed := _build(&"severed_coasting_tail")
	var plain := _build(&"range_chunked")
	var severed_tail: BladeTrajectory = severed.trajs[1][1]
	var plain_tail: BladeTrajectory = plain.trajs[1][1]
	assert_ne(severed_tail.samples[-1], plain_tail.samples[-1],
			"the severed tail differs from the undamaged one")

	var broken := _build(&"clamped_spine_break")
	assert_true((broken.field as BladeObstacleField)._break_edge >= 0
			or _read_fixture(&"clamped_spine_break").contains("BREAK edge"),
			"the clamped spine arms a break")

	var dragged := _build(&"wall_drag")
	assert_true((dragged.clock as BladeSwingClock).is_warping(), "the wall banked drag")
	var untouched := _build(&"untouched_wall")
	assert_false((untouched.clock as BladeSwingClock).is_warping(),
			"the untouched wall really is never reached")

	var cluster := _build(&"zone_cluster")
	var metering := 0
	for b: BladeObstacleField.Bank in (cluster.field as BladeObstacleField).history:
		var live := 0
		for d: Dictionary in b.edge_residual:
			if not d.is_empty():
				live += 1
		metering = maxi(metering, live)
	assert_gt(metering, 1, "more than one plate banked load in the cluster swing")
