@tool
class_name AllocationVFX
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## Listens to AllocationSystem (allocate / dealloc) and BattleSystem
## (cascade_started) and spawns transient world-space effects:
##   - alloc spike   : "skill point from the heavens" on every allocation
##   - dealloc lift  : floating colored disk on voluntary deallocation
##   - shatter       : vibrate + particle burst on forced deallocation,
##                     staggered by BFS-distance-from-impact when part of a
##                     battle cascade
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

const SHATTER_VIBRATE_DURATION: float = 0.8
const SHATTER_VIBRATE_AMPLITUDE: float = 2.5
const SHATTER_VIBRATE_FREQ: float = 60.0  # hz
const SHATTER_BURST_DURATION: float = 2.40
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



func _ready() -> void:
	# Absolute z (z_as_relative = false) so children inherit the same effective
	# z floor — otherwise a transient effect added under us would be at
	# parent_z + child_z and could land below a fog-promoted node.
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX
	bind(allocation_system, battle_system)

func bind(_allocation_system: AllocationSystem, _battle_system: BattleSystem) -> void:
	# `_ready()` runs unguarded in the editor too (this script has no other
	# is_editor_hint gate), and the NodePath-resolved systems are bare `Node`s
	# there — their scripts only attach when actually running. Skip wiring
	# entirely rather than touching a placeholder's signals (see
	# `.claude/rules/gdscript-pitfalls.md`).
	if Engine.is_editor_hint():
		return
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
	disk.global_position = world_pos
	disk.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)
	container.add_child(disk)

	var spike := Polygon2D.new()
	spike.polygon = _build_needle_polygon(inner_radius, node_radius * SPIKE_HEIGHT_FACTOR)
	# Polygon2D.color is the draw tint — alpha here multiplies with modulate.a,
	# so keep it opaque and animate visibility via modulate.a only.
	spike.color = color
	spike.global_position = world_pos
	spike.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)
	container.add_child(spike)

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


func _spawn_lift(world_pos: Vector2, disk_radius: float, color: Color) -> void:
	var disk := _make_snapshot_disk(disk_radius, color)
	disk.global_position = world_pos
	add_child(disk)
	var rise := disk_radius * LIFT_RISE_FACTOR
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(disk, "position:y", world_pos.y - rise, LIFT_DURATION)\
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


## Node "death" animation: start vibrating and then *pop* shatter into pieces
func _spawn_shatter(world_pos: Vector2, disk_radius: float, color: Color, delay: float) -> void:
	# Wrapper Node2D holds the vibrating snapshot disk; particles spawn at
	# burst time as a sibling. Whole thing self-frees when both children are done.
	var stage := Node2D.new()
	stage.global_position = world_pos
	add_child(stage)
	var disk := _make_snapshot_disk(disk_radius, color)
	stage.add_child(disk)
	# Stay visible through the pre-vibrate delay — the real SkillNode's owned
	# fill clears immediately on force_deallocate, so the snapshot has to stand
	# in continuously or the node visibly vanishes until its cascade ring fires.

	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	# Vibrate: tiny sine-driven offset, amplitude ramping up over the duration.
	var steps := int(SHATTER_VIBRATE_DURATION * 60.0)
	
	for s in steps:
		var u := float(s) / float(steps)
		var vibration_intensity := lerpf(0., SHATTER_VIBRATE_AMPLITUDE, u)
		var dx := sin(u * SHATTER_VIBRATE_FREQ * TAU) * vibration_intensity
		var dy := cos(u * SHATTER_VIBRATE_FREQ * TAU * 0.7) * vibration_intensity
		tween.tween_property(disk, "position", Vector2(dx, dy),
				SHATTER_VIBRATE_DURATION / float(steps))
	# Burst: hide disk, emit particles.
	tween.tween_callback(func() -> void:
		disk.visible = false
		_emit_burst(stage, disk_radius, color))
	tween.tween_interval(SHATTER_BURST_DURATION)
	tween.tween_callback(stage.queue_free)


## Blade-pop burst (#170): a self-freeing one-shot spray at the contact point.
func _spawn_pop_burst(world_pos: Vector2, radius: float, color: Color) -> void:
	var stage := Node2D.new()
	stage.global_position = world_pos
	add_child(stage)
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
