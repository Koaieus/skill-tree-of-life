@tool
class_name TrailBlazerEdgeVisual
extends Node2D

## #673 edge treatment — the fuse. Composes the shared kit's [EdgeEnergize]
## (#670 P5) so a hop's ignited wire can also drive Trail Blazer's junction
## slam: a degree-2 string produces one [EdgeEnergize] overlay per hop, and
## only the LAST one — read off [member ScheduleEntry.is_terminal], never a
## hop-count guess (#663 D7: the walk is unbounded) — also detonates.
##
## [b]The slam[/b] is a double [ImpactRing] at [constant Emissive.ALERT] plus
## a single-frame [constant Emissive.PEAK] core, forced to the tier-2 grammar
## shape regardless of whether the hit actually crit — #663's one deliberate
## non-crit PEAK. It stays pinned to the spell's own hue even on a genuine
## crit (achieved by handing [member ImpactRing.crit_color] the caster tint,
## so the ring's own crit-retint has nowhere else to go); a genuine crit
## instead STACKS a second, wider ring using the kit's standard red grammar
## around it, so the two loudnesses read apart rather than one lying about
## the other.
##
## [b]Escapes the moving [Projectile] parent via [member Node2D.top_level].[/b]
## [EdgeEnergize] anchors itself with an absolute `edge_origin`/`edge_target`
## (see its own class docs — "in the parent's space"), but this wrapper's
## actual parent is a [Projectile] whose own `global_position` moves along
## the same edge every frame as it flies EDGE's `LinearPath`. Left alone, the
## overlay would ride glued to wherever the projectile head currently is
## instead of drawing the whole wire. [BoltBody] escapes an equivalent
## problem — its own trail segments outliving a moving head — with the exact
## same flag (`ui/vfx/projectile/visual/bolt_body.gd`).
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`,
##              `_on_crit(tier)`, `_on_context(entry)`
##   outbound — [signal finished]

signal finished

const EDGE_ENERGIZE_SCENE: PackedScene = preload("res://ui/vfx/projectile/visual/edge_energize.tscn")
const IMPACT_RING_SCENE: PackedScene = preload("res://ui/vfx/projectile/visual/impact_ring.tscn")

## Caster identity tint, stamped by the coordinator exactly as every other
## visual in the kit (#663 D4).
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if _overlay != null:
			_overlay.tint = value

## Forwarded straight onto the inner [EdgeEnergize] — concurrency is bounded
## by THIS, never by hop count (#663 D7). See
## [method EdgeEnergize.max_live_overlays]. Left at the kit's own authored
## default so #663's peak-load table (1 head + ~7 lingering) stays true.
@export_range(0.0, 8.0, 0.05) var linger_seconds: float = 2.5

## Slam ring geometry — the spell-hue tier-2 grammar ring.
@export_range(1.0, 128.0, 0.5) var slam_radius: float = 14.0
@export_range(1.0, 256.0, 0.5) var slam_expand_radius: float = 46.0

var _overlay: EdgeEnergize
var _is_terminal: bool = false
var _crit_tier: int = 0
var _slam_pending: int = 0
var _overlay_done: bool = false
var _arrival_handled: bool = false
var _done_emitted: bool = false


func _ready() -> void:
	# Same guard [ComposedProjectileVisual] uses: a `@tool` script that spawns
	# a child would otherwise leave a phantom node offered for saving the
	# moment this scene is opened in the editor. Scoped to the EDITED scene,
	# not the editor process, so a live sandbox tab still gets its overlay.
	if VfxEditorScene.is_edited(self):
		return
	# The overlay's `edge_origin`/`edge_target` are authored as absolute world
	# positions (see class docs); this flag is what makes "this wrapper's
	# space" actually BE world space regardless of where the owning
	# [Projectile] currently sits or is travelling to.
	top_level = true
	_overlay = EDGE_ENERGIZE_SCENE.instantiate()
	_overlay.linger_seconds = linger_seconds
	_overlay.tint = tint
	add_child(_overlay)
	_overlay.finished.connect(_on_overlay_finished)


# ---------------------------------------------------------------- duck contract


func _on_context(entry: Variant) -> void:
	_is_terminal = VfxContext.read_bool(entry, &"is_terminal", false)
	if _overlay == null:
		return
	var origin: SkillNode = _read_node(entry, &"origin")
	if origin != null:
		_overlay.edge_origin = origin.global_position
	var target: SkillNode = _read_node(entry, &"target")
	if target != null:
		_overlay.edge_target = target.global_position
	# Heat ramps off the WALK's position (#673: LABEL → VALUE → brushing
	# ALERT), not off the generic hit magnitude EdgeEnergize's own
	# `_on_context` would otherwise read — intermediate hops carry no hit at
	# all (Trail Blazer only deals damage at the junction), so magnitude is
	# never the honest signal here.
	_overlay.emissive_tier = _heat_for_fraction(VfxContext.read_hop_fraction(entry, 0.0))


func _on_launch() -> void:
	if _overlay != null:
		_overlay._on_launch()


func _on_progress(t: float) -> void:
	if _overlay != null:
		_overlay._on_progress(t)


func _on_crit(tier: int) -> void:
	_crit_tier = tier
	if _overlay != null:
		_overlay._on_crit(tier)


func _on_arrival() -> void:
	if _overlay != null:
		_overlay._on_arrival()
	if _is_terminal:
		_slam()
	_arrival_handled = true
	_check_done()


# ------------------------------------------------------------------- internals


func _read_node(entry: Variant, field: StringName) -> SkillNode:
	if entry is Object and field in entry:
		var v: Variant = entry.get(field)
		if v is SkillNode:
			return v
	return null


func _heat_for_fraction(f: float) -> float:
	var k: float = clampf(f, 0.0, 1.0)
	if k < 0.5:
		return lerpf(Emissive.LABEL, Emissive.VALUE, k / 0.5)
	# Brushes ALERT on the final approach without ever reaching it — ALERT
	# stays reserved for the slam and for a genuine crit.
	return lerpf(Emissive.VALUE, Emissive.ALERT, (k - 0.5) / 0.5 * 0.9)


## The junction detonation (#673) — see class docs for the crit-stacking
## rationale.
func _slam() -> void:
	var target_pos: Vector2 = _overlay.edge_target if _overlay != null else global_position

	var slam := IMPACT_RING_SCENE.instantiate() as ImpactRing
	slam.top_level = true
	slam.global_position = target_pos
	slam.tint = tint
	slam.crit_color = tint  # never retints red — stays on the spell's own hue
	slam.crit_tier = 2  # always the tier-2 shape: double ring + PEAK core
	slam.radius = slam_radius
	slam.expand_radius = slam_expand_radius
	add_child(slam)
	_track(slam)
	slam._on_arrival()

	if _crit_tier > 0:
		# The genuine crit — standard red grammar, stacked wider so it reads
		# as surrounding the spell-hue core rather than replacing it.
		var crit_ring := IMPACT_RING_SCENE.instantiate() as ImpactRing
		crit_ring.top_level = true
		crit_ring.global_position = target_pos
		crit_ring.radius = slam_radius * 1.3
		crit_ring.expand_radius = slam_expand_radius * 1.3
		crit_ring.crit_tier = _crit_tier
		add_child(crit_ring)
		_track(crit_ring)
		crit_ring._on_arrival()


func _track(node: Node) -> void:
	if not node.has_signal(&"finished"):
		return
	_slam_pending += 1
	node.finished.connect(func() -> void:
		_slam_pending -= 1
		_check_done())


func _on_overlay_finished() -> void:
	_overlay_done = true
	_check_done()


func _check_done() -> void:
	if not _arrival_handled or _done_emitted or _slam_pending > 0 or not _overlay_done:
		return
	_done_emitted = true
	# Deferred, matching [ComposedProjectileVisual]: a same-frame completion
	# (e.g. `linger_seconds == 0`) would otherwise emit before
	# `Projectile._wait_for_visual_done`'s `await finished` has registered.
	call_deferred(&"emit_signal", &"finished")
