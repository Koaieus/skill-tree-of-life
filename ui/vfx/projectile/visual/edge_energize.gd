@tool
class_name EdgeEnergize
extends Node2D

## #670 P5 — an animated travelling front of light laid ALONG a real edge,
## drawn as an overlay quad. Trail Blazer's fuse and Resonator's converging
## waves are built on this.
##
## [b]Paint-on-top. It never touches [Edge], [Graph] or the edge MultiMesh[/b]
## (#670, settled — the reasoning lives in `edge_energize.gdshader`'s header and
## on the issue). The overlay frees itself and the edge was never written to, so
## there is no interrupt-restore semantics to get wrong: a cast cut short by
## teardown cannot leave an edge stuck energized.
##
## [b]One material, one texture, for every overlay alive.[/b] At Resonator's ~60
## that is one batch, not 60 draws — and the only thing that keeps it true is
## that per-instance animation rides [b]transform and [member CanvasItem.modulate]
## only[/b]. The ignition front is the quad's x-scale ([method set_front]);
## intensity is `modulate` through [Emissive] tiers. Animating a per-overlay
## shader UNIFORM duplicates the material and the batch is gone. See
## `test/unit/vfx/test_edge_energize.gd`, which pins exactly that.
##
## [b]Width tracks the edge, with no CPU mirror.[/b] The shader reads the same
## `edge_camera_zoom` global `graph/edge_mesh.gdshader` reads (pushed by
## `GraphCamera` on every zoom step), and [method _sync_width] pushes the edge
## material's own `width` onto the shared overlay material once at load. There
## is therefore no per-frame sync between edge and overlay that can drift.
##
## [b]Fog-oblivious[/b] (owner call 2026-08-30), matching every existing spell
## visual — see the shader header for the one-line upgrade whenever fog-gating
## arrives.
##
## [b]Concurrency is bounded by LINGER, not by hop count.[/b] Trail Blazer's
## `max_hops` bound is being removed (#663 D7), so N is unbounded and any
## assumption of 20 is wrong. What actually caps live overlays is
## [method max_live_overlays] — at the shipped 2.5 s linger over 0.4 s beats
## that is 7, whatever the path length.
##
## [b]Opt-in needs no new knob.[/b] The coordinator's per-verb `edge_visual`
## slot already expresses it: a spell that wants energized edges composes this
## scene in, one that does not, does not. A bool on the def or on the tempo
## resource would be a second parallel opt-in channel for something the slot
## system already says.
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`,
##              `_on_crit(tier)`, `_on_context(entry)`
##   outbound — [signal finished]

signal finished

## The one shared pair, named as constants so a test can assert identity and an
## accidental `.duplicate()` shows up as a failing check rather than as a
## silent 60x draw-call regression.
const SHARED_MATERIAL: ShaderMaterial = preload("res://ui/vfx/projectile/visual/edge_energize_material.tres")
const BAR_TEXTURE: Texture2D = preload("res://ui/vfx/projectile/visual/edge_energize_texture.tres")

## Read-only, and the ONLY reference this unit makes into `graph/`: the edge's
## own material, so the overlay's stroke width comes from the same authored
## number rather than from a copy of it. Never written to.
const EDGE_MATERIAL: ShaderMaterial = preload("res://graph/edge_mesh_material.tres")

## `ui/z_layers.gd` has no `class_name` — it is preloaded, per its own header.
const ZLayers = preload("res://ui/z_layers.gd")

const _WIDTH_PARAM: StringName = &"width"
const _OVERLAY_WIDTH_PARAM: StringName = &"edge_width"

## Caster identity colour, stamped by the coordinator exactly as
## [member BoltBody.tint] and [member LightArrow.tint] are.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_apply_look()

## Resting tier. [constant Emissive.VALUE] and not higher: a lit edge already
## carries a baked VALUE lift (`graph/edge.gd`'s `lit_glow_stops`), and
## additive-on-lifted goes white fast. The moving front's extra stop is the
## shader's `front_gain_stops`, which lands it at [constant Emissive.ALERT].
@export_range(0.0, 3.0, 0.05) var emissive_tier: float = Emissive.VALUE:
	set(value):
		emissive_tier = value
		_apply_look()

## Edge endpoints in the parent's space. The visual needs these UP FRONT — a
## quad cannot discover the edge by sampling its own flight the way
## [GlowingDot]'s trail does — so the coordinator stamps them after
## instantiation, the same stamp precedent [ArrowVolleyCoordinator] already uses
## for `tint`.
@export var edge_origin: Vector2 = Vector2.ZERO:
	set(value):
		edge_origin = value
		_place()

@export var edge_target: Vector2 = Vector2.ZERO:
	set(value):
		edge_target = value
		_place()

## How long the burnt-in overlay takes to fade once the front has arrived. This
## is the number [method max_live_overlays] is bounded by — retuning it changes
## peak overlay count, so read #663's load table before raising it.
@export_range(0.0, 8.0, 0.05) var linger_seconds: float = 2.5

## Fraction of the edge the overlay already covers when the front sets off.
## A hair above zero so the very first frame is a visible spark at the origin
## rather than a degenerate zero-width quad.
@export_range(0.0, 1.0, 0.01) var initial_front: float = 0.02

@onready var _bar: Sprite2D = %Bar

var _front: float = 0.0
var _alpha: float = 1.0
var _crit_stops: float = 0.0
var _done_emitted: bool = false


## Live overlays cap at `ceil(linger / beat) + 1`, regardless of how many hops
## the cast runs — a new one ignites every beat and each survives `linger`.
## State the bound THIS way: #663 D7 removes Trail Blazer's `max_hops`, so hop
## count is unbounded and any "at most 20" reasoning is wrong.
static func max_live_overlays(linger: float, beat_interval: float) -> int:
	if beat_interval <= 0.0:
		return 0
	return int(ceil(maxf(linger, 0.0) / beat_interval)) + 1


func _ready() -> void:
	_sync_width()
	# Above fog and above sensed nodes, the same promotion `AllocationVFX`
	# makes and for the same reason — see `ui/z_layers.gd`.
	z_index = ZLayers.SPELL_VFX
	_front = initial_front
	_place()
	_apply_look()


## Pushes the EDGE's authored stroke width onto the shared overlay material,
## once. A SHARED-material write (all overlays want the same value), never a
## per-instance one — that distinction is the whole batching claim. Reading it
## off `graph/edge_mesh_material.tres` rather than restating it here is what
## keeps the overlay from drifting when the edge is retuned.
static func _sync_width() -> void:
	var edge_width: Variant = EDGE_MATERIAL.get_shader_parameter(_WIDTH_PARAM)
	if edge_width is float or edge_width is int:
		SHARED_MATERIAL.set_shader_parameter(_OVERLAY_WIDTH_PARAM, float(edge_width))


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	set_front(initial_front)


## The front rides the projectile: the quad grows along the edge as the bolt
## travels it, so ignition and arrival are the same event seen twice.
func _on_progress(t: float) -> void:
	set_front(t)


func _on_arrival() -> void:
	set_front(1.0)
	if _done_emitted:
		return
	if linger_seconds <= 0.0:
		_emit_finished()
		return
	var tween := create_tween()
	tween.tween_property(self, ^"_alpha", 0.0, linger_seconds)
	tween.tween_callback(_emit_finished)
	set_process(true)


## Crit emphasis rides `modulate` like everything else here — never a uniform.
func _on_crit(tier: int) -> void:
	if tier <= 0:
		return
	# One stop, once: the front is already at ALERT, and PEAK is the ring's
	# (#663 D6 — [ImpactRing] owns the crit grammar, this only leans into it).
	_crit_stops = Emissive.ALERT - Emissive.VALUE
	_apply_look()


## Typed [Variant] on purpose — #543's `ScheduleEntry` does not exist yet and a
## typed parameter would refuse to parse.
func _on_context(entry: Variant) -> void:
	if entry == null:
		return
	var magnitude: float = VfxContext.read_float(entry, &"magnitude", -1.0)
	if magnitude >= 0.0:
		# Normalized magnitude leans the resting tier between LABEL and VALUE.
		# Named tiers at both ends — no hand-picked float (hdr-color.md).
		emissive_tier = lerpf(Emissive.LABEL, Emissive.VALUE, clampf(magnitude, 0.0, 1.0))


# ------------------------------------------------------------------- internals


func _process(_delta: float) -> void:
	_apply_look()


## The ignition front, 0..1 along the edge. [b]The quad's x-scale, and nothing
## else[/b] — no uniform is touched, which is what keeps every overlay on one
## material and therefore in one batch.
func set_front(value: float) -> void:
	_front = clampf(value, 0.0, 1.0)
	_place()


func _place() -> void:
	if _bar == null:
		return
	var along: Vector2 = edge_target - edge_origin
	position = edge_origin
	if along.length_squared() < 1e-6:
		# A self-loop routed here by mistake has no direction to lay light
		# along; draw nothing rather than normalise a zero vector.
		_bar.scale = Vector2(0.0, 1.0)
		return
	rotation = along.angle()
	var texture_width: float = maxf(1.0, float(BAR_TEXTURE.get_width()))
	# x carries the front; y stays at 1 because the shader owns the width (it
	# derives it from `edge_camera_zoom`, ignoring instance y-scale entirely).
	_bar.scale = Vector2(along.length() * _front / texture_width, 1.0)


## Colour and fade. The ONLY per-instance channels written anywhere in this
## class are `modulate`, `position`, `rotation` and the bar's `scale`.
func _apply_look() -> void:
	var col: Color = Emissive.tint(tint, emissive_tier + _crit_stops)
	col.a = tint.a * clampf(_alpha, 0.0, 1.0)
	modulate = col


func _emit_finished() -> void:
	if _done_emitted:
		return
	_done_emitted = true
	set_process(false)
	finished.emit()
