@tool
class_name AllocationVFX
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")
const InnerDiskShatterField := preload("res://skill_node/visuals/inner_disk_shatter_field.tscn")

## Listens to AllocationSystem (allocate / dealloc) and BattleSystem
## (cascade_started) and spawns transient world-space effects:
##   - alloc spike   : "skill point from the heavens" on every allocation
##   - dealloc lift  : floating colored disk on voluntary deallocation
##   - shatter       : #257's InnerDisk fragmentation on forced deallocation —
##                     an intact-disc crescendo (cracks glow, rays leak out)
##                     THEN the disc comes apart into flying shards, staggered
##                     by BFS-distance-from-impact when part of a battle
##                     cascade. Real dome shading, not a snapshot texture —
##                     see `skill_node/visuals/inner_disk_shatter.gdshader`.
##
## Mounted under Graph (sibling of AttackVFX) so world coords match.
## See docs/domain/allocation-vfx.md for the design rationale.

# --- Tunables ----------------------------------------------------------------

const SPIKE_DURATION: float = 0.4
# Base width = SkillNode.inner_radius * 2 (the horizontal chord through the
# inner fill circle). Spike sits flush on the disk.
const SPIKE_HEIGHT_FACTOR: float = 6.0  # multiplied by node radius
# Lorentzian / Breit-Wigner-ish profile: w(t) ∝ γ² / (γ² + t²), tip pinned to 0.
# Smaller γ → narrower needle, sharper concave shoulders. ~0.22 reads as a
# clean resonance peak; raise toward 0.5 for a candle-flame, drop below 0.15
# for a hair-thin spire.
const SPIKE_NEEDLE_GAMMA: float = 0.22
const SPIKE_SAMPLES: int = 14  # per side; total poly verts = 2*samples + 2

# Z-order: must render above EVERYTHING the FogOverlay promotes — see ZLayers.
# We use SPELL_VFX absolute (z_as_relative = false) so the VFX always wins
# regardless of parent chain.

const LIFT_DURATION: float = 0.30
const LIFT_RISE_FACTOR: float = 1.5  # multiplied by node radius
const LIFT_END_SCALE: float = 0.6

## #257's ShatterField-driven node death replaced the old vibrate + particle
## pair outright; only the particle burst consts below survive, for
## `_spawn_pop_burst` (#170, untouched by #257 — see its own doc).
const SHATTER_PARTICLE_COUNT: int = 24
const SHATTER_PARTICLE_LIFETIME: float = 0.35
const SHATTER_OUTWARD_SPEED: float = 220.0

# Blade-pop burst (#170): a sharp, short radial spray where a defender's spike
# pops an incoming enemy blade vertex. Reuses the shatter burst idiom; tighter
# and faster than a node shatter. Radius scales mildly with spike power.
const POP_BURST_DURATION: float = 0.5
const POP_BASE_RADIUS: float = 6.0
const POP_RADIUS_PER_POWER: float = 2.0
const POP_MAX_RADIUS: float = 22.0

# --- Modifier pulses (#71) ---------------------------------------------------
# On voluntary allocation, one pulse per granted modifier flows from the
# allocated node along the entity-navigator path to the core; on arrival each
# fires #70's stat-modifier floater. Travel time scales with hop count so the
# per-hop speed stays roughly constant regardless of path length.
const _PULSE_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")
const PULSE_STAGGER: float = 0.07     # s between successive pulses (burst feel)
const PULSE_PER_HOP: float = 0.13     # s of travel per graph hop (constant speed)
const PULSE_MIN_FLIGHT: float = 0.2   # floor so a 1-hop path isn't a blink


# --- Wiring ------------------------------------------------------------------
## When true, every cosmetic handler early-returns — the systems still run, the
## VFX just stays silent. Lets a driver replay the real allocate/force-dealloc
## primitives for a non-visual purpose (e.g. a showcase's silent SETUP beat that
## re-arms cells) without spewing spikes/shatters. Off by default; nothing in
## normal gameplay touches it.
var muted: bool = false

@export var allocation_system: AllocationSystem
@export var battle_system: BattleSystem
## Seconds between cascade layers' shatters. #504: the forced-dealloc cascade
## MUTATES synchronously — all layers in one beat, and it must (see
## `BattleSystem._on_node_depleted`) — so the layer-by-layer ripple is owned
## here, as pure animation. Delaying a shatter spawn is not frame-ordered
## mutation: nothing downstream reads it, and dropping it entirely would leave
## the applied world identical.
const CASCADE_STEP: float = 0.35

## Pre-dealloc snapshot for the cascade currently unwinding: per node, the
## position / radius / colour to draw plus this node's own `delay` slot.
## Written by `_on_cascade_started` — which runs BEFORE `force_deallocate` and
## so still sees an accurate `inner_radius` — and consumed once by
## `_on_force_deallocated`, which is what actually spawns. A standalone
## (non-cascade) force-dealloc has no entry and reads live values at zero delay.
var _cascade_snapshot: Dictionary[SkillNode, Dictionary] = {}

# --- #257 node-death shatter tuning (exposed on this node so #838's live tab
# tunes it via the Inspector — no new resource type, per the issue's own
# "the tuning resource is almost certainly just the material" call; these are
# the CPU-side half of the same knobs, the rest live on the material .tres) --

## Seconds a shatter takes from spawn (cascade delay) to fully faded — the
## crescendo AND the flight together. Pushed to `ShatterField.window`.
@export_range(0.1, 5.0, 0.01, "or_greater") var shatter_window: float = 1.4:
	set(value):
		shatter_window = value
		_push_shatter_tuning()
## Progress (0..1 of `shatter_window`) at which the disc lets go and shards
## start flying — before this the shard field draws one intact, cracking
## disc. Pushed to `ShatterField.flight_start` (`p0`).
@export_range(0.0, 1.0, 0.01) var shatter_flight_start: float = 0.6:
	set(value):
		shatter_flight_start = value
		_push_shatter_tuning()
## Shards a dying node's disc splits into. Capped at `ShatterField.MAX_CELLS`
## (32) — the half-float packing budget.
@export_range(1, 32, 1) var shatter_shard_count: int = 14
## Each shard's own outward push speed (px/s) — the WHOLE of its velocity, a
## dying node is stationary so there is no momentum to inherit (#257 decision
## 7). "Sending far could be hella fun" (the issue body) is this knob.
@export_range(0.0, 2000.0, 1.0) var shatter_fling_speed: float = 90.0
## Tier a shard's COLOR is lifted to at spawn. Pinned to INERT (0 stops, the
## identity lift) — anything higher would make the pre-flight intact-disc
## crescendo render brighter than the live InnerDisk, breaking #257
## acceptance 2. The shader's own crack-glow/ray HDR boost is independent of
## this (see `inner_disk_shatter.gdshader`'s header). Still an `@export`
## (not a `const`) so the live tab can SEE why, and because `ShatterField`
## itself expects a real tier to push.
@export var shatter_spawn_tier: Emissive.Tier = Emissive.Tier.INERT:
	set(value):
		shatter_spawn_tier = value
		_push_shatter_tuning()
## Tier a shard has dimmed to by the time it's fully faded. Matches
## [member shatter_spawn_tier] by default (fade_stops = 0) — alpha alone
## carries the fade-out, per `.claude/rules/hdr-color.md`.
@export var shatter_end_tier: Emissive.Tier = Emissive.Tier.INERT:
	set(value):
		shatter_end_tier = value
		_push_shatter_tuning()

## #257's node-death shard field. One per AllocationVFX (one graph's worth of
## node deaths pool together, same idiom as `SkillBlade._shard_field`), an
## inherited `shatter_field.tscn` with its own `resource_local_to_scene`
## material (`inner_disk_shatter_material.tres`). Must stay a non-moving
## parent of this — `elapsed`/spawn origin math both assume it (see
## `ShatterField`'s class docs) — which `self` (this AllocationVFX, mounted
## once under Graph) satisfies.
var _shard_field: ShatterField
## This field's own clock, advanced every frame regardless of whether
## anything is currently live in the pool — the one per-frame write
## `ShatterField.elapsed` contracts for (`ui/vfx/shatter/shatter_field.gd`'s
## class docs: "the ONLY per-frame call"). Run-long is fine; the pool only
## ever stores spawn times relative to its own `time_base`.
var _shatter_clock: float = 0.0


func _ready() -> void:
	# Absolute z (z_as_relative = false) so children inherit the same effective
	# z floor — otherwise a transient effect added under us would be at
	# parent_z + child_z and could land below a fog-promoted node.
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX
	_shard_field = get_node_or_null("ShatterField") as ShatterField
	if _shard_field == null:
		_shard_field = InnerDiskShatterField.instantiate() as ShatterField
		_shard_field.name = "ShatterField"
		add_child(_shard_field)
	_push_shatter_tuning()
	# Ticks in the editor too (no `is_editor_hint()` gate) — #838's live tab
	# is exactly where this needs to be SEEN playing.
	set_process(true)
	bind(allocation_system, battle_system)


func _process(delta: float) -> void:
	if _shard_field == null:
		return
	_shatter_clock += delta
	_shard_field.elapsed = _shatter_clock


func _push_shatter_tuning() -> void:
	if _shard_field == null:
		return
	_shard_field.window = shatter_window
	_shard_field.flight_start = shatter_flight_start
	_shard_field.spawn_tier = shatter_spawn_tier
	_shard_field.end_tier = shatter_end_tier


## The shard field #257's node deaths spawn into — exposed for the live tab
## and test inspection, same as `SkillBlade.get_shard_field()`.
func get_shard_field() -> ShatterField:
	return _shard_field

func bind(_allocation_system: AllocationSystem, _battle_system: BattleSystem) -> void:
	# NO blanket `Engine.is_editor_hint()` guard here (removed while wiring
	# #257's shatter into this file) — `Engine.is_editor_hint()` is TRUE
	# inside a live sandbox tab too, and AllocationSystem/BattleSystem are
	# `@tool` (#260), so the signals below are real there, not placeholders.
	# A blanket guard would leave #838's live tab "silently half-built": every
	# signal-driven VFX (this shatter included) simply never firing, no error.
	# See `docs/domain/sandbox-framework.md`'s "Engine.is_editor_hint() is TRUE
	# inside a live tab" section and `.claude/rules/gdscript-pitfalls.md`.
	if _allocation_system != null:
		allocation_system = _allocation_system
		allocation_system.allocated.connect(_on_allocated)
		allocation_system.deallocated.connect(_on_deallocated)
		allocation_system.force_deallocated.connect(_on_force_deallocated)
	if _battle_system != null:
		battle_system = _battle_system
		# The pre-dealloc snapshot point AND where the ripple schedule is
		# assigned — see `_on_cascade_started`.
		battle_system.cascade_started.connect(_on_cascade_started)
	# #170: bus-driven, not system-bound — a spike pop is a world event, not an
	# allocation. Connect once (idempotent guard for repeat bind() calls).
	if not Events.blade_vertex_popped.is_connected(_on_blade_vertex_popped):
		Events.blade_vertex_popped.connect(_on_blade_vertex_popped)


# --- Signal handlers ---------------------------------------------------------

func _on_allocated(node: SkillNode, entity: Entity, forced: bool) -> void:
	if muted or node == null or entity == null:
		return
	spawn_alloc_spike(self, node.global_position, node.inner_radius, node.radius, entity.color)
	# Forced allocations are level setup (spawn / procgen / scene-authored) —
	# the spike "drops the node in", but no gameplay pulses/floaters fire.
	if forced:
		return
	_spawn_modifier_pulses(node, entity)


func _on_deallocated(node: SkillNode, previous_owner: Entity) -> void:
	if muted or node == null or previous_owner == null:
		return
	_spawn_lift(node.global_position, node.inner_radius, previous_owner.color)
	# #70: voluntary dealloc only (force-dealloc / death use force_deallocated,
	# so the death-strip flurry is suppressed by construction).
	for m in StatModifier.flatten_all(node.modifiers):  # bundles → one floater per leaf (#183)
		Events.stat_modifier_changed.emit(previous_owner, m, ModifierBinding.Kind.NODE, false)


## #504: `force_deallocated` fires when the node ACTUALLY changes hands — which
## under design B is the landing's own `arrival_time` — so the shatter spawns
## from here directly. Its only scheduling is the intra-cascade ripple delay
## `_on_cascade_started` assigned it (0.0 for a standalone dealloc).
func _on_force_deallocated(node: SkillNode, previous_owner: Entity) -> void:
	if muted or node == null or previous_owner == null:
		return
	var snap: Dictionary = _cascade_snapshot.get(node, {})
	_cascade_snapshot.erase(node)
	# Live values are the fallback, not the preference: by now `owned_by` is
	# null and the stake/alloc count has zeroed, so `inner_radius` has already
	# collapsed (see [AllocationSystem.force_deallocate]). A cascade node's
	# snapshot is the accurate one.
	_spawn_shatter(
			snap.get("position", node.global_position),
			snap.get("radius", node.inner_radius),
			snap.get("color", previous_owner.color),
			snap.get("delay", 0.0))


func _on_blade_vertex_popped(defender: SkillNode, _attacker: Entity, at_pos: Vector2) -> void:
	if muted or defender == null:
		return
	# Pop in the defender's colour (the node whose spikes did the popping).
	var color: Color = defender.owned_by.color if defender.owned_by != null \
			else Color(0.95, 0.55, 0.4, 0.95)
	var power := defender.get_spike_power()
	var radius := minf(POP_MAX_RADIUS, POP_BASE_RADIUS + power * POP_RADIUS_PER_POWER)
	_spawn_pop_burst(at_pos, radius, color)


## A forced-dealloc cascade is about to run in the model. Two jobs, both of
## which need to happen BEFORE `force_deallocate`:
##
## 1. Snapshot each node's position/radius — the node lives on (only
##    ownership/visuals change), but stake/allocation collapsing to 0 on
##    dealloc shrinks `inner_radius` out from under any later read.
## 2. Assign each node its ripple slot. `layers` arrives in BFS order from the
##    impact, so layer `i` shatters `i * CASCADE_STEP` after the hit — the
##    cascade reads as spreading outward rather than popping at once. #504
##    moved this here: the mutation is synchronous and cannot be staggered
##    (see `BattleSystem._on_node_depleted`), but the ANIMATION can.
func _on_cascade_started(layers: Array, defender: Entity) -> void:
	if muted or defender == null or layers.is_empty():
		return
	var color: Color = defender.color
	for i in range(layers.size()):
		for n in layers[i]:
			if n == null:
				continue
			_cascade_snapshot[n] = {
				"position": n.global_position,
				"radius": n.inner_radius,
				"color": color,
				"delay": i * CASCADE_STEP,
			}


# --- Modifier pulses (#71) ---------------------------------------------------

## One pulse per modifier the allocation grants, flowing node → core along the
## entity's owned subgraph, each firing #70's floater on arrival. The modifier
## is ALREADY on the board (allocation applied it synchronously) — this is the
## visual catching up. The #70→#71 seam: the floater emit now waits for arrival
## instead of firing in `_on_allocated` directly.
func _spawn_modifier_pulses(node: SkillNode, entity: Entity) -> void:
	# Flatten so a CompositeStatModifier pulses one floater per leaf (#183).
	var mods := StatModifier.flatten_all(node.modifiers)
	if mods.is_empty():
		return
	var route := _core_route(node, entity)
	if route.size() < 2:
		# No usable path (node IS the core, or no navigator) — pop in place.
		for m in mods:
			_emit_modifier_floater(entity, m)
		return
	var curve := _route_curve(route)
	var origin := route[0]
	var target := route[route.size() - 1]
	var flight := maxf(PULSE_MIN_FLIGHT, float(route.size() - 1) * PULSE_PER_HOP)
	for i in mods.size():
		_launch_modifier_pulse(curve, origin, target, entity, mods[i],
				float(i) * PULSE_STAGGER, flight)


## World-space node centres from the allocated node to the core, via the
## entity's navigator (shortest hop path within its owned subgraph).
func _core_route(node: SkillNode, entity: Entity) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if entity.navigator == null or entity.core_location == null:
		return pts
	for n in entity.navigator.path_between(node, entity.core_location):
		if n != null:
			pts.append(n.global_position)
	return pts


## Curve2D through the route points. With origin/target pinned to the route
## endpoints, Curve2DPath's similarity transform is the identity, so the pulse
## traces the exact polyline (no shape-warping). Zero tangents → straight hops.
func _route_curve(route: PackedVector2Array) -> Curve2D:
	var c := Curve2D.new()
	for p in route:
		c.add_point(p)
	return c


func _launch_modifier_pulse(curve: Curve2D, origin: Vector2, target: Vector2,
		entity: Entity, modifier: StatModifier, delay: float, flight: float) -> void:
	var path := Curve2DPath.new()
	path.curve = curve
	var proj := Projectile.new()
	proj.path = path
	proj.visual_scene = _PULSE_VISUAL
	proj.flight_time = flight
	proj.face_velocity = false
	proj.modulate = entity.color
	add_child(proj)
	proj.arrived.connect(_emit_modifier_floater.bind(entity, modifier), CONNECT_ONE_SHOT)
	proj.launch(origin, target, delay)


func _emit_modifier_floater(entity: Entity, modifier: StatModifier) -> void:
	Events.stat_modifier_changed.emit(entity, modifier, ModifierBinding.Kind.NODE, true)


# --- Effect spawners ---------------------------------------------------------

## "Skill point from the heavens" — a needle that drops onto the node and a
## disk that lingers after it.
##
## [b]Static, and takes primitives rather than a [SkillNode][/b] — the last
## spawner here that did not. `_spawn_lift` and `_spawn_shatter` already took
## `(world_pos, radius, colour)`; this one kept a node reference only to read
## two radii off it. Making it match is what lets the frontmatter menu (#574)
## play the SAME spike when the splash allocates its root node: that menu has no
## [SkillNode], no [Entity] and no [AllocationSystem] anywhere in it by
## construction (see [MenuNodeView]), so anything it reuses has to be reusable as
## a scene or a function, never as a class.
##
## [param host] is what the effect is parented to and what its [Tween] runs
## against — this instance in gameplay, `%GraphLayer` in the menu. It sets its
## own absolute z rather than inheriting one, so it wins over fog-promoted nodes
## from any parent chain.
static func spawn_alloc_spike(
	host: Node2D, world_pos: Vector2, inner_radius: float, node_radius: float, color: Color
) -> void:
	var container := Node2D.new()
	# Absolute (z_as_relative = false), for the reason `_ready` gives: a
	# transient added under a relative parent lands at parent_z + child_z.
	container.z_as_relative = false
	container.z_index = ZLayers.SPELL_VFX
	host.add_child(container)

	var disk := _make_snapshot_disk(inner_radius, color)
	disk.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)
	# Parented FIRST, positioned second. `global_position` on a node that is not
	# in the tree yet has no parent transform to invert, so it silently writes
	# `position` — and the child then lands at `host.global_position + world_pos`
	# once it is added. Invisible while every host sat at the origin
	# (`%AllocationVFX` does); the frontmatter menu parents a spike to the NODE
	# VIEW itself, which is at its own world home, so the offset read as exactly
	# doubled (#599 follow-up, reported 2026-08-26).
	container.add_child(disk)
	disk.global_position = world_pos

	var spike := Polygon2D.new()
	spike.polygon = _build_needle_polygon(inner_radius, node_radius * SPIKE_HEIGHT_FACTOR)
	# Polygon2D.color is the draw tint — alpha here multiplies with modulate.a,
	# so keep it opaque and animate visibility via modulate.a only.
	spike.color = color
	spike.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)
	container.add_child(spike)  # before `global_position` — see the disk above.
	spike.global_position = world_pos

	# White flash: disk + spike both ramp toward a lightened tint, then settle
	# back to the entity color. Disk is the snapshot reused from the lift VFX.
	#var flash_color := color
	# Bound to the container rather than to `host`: the effect owns its own
	# clock, so a static caller needs no node of its own to hang it off.
	var tween := container.create_tween()
	tween.set_parallel(true)

	# Alpha 0.5 → 1 → 0.
	container.modulate.a = 0.5
	tween.tween_property(container, "modulate:a", 1.0, SPIKE_DURATION * 0.2)
	
	# Height 0.0 → 1 → 0.
	# Height collapses into the node center (poly's bottom edge is at y=0,
	# so scaling y → 0 makes it sink in).
	const SCALE_RAMPUP_FRAC := 0.5
	spike.scale.y = 0.0
	tween.tween_property(spike, "scale:y", 1.0, SPIKE_DURATION * SCALE_RAMPUP_FRAC)
	tween.tween_property(spike, "scale:y", 0.0, SPIKE_DURATION * (1.0 - SCALE_RAMPUP_FRAC))\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)\
			.set_delay(SPIKE_DURATION * SCALE_RAMPUP_FRAC)
	
	const DISK_LINGER_TIME := 2.
	tween.tween_property(disk, "modulate:a", 0.0, DISK_LINGER_TIME)\
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)\
			.set_delay(SPIKE_DURATION)
	
	tween.chain().tween_callback(container.queue_free)


## Floating colored disk on voluntary deallocation — a puff marking the spot
## the node vacated as it collapses back onto its parent.
##
## [b]Static, and takes a [param host] rather than assuming `self`[/b] — the
## last spawner here that did. Extracted so the frontmatter menu (#599) can
## play the SAME lift when a view loses focus-path allocation: that menu has
## no [AllocationSystem] to mount an [AllocationVFX] under (see
## [MenuNodeView]), so anything it reuses has to be reusable as a function.
##
## [param host] is what the effect is parented to and what its [Tween] runs
## against — this instance in gameplay, `%GraphLayer` in the menu (the lift
## marks the spot vacated, not the node itself, which is about to collapse to
## `FrontmatterLayout.PREVIEW_SCALE` on its own parent).
static func spawn_dealloc_lift(host: Node2D, world_pos: Vector2, disk_radius: float, color: Color) -> void:
	var disk := _make_snapshot_disk(disk_radius, color)
	host.add_child(disk)  # before `global_position` — see [method spawn_alloc_spike].
	disk.global_position = world_pos
	var rise := disk_radius * LIFT_RISE_FACTOR
	var tween := host.create_tween()
	tween.set_parallel(true)
	# The rise is off the disk's OWN `position`, not off `world_pos` — those
	# agree only for a host at the origin, and the whole point of `host` being a
	# parameter is that it need not be.
	tween.tween_property(disk, "position:y", disk.position.y - rise, LIFT_DURATION)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(disk, "scale", Vector2.ONE * LIFT_END_SCALE, LIFT_DURATION)
	# Color shift owner → white (holy puff of smoke) over the first ~70% of
	# the lift, so the bloom reads BEFORE the fade really kicks in. Keeps
	# alpha at 1 during the shift; the modulate:a tween below handles fade.
	tween.tween_property(disk, "disk_color", Color(1.0, 1.0, 1.0, 1.0),
			LIFT_DURATION * 0.7)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(disk, "modulate:a", 0.0, LIFT_DURATION)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(disk.queue_free)


func _spawn_lift(world_pos: Vector2, disk_radius: float, color: Color) -> void:
	spawn_dealloc_lift(self, world_pos, disk_radius, color)


## Node "death" animation (#257): fragments the dying node's own dome into
## [member _shard_field] — an intact-disc crescendo (cracks glow, rays leak
## out) through the cascade `delay`, then the disc comes apart at
## `shatter_flight_start`. Replaces the old vibrate + particle-burst pair
## outright, same handoff shape: the real SkillNode's InnerDisk hides at
## `force_deallocate` (see `skill_node.gd`), the shard field takes over.
## Returns the first pool slot (`ShatterField.spawn_shatter`'s own return),
## for test inspection — nothing in gameplay reads it.
func _spawn_shatter(world_pos: Vector2, disk_radius: float, color: Color, delay: float) -> int:
	if _shard_field == null:
		return -1
	var spawn_time := _shatter_clock + delay
	var origin := _shard_field.to_local(world_pos)
	# A dying node is stationary — its shards' entire velocity is their own
	# radial kick, never inherited momentum (#257 decision 7).
	return _shard_field.spawn_shatter(origin, disk_radius, color, Vector2.ZERO, spawn_time,
			shatter_shard_count, shatter_fling_speed)


## Blade-pop burst (#170): a self-freeing one-shot spray at the contact point.
func _spawn_pop_burst(world_pos: Vector2, radius: float, color: Color) -> void:
	var stage := Node2D.new()
	add_child(stage)  # before `global_position` — see [method spawn_alloc_spike].
	stage.global_position = world_pos
	_emit_burst(stage, radius, color)
	var tween := create_tween()
	tween.tween_interval(POP_BURST_DURATION)
	tween.tween_callback(stage.queue_free)


func _emit_burst(parent: Node2D, disk_radius: float, color: Color) -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = SHATTER_PARTICLE_COUNT
	particles.lifetime = SHATTER_PARTICLE_LIFETIME
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = SHATTER_OUTWARD_SPEED * 0.6
	particles.initial_velocity_max = SHATTER_OUTWARD_SPEED
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = color
	# Fade-out alpha curve so particles fizzle.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = ramp
	# Spawn distributed inside the snapshot disk so the burst reads as the
	# disk shattering, not a point implosion.
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = max(1.0, disk_radius)
	parent.add_child(particles)
	particles.emitting = true


static func _make_snapshot_disk(disk_radius: float, color: Color) -> Node2D:
	var disk := _SnapshotDisk.new()
	disk.disk_radius = max(1.0, disk_radius)
	disk.disk_color = color
	return disk


## Lorentzian (Breit-Wigner-ish) needle profile. Base sits at y=0 with full
## width `2 * half_w`; tip pinned to (0, -height). γ controls how aggressively
## the sides pinch toward the tip — see SPIKE_NEEDLE_GAMMA.
##
## Polygon wound CCW: right-side base → right shoulder → tip → left shoulder
## → left base. y axis points DOWN in Godot, so "up" is negative y.
static func _build_needle_polygon(half_w: float, height: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var gamma_sq := SPIKE_NEEDLE_GAMMA * SPIKE_NEEDLE_GAMMA
	# Right side: bottom (t=0) → just-below-tip (t≈1). Skip t=1 here; the
	# tip vertex is appended explicitly so its width is exactly 0.
	for i in SPIKE_SAMPLES:
		var t := float(i) / float(SPIKE_SAMPLES)
		var w := half_w * gamma_sq / (gamma_sq + t * t)
		# (1 - t^6) eases the last few samples cleanly into the pinned tip
		# so there's no kink between the lorentzian shoulder and the apex.
		w *= 1.0 - pow(t, 6.0)
		pts.append(Vector2(w, -t * height))
	pts.append(Vector2(0.0, -height))  # tip
	# Left side mirrored, walking back down toward the base.
	for i in range(SPIKE_SAMPLES - 1, -1, -1):
		var t := float(i) / float(SPIKE_SAMPLES)
		var w := half_w * gamma_sq / (gamma_sq + t * t)
		w *= 1.0 - pow(t, 6.0)
		pts.append(Vector2(-w, -t * height))
	return pts


# Local helper class — a Node2D that renders one filled circle. Future texture
# swap: replace _draw with a Sprite2D; keep the same disk_radius / disk_color
# API and all callers stay valid.
class _SnapshotDisk extends Node2D:
	var disk_radius: float = 16.0
	# Property with setter so tween_property("disk_color", ...) repaints
	# every frame — without this the colour change isn't visible.
	var disk_color: Color = Color.WHITE:
		set(value):
			disk_color = value
			queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, disk_radius, disk_color, true)
