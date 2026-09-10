@tool
class_name ShatterField
extends MultiMeshInstance2D
## The pooled, scrub-driven shard field a dying object fragments into (#835).
## Blade pops (#787) and node deaths (#257) both spawn into one of these
## instead of each rolling their own particle sphere.
##
## **The operation:** take an object that is dying, replace it with pieces that
## inherit its momentum, and let them coast and fizzle. The owner's rule for
## how far a piece travels is the whole motion model — *"how far they travel
## depends on their momentum at disconnection + simulation time left, that's
## all really"* — so a shard's position is its seed velocity integrated over
## elapsed window time. No drag, no authored travel distance.
##
## **What lives here vs. in the consumer.** This node owns the shard *field*:
## the one shared quad every shard everywhere is drawn as, the per-instance
## packing, the pool, and the motion/fade curve in
## `ui/vfx/shatter/shatter_motion.gdshaderinc`. The consumer owns what a shard
## *looks like* — a `ShaderMaterial` whose shader `#include`s that file (see
## `shatter_shard.gdshader`, the flat-tint reference look) and decides the
## fragment's colour inside the cell the include hands it. GLSL has no
## inheritance; the include IS the reuse.
##
## **One draw call, by construction.** A single `MultiMeshInstance2D` over ONE
## unit `QuadMesh`, oversized [constant OVERSIZE]x the source radius so a shard
## can spin about its own pivot (and #257 can leak rays) without leaving the
## quad. Every shard is that same quad; its *shape* is decided in the fragment
## shader (analytic Voronoi: a fragment belongs to cell K iff seed K is its
## nearest, `discard` otherwise). Per-shard variation rides `COLOR` +
## `INSTANCE_CUSTOM` and the instance transform, never `instance uniform`s (a
## MultiMesh's instances share one CanvasItem, so those cannot vary per shard)
## and never per-shard uniforms. Same idiom as `graph/edge.gd` +
## `graph/edge_mesh.gdshader`.
##
## **Progress is supplied, never self-timed** (`.claude/rules/presentation-clock.md`).
## The field starts no `Tween`, reads no wall clock and has no `_process`. The
## consumer sets [member elapsed] on *its* clock (trajectory time for #787,
## the cascade clock for #257) and the shader derives every shard's progress
## from that one uniform against the shard's own spawn time. Seeking backwards
## just sets a smaller number: nothing on the CPU accumulates, so
## `elapsed = t1; elapsed = t0; elapsed = t1` leaves every pushed value
## byte-identical. The one caveat is the pool — see [method spawn_shatter].
##
## **Packing** (must match `shatter_motion.gdshaderinc`'s `shatter_unpack`):
##   `COLOR`           = tint lifted by [member spawn_tier] via `Emissive.at()`
##   `INSTANCE_CUSTOM` = (velocity.x, velocity.y, spawn_time - [member time_base],
##                        [method pack_shard])
##   transform         = origin at the source, uniform scale `2 * radius * OVERSIZE`,
##                       never rotated — [method radial_kick]'s angle for cell K
##                       and the shader's seed placement for cell K agree only
##                       while local axes equal world axes. The shader also
##                       hashes the fracture pattern's seed from this origin,
##                       so the field must sit under a parent that does not move.
##
## **Everything packed is exact in a HALF float.** The compatibility renderer
## stores a 2D MultiMesh's colour and custom data as 16-bit halves (probed
## 2026-09-10: `custom.w = 2049` reads back as 2048 under opengl3), which is
## why cells are capped at [constant MAX_CELLS] (`cell + count * 32 < 2048`),
## the fracture seed is not a channel at all, and spawn times are stored
## relative to [member time_base] — a run-long clock would otherwise lose the
## whole window to half-float spacing after a few thousand seconds.
##
## Headless Godot cannot read a MultiMesh's buffer back
## (`docs/domain/rendering-performance.md`), so every push is mirrored in the
## `_origins`/`_sides`/`_colors`/`_customs` arrays — the pool needs the spawn
## time per slot anyway, the rest is what makes the field testable and what
## repopulates the buffer after a capacity growth (which discards it, see
## `Graph._grow_edge_mesh_capacity`).

## Quad side over source diameter. Must match `SHATTER_OVERSIZE` in
## `shatter_motion.gdshaderinc`. 2x covers a cell spinning about a pivot near
## the rim (|pivot| + cell extent <= 2r) and leaves #257 room for its rays.
const OVERSIZE: float = 2.0
## Cells per shatter: 5 bits each for cell and count keep [method pack_shard]
## under 2048, the last integer a half float holds exactly.
const MAX_CELLS: int = 32
## Smallest GPU buffer; doubled from here.
const MIN_CAPACITY: int = 16

const _CELL_SCALE: int = 32

## Seconds from a shard's spawn to its last frame (progress 1). Authored on
## the consumer's tuning resource and handed here (#787: ~0.25s from
## `BladeStyle`; #257: its cascade window). Pushed to `shatter_window`.
@export_range(0.01, 10.0, 0.01, "or_greater") var window: float = 0.25:
	set = set_window
## The progress at which shards start to move (`p0`). 0 = an immediate pop
## (#787); ~0.6 = after a crescendo drawn on the intact disc (#257). Pushed to
## `shatter_flight_start`.
@export_range(0.0, 1.0, 0.01) var flight_start: float = 0.0:
	set = set_flight_start
## Emissive tier a shard is born at — a named stop, never a float
## (`.claude/rules/hdr-color.md`). The pushed `COLOR` is
## `Emissive.at(tint, stops(spawn_tier))`.
@export var spawn_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set = set_spawn_tier
## Tier a shard has dropped to by the time its alpha runs out. The shader dims
## by `spawn_tier - end_tier` stops across the flight (colour value is the
## dimmer, alpha is the fade channel), pushed as `shatter_fade_stops`.
@export var end_tier: Emissive.Tier = Emissive.Tier.INERT:
	set = set_end_tier

## The consumer's clock, in the same seconds every shard's spawn time was given
## in. Writing it pushes exactly one uniform (`shatter_elapsed`, as
## `elapsed - time_base`) and nothing else — that is the whole scrub contract.
var elapsed: float = 0.0:
	set = set_elapsed
## The clock value spawn times are stored relative to, so the half-float
## channel only ever carries "seconds since this pool's first shard". Re-based
## by [method spawn_shatter] whenever every shard in the pool has expired
## (which also empties the pool — they were all dead anyway).
var time_base: float = 0.0

var _capacity: int = 0
var _used: int = 0
## Slots found expired by the last reclaim scan and not yet handed out. Every
## pop re-checks expiry against the CURRENT [member elapsed]: a rewind can make
## a listed slot live again, and a live shard is never overwritten.
var _free: PackedInt32Array = PackedInt32Array()
## The `elapsed` the last reclaim scan ran at — nothing new can have expired
## until it changes, so a burst of spawns in one frame scans once.
var _free_scan_elapsed: float = NAN
## Latest `spawn_time + window` in the pool: `elapsed >= _max_expiry` means
## nothing is live, in O(1), and a rewind below it means something is.
var _max_expiry: float = -INF
var _origins: PackedVector2Array = PackedVector2Array()
var _sides: PackedFloat32Array = PackedFloat32Array()
var _colors: PackedColorArray = PackedColorArray()
var _customs: PackedColorArray = PackedColorArray()
## Spawn times on the consumer's clock, in float64. The GPU copy in
## `_customs[].b` is a float32 (and a half on the compatibility renderer), so
## comparing IT against the float64 `elapsed` misreads a shard spawned at
## exactly `elapsed` as unborn; the pool's own bookkeeping never rounds.
var _spawn_times: PackedFloat64Array = PackedFloat64Array()


func _ready() -> void:
	_init_multimesh()
	if material == null:
		push_warning("ShatterField '%s' has no material — instantiate shatter_field.tscn (or override its material) rather than ShatterField.new()." % name)
	elif not material.resource_local_to_scene:
		# One shared ShaderMaterial would carry ONE `shatter_elapsed`, so every
		# field in the tree would scrub together. `resource_local_to_scene` makes
		# `instantiate()` hand each instance its own copy — the sanctioned fix
		# (`.claude/rules/godot-scene-authoring.md`), and it costs no draw call:
		# two MultiMeshInstance2Ds are two draws regardless.
		push_warning("ShatterField '%s': material '%s' is not resource_local_to_scene — every field sharing it scrubs together." % [name, material.resource_path])
	_push_uniforms()


## Keep the runtime buffer OUT of a saved `.tscn`. This node is `@tool` so
## #838's in-editor tab can drive it, and an instance data buffer is a node
## property like any other — the next scene save would bake it in (same
## trap, same hook as `Graph._notification`). Empty it just before the writer
## reads the tree, rebuild it from the mirrors right after. Runtime never
## sees either notification.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			if multimesh != null:
				multimesh.visible_instance_count = 0
				multimesh.instance_count = 0
		NOTIFICATION_EDITOR_POST_SAVE:
			_capacity = 0
			if _used > 0 and multimesh != null:
				_grow(_used)


# ------------------------------------------------------------ the reference
# The motion the shader integrates, as pure functions. `shatter_motion.gdshaderinc`
# implements the same curve on the GPU; the two must stay in lockstep (each
# names the other). Tests pin these; the look is judged under a real renderer.


## Progress of a shard spawned at `spawn_time`, on the consumer's clock.
static func progress_at(spawn_time: float, at_elapsed: float, window_seconds: float) -> float:
	return clampf((at_elapsed - spawn_time) / maxf(window_seconds, 0.0001), 0.0, 1.0)


## Seconds a shard has been in flight at `progress`: zero until `p0`, then
## window time elapsed since. This is the owner's "simulation time left".
static func flight_time_at(progress: float, window_seconds: float, p0: float) -> float:
	return maxf(progress - p0, 0.0) * window_seconds


## Momentum times time in flight. No drag term, by decision.
static func displacement_at(velocity: Vector2, progress: float, window_seconds: float, p0: float) -> Vector2:
	return velocity * flight_time_at(progress, window_seconds, p0)


## 0..1 across the flight: how far through its dimming + fade a shard is.
static func fade_ramp_at(progress: float, p0: float) -> float:
	if p0 >= 1.0:
		return 1.0 if progress >= 1.0 else 0.0
	return clampf((progress - p0) / (1.0 - p0), 0.0, 1.0)


## Alpha at `progress`: full through the first half of the flight (the tier
## drop does the quieting there), then to exactly 0 at progress 1.
static func fade_alpha_at(progress: float, p0: float) -> float:
	return 1.0 - smoothstep(0.5, 1.0, fade_ramp_at(progress, p0))


## The outward kick cell `cell` of `cell_count` gets — `speed` along the cell's
## nominal angle `TAU * cell / cell_count`. The shader places cell K's Voronoi
## seed on that same nominal angle (plus a bounded hashed jitter), so the kick
## points out through the shard's own centre. Must match
## `shatter_cell_seed` in `shatter_motion.gdshaderinc`.
static func radial_kick(cell: int, cell_count: int, speed: float) -> Vector2:
	return Vector2.from_angle(TAU * float(cell) / float(maxi(cell_count, 1))) * speed


## What rides `INSTANCE_CUSTOM.xy`: the parent's momentum plus this shard's own
## kick, folded on the CPU so the shader integrates one velocity.
static func shard_velocity(seed_velocity: Vector2, cell: int, cell_count: int, kick_speed: float) -> Vector2:
	return seed_velocity + radial_kick(cell, cell_count, kick_speed)


## `cell + (cell_count - 1) * 32` — two integers in one float, at most 1023,
## exact in a half float (see the class docs). Inputs are clamped so no two
## shards ever alias.
static func pack_shard(cell: int, cell_count: int) -> float:
	var n := clampi(cell_count, 1, MAX_CELLS)
	var k := clampi(cell, 0, n - 1)
	return float(k + (n - 1) * _CELL_SCALE)


## Inverse of [method pack_shard]: `(cell, cell_count)`.
static func unpack_shard(packed: float) -> Vector2i:
	var p := int(roundf(packed))
	return Vector2i(p % _CELL_SCALE, p / _CELL_SCALE + 1)


# ------------------------------------------------------------------ the pool


## Fragment one dying object into `shard_count` shards born at `spawn_time` on
## the consumer's clock. `origin` is in this node's local space; `radius` is
## the source's; `tint` is the source's SDR identity colour (the tier lift is
## applied here); `seed_velocity` is the momentum the consumer derived — the
## field never derives momentum itself; `kick_speed` is each shard's own
## outward push. The fracture pattern is seeded from `origin` in the shader.
## Returns the first slot (the shards occupy `shard_count` slots, not
## necessarily contiguous).
##
## Pooling: a slot whose shard has expired *at the current [member elapsed]*
## is reused first, then the buffer grows by doubling. Recycling happens ONLY
## here — expiry alone never touches a slot, so a consumer that seeks backwards
## after a shard expired sees it again unless a later spawn took the slot.
## When *every* shard has expired the pool is emptied and [member time_base]
## re-based to `spawn_time` instead. #787's rewind therefore calls
## [method clear] and re-drains its spawns.
func spawn_shatter(origin: Vector2, radius: float, tint: Color, seed_velocity: Vector2,
		spawn_time: float, shard_count: int = 8, kick_speed: float = 0.0) -> int:
	if _used == 0 or elapsed >= _max_expiry:
		_rebase(spawn_time)
	var n := clampi(shard_count, 1, MAX_CELLS)
	var side := 2.0 * maxf(radius, 0.0) * OVERSIZE
	var color := Emissive.at(tint, Emissive.stops(spawn_tier))
	var first := -1
	for k in n:
		var slot := _acquire_slot()
		if first < 0:
			first = slot
		var v := shard_velocity(seed_velocity, k, n, kick_speed)
		var custom := Color(v.x, v.y, spawn_time - time_base, pack_shard(k, n))
		_spawn_times[slot] = spawn_time
		_push_shard(slot, origin, side, color, custom)
	_max_expiry = maxf(_max_expiry, spawn_time + window)
	return first


## Drop every shard. Draw range to zero; the buffer capacity is kept.
func clear() -> void:
	_used = 0
	_free = PackedInt32Array()
	_free_scan_elapsed = NAN
	_max_expiry = -INF
	_origins = PackedVector2Array()
	_sides = PackedFloat32Array()
	_colors = PackedColorArray()
	_customs = PackedColorArray()
	_spawn_times = PackedFloat64Array()
	if multimesh != null:
		multimesh.visible_instance_count = 0


## Slots handed out since the last [method clear] (expired ones included).
func used_slots() -> int:
	return _used


## Shards drawn at the current [member elapsed]: born and not yet expired.
func live_count() -> int:
	var n := 0
	for slot in _used:
		if shard_spawn_time(slot) <= elapsed and not _is_expired(slot):
			n += 1
	return n


## A slot's spawn time back on the consumer's clock.
func shard_spawn_time(slot: int) -> float:
	return _spawn_times[slot]


## The pushed instance transform (CPU mirror).
func shard_transform(slot: int) -> Transform2D:
	return _transform_for(_origins[slot], _sides[slot])


## The pushed instance colour (CPU mirror).
func shard_color(slot: int) -> Color:
	return _colors[slot]


## The pushed `INSTANCE_CUSTOM` (CPU mirror): `(vx, vy, spawn_time, packed)`.
func shard_custom(slot: int) -> Color:
	return _customs[slot]


# ------------------------------------------------------------------ setters


func set_window(value: float) -> void:
	window = maxf(value, 0.0001)
	_set_uniform(&"shatter_window", window)


func set_flight_start(value: float) -> void:
	flight_start = clampf(value, 0.0, 1.0)
	_set_uniform(&"shatter_flight_start", flight_start)


func set_spawn_tier(value: Emissive.Tier) -> void:
	spawn_tier = value
	_set_uniform(&"shatter_fade_stops", _fade_stops())


func set_end_tier(value: Emissive.Tier) -> void:
	end_tier = value
	_set_uniform(&"shatter_fade_stops", _fade_stops())


func set_elapsed(value: float) -> void:
	elapsed = value
	_set_uniform(&"shatter_elapsed", elapsed - time_base)


# ----------------------------------------------------------------- internals


func _fade_stops() -> float:
	return Emissive.stops(spawn_tier) - Emissive.stops(end_tier)


func _push_uniforms() -> void:
	_set_uniform(&"shatter_window", window)
	_set_uniform(&"shatter_flight_start", flight_start)
	_set_uniform(&"shatter_fade_stops", _fade_stops())
	_set_uniform(&"shatter_elapsed", elapsed - time_base)


func _rebase(new_base: float) -> void:
	clear()
	time_base = new_base
	_set_uniform(&"shatter_elapsed", elapsed - time_base)


func _set_uniform(uniform: StringName, value: float) -> void:
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(uniform, value)


## Fresh buffer every `_ready` (editor and runtime both) so the runtime
## instance data never lands in a saved `.tscn` — same reasoning as
## `Graph._init_edge_mesh`.
func _init_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = 0
	mm.visible_instance_count = 0
	multimesh = mm
	_capacity = 0
	clear()


static func _transform_for(origin: Vector2, side: float) -> Transform2D:
	return Transform2D(0.0, Vector2(side, side), 0.0, origin)


func _is_expired(slot: int) -> bool:
	return shard_spawn_time(slot) + window <= elapsed


func _acquire_slot() -> int:
	if _free.is_empty() and _free_scan_elapsed != elapsed:
		_free_scan_elapsed = elapsed
		for slot in _used:
			if _is_expired(slot):
				_free.append(slot)
	while not _free.is_empty():
		var slot := _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		if _is_expired(slot):
			return slot
		# Listed while expired, rewound since: live again, leave it alone.
	if _used >= _capacity:
		_grow(_used + 1)
	var fresh := _used
	_used += 1
	_origins.append(Vector2.ZERO)
	_sides.append(0.0)
	_colors.append(Color.BLACK)
	_customs.append(Color.BLACK)
	_spawn_times.append(0.0)
	multimesh.visible_instance_count = _used
	return fresh


## `instance_count` reallocates AND discards the GPU buffer on every write
## (`Graph._grow_edge_mesh_capacity`), so grow rarely — by doubling — and
## repopulate every live slot from the mirrors right after.
func _grow(min_count: int) -> void:
	if min_count <= _capacity:
		return
	_capacity = maxi(min_count, maxi(_capacity * 2, MIN_CAPACITY))
	multimesh.instance_count = _capacity
	multimesh.visible_instance_count = _used
	for slot in _used:
		_write_instance(slot)


func _push_shard(slot: int, origin: Vector2, side: float, color: Color, custom: Color) -> void:
	_origins[slot] = origin
	_sides[slot] = side
	_colors[slot] = color
	_customs[slot] = custom
	_write_instance(slot)


func _write_instance(slot: int) -> void:
	multimesh.set_instance_transform_2d(slot, _transform_for(_origins[slot], _sides[slot]))
	multimesh.set_instance_color(slot, _colors[slot])
	multimesh.set_instance_custom_data(slot, _customs[slot])
