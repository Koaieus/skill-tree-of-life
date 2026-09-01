@tool
class_name BoltBody
extends Node2D

## The spell-VFX workhorse body (#670 P1) — one additive sprite quad plus an
## optional 0-4 segment micro-trail, all drawing from ONE shared texture
## ([code]bolt_head_texture.tres[/code]) and ONE shared [CanvasItemMaterial]
## ([code]bolt_additive_material.tres[/code]).
##
## [b]The batching contract is the whole design.[/b] Batching breaks on a
## different texture [i]or[/i] a different material
## (docs/domain/rendering-performance.md), and Resonator peaks at ~30-60
## simultaneous bolts (#663's load table). So every instance shares those two
## resources and all per-instance variation rides [member Node2D.scale],
## [member Node2D.rotation] and [member CanvasItem.modulate]. Never give one
## instance its own [ShaderMaterial]; that single change turns ~60 batched
## quads into ~60 draw calls.
##
## Identity is [b]motion and heat, never hue[/b] (#663 D3): the five shipped
## configs differ by silhouette, trail and size-ramp, and the body colour is
## the [b]caster's[/b] identity tint (#663 D4) stamped by the coordinator —
## the same [code]tint[/code] stamp precedent [ArrowVolleyCoordinator] already
## uses on [LightArrow]. [GlowingDot]'s reserved-gold default does not carry
## forward.
##
## Five inherited configs ship next to this scene and are the vocabulary the
## per-spell units select from — [code]bolt_small[/code] (Spark),
## [code]bolt_blunt[/code] (Bruiser), [code]bolt_streak[/code] (Leafblower),
## [code]bolt_packet[/code] (Reverberator/Resonator), [code]bolt_soft[/code]
## (Healing Beam).
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`,
##              `_on_crit(tier)`, `_on_context(entry)`
##   outbound — [signal finished]
##
## [GlowingDot] is NOT deleted — it still has non-spell callers, and retiring
## it is separate cleanup (#663 NOTES).

signal finished

## The shared pair. Referenced here as constants so a test (and a reader) can
## assert identity without reaching into the scene tree, and so an accidental
## `.duplicate()` anywhere shows up as a failing identity check.
const HEAD_TEXTURE: Texture2D = preload("res://ui/vfx/projectile/visual/bolt_head_texture.tres")
const SHARED_MATERIAL: CanvasItemMaterial = preload("res://ui/vfx/projectile/visual/bolt_additive_material.tres")

## Max trail segments authored in the scene. [member trail_length] clamps here.
const MAX_TRAIL_SEGMENTS: int = 4

## Native pixel size of [constant HEAD_TEXTURE]; [member head_size] divides by
## it to reach a sprite scale.
const _TEXTURE_SIZE: float = 64.0

## Caster identity colour, stamped by the coordinator after `proj.launch()`
## exactly like [member LightArrow.tint]. White = "no identity supplied", which
## reads as the neutral off-white body rather than as reserved gold.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_apply_look()

## Emissive tier the body sits at. [constant Emissive.VALUE] is "this is lit";
## [constant Emissive.LABEL] is the alpha-led whisper the Healing Beam config
## wants. Never a hand-picked float — see docs/domain/hdr-color.md.
@export_range(0.0, 3.0, 0.05) var emissive_tier: float = Emissive.VALUE:
	set(value):
		emissive_tier = value
		_apply_look()

## Hop-driven emissive-tier ramp, the tier equivalent of [member hop_scale_start]
## / [member hop_scale_end] below — lerped by the same hop fraction. `-1.0` is a
## sentinel meaning "unset -> fall back to [member emissive_tier]", so a config
## that sets neither (every one shipped before #686) holds a flat tier across
## the whole hop, byte-identical to today. Never a hand-picked float on either
## end — see docs/domain/hdr-color.md.
@export_range(0.0, 3.0, 0.05) var emissive_tier_start: float = -1.0:
	set(value):
		emissive_tier_start = value
		_apply_look()
@export_range(0.0, 3.0, 0.05) var emissive_tier_end: float = -1.0:
	set(value):
		emissive_tier_end = value
		_apply_look()

## Head diameter in world pixels at [member hop_scale_start].
@export_range(1.0, 96.0, 0.5) var head_size: float = 14.0:
	set(value):
		head_size = value
		_apply_look()

## How many trail segments trail the head. 0 = a bare head (Blunt, Soft).
@export_range(0, MAX_TRAIL_SEGMENTS, 1) var trail_length: int = 3:
	set(value):
		trail_length = clampi(value, 0, MAX_TRAIL_SEGMENTS)
		_apply_look()

## Progress samples between consecutive trail segments — the trail's *length*
## in time rather than in pixels, so it reads the same at any flight speed.
@export_range(1, 12, 1) var trail_stride: int = 3

## Head scale of the hindmost trail segment, as a fraction of the head's.
@export_range(0.0, 1.0, 0.05) var trail_taper: float = 0.35

## 0 = a symmetric disc. 1 = the head stretches along travel and squashes
## across it by the same factor — the squash-and-stretch the Blunt (piston)
## and Streak (gust) configs are built on. Requires the [Projectile] to be
## `face_velocity` so local +X is forward.
@export_range(0.0, 3.0, 0.05) var stretch_along_velocity: float = 0.0

## Size ramp across the cast, driven by the hop fraction `_on_context(entry)`
## carries — as #543's `beat_index` / `beat_count` pair, or as an explicit
## `hop_fraction`. See [method VfxContext.read_hop_fraction].
## This is #663 D3's deliberate teaching pair: Lightning SHRINKS per hop
## (end < 1) while Leafblower GROWS (end > 1), so "bolt size means current
## damage" becomes learned vocabulary. Both default to 1.0 — a visual that
## never receives a context entry never ramps.
@export_range(0.1, 4.0, 0.05) var hop_scale_start: float = 1.0
@export_range(0.1, 4.0, 0.05) var hop_scale_end: float = 1.0

## Post-arrival drain before [signal finished]. Also how long the trail keeps
## dissipating after the head lands.
@export_range(0.0, 2.0, 0.01) var fade_seconds: float = 0.28

## How much of the wave this ONE arc is carrying, stamped per projectile by the
## coordinator exactly as [member tint] is (#708). 1.0 = undivided, which is
## what every spell that does not split its damage across a fan means.
##
## Per-ARC and not per-landing, which is why it cannot ride `_on_context`: a
## [ScheduleEntry] is one landing moment, and a convergence is one entry holding
## several arcs.
@export_range(0.0, 2.0, 0.01) var arc_weight: float = 1.0:
	set(value):
		arc_weight = maxf(0.0, value)
		_apply_look()

## How far [member arc_weight] moves the body's size. 0 = ignored entirely,
## which is the default and why this is strictly additive: the eight spells that
## do not split their damage are untouched. 1 = direct proportion, so a rank-3
## offshoot carrying 0.20 draws at a fifth of the spine.
##
## Direct proportion is the honest setting, because "bolt size means current
## damage" is already learned vocabulary from #663 D3's Lightning/Leafblower
## teaching pair — a splitting spell is saying the same sentence about the same
## quantity, one hop earlier.
@export_range(0.0, 1.0, 0.05) var arc_weight_influence: float = 0.0:
	set(value):
		arc_weight_influence = clampf(value, 0.0, 1.0)
		_apply_look()

@onready var _head: Sprite2D = %Head
@onready var _trail_root: Node2D = %Trail

var _segments: Array[Sprite2D] = []
var _history: PackedVector2Array = []
var _emitting: bool = false
var _arrived: bool = false
var _done_emitted: bool = false
var _alpha: float = 1.0
## Multiplier from `_on_crit`, applied on top of [member head_size].
var _crit_scale: float = 1.0
## Set by `_on_crit`; overrides [member tint] for the body once a crit lands.
var _crit_tint: Color = Color.WHITE
var _has_crit: bool = false
## Latest `hop_fraction` seen through `_on_context`, 0..1.
var _hop_fraction: float = 0.0


func _ready() -> void:
	_segments.clear()
	for child in _trail_root.get_children():
		if child is Sprite2D:
			var seg: Sprite2D = child
			# Trail segments live in WORLD space — they mark where the head
			# *was*, so the parent's motion must not drag them along.
			seg.top_level = true
			_segments.append(seg)
	_apply_look()
	# Idle until launched — a coordinator instantiates these ahead of the beat.
	set_process(false)


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	_emitting = true
	_history.clear()
	_apply_look()
	set_process(true)


func _on_progress(t: float) -> void:
	if not _emitting:
		return
	_history.append(global_position)
	var cap: int = MAX_TRAIL_SEGMENTS * trail_stride + 2
	if _history.size() > cap:
		_history = _history.slice(_history.size() - cap)
	# A visual that receives no ScheduleEntry still ramps across its own
	# flight, which is the honest reading of "size follows the hop".
	if is_equal_approx(_hop_fraction, 0.0):
		_apply_look(t)
	_place_segments()


func _on_arrival() -> void:
	_emitting = false
	_arrived = true
	if _done_emitted:
		return
	if fade_seconds <= 0.0:
		_emit_finished()
		return
	var tween := create_tween()
	tween.tween_property(self, ^"_alpha", 0.0, fade_seconds)
	tween.tween_callback(_emit_finished)
	set_process(true)


## #663 D6's uniform crit grammar, body half: retint to damage red at
## [constant Emissive.ALERT] and swell. The ring half lives in [ImpactRing],
## authored once there rather than eight times.
func _on_crit(tier: int) -> void:
	if tier <= 0:
		return
	var t: float = clampf(float(tier), 1.0, 2.0)
	_has_crit = true
	_crit_scale = lerpf(1.3, 1.8, t - 1.0)
	_crit_tint = Color.ORANGE_RED.lerp(Color.RED, t - 1.0)
	_apply_look()


## #543 D6's [code]ScheduleEntry[/code]. [b]Deliberately typed [Variant][/b]:
## that class does not exist yet, and a typed parameter would refuse to parse.
## The visual contract is duck-typed anyway ("any subset, all optional"), so
## every field below is read defensively; a visual that needs one tightens the
## type in its own unit once #543 merges.
func _on_context(entry: Variant) -> void:
	if entry == null:
		return
	var frac: float = VfxContext.read_hop_fraction(entry, -1.0)
	if frac >= 0.0:
		_hop_fraction = clampf(frac, 0.0, 1.0)
		_apply_look()


# ------------------------------------------------------------------- internals


func _process(_delta: float) -> void:
	if _arrived:
		_apply_look()
		_place_segments()


func _emit_finished() -> void:
	if _done_emitted:
		return
	_done_emitted = true
	set_process(false)
	finished.emit()


## Body colour + scale. The ONLY per-instance channels touched are `modulate`,
## `scale` and `self_modulate` — never a shader uniform, never a material swap.
func _apply_look(progress_hint: float = -1.0) -> void:
	if _head == null:
		return
	var frac: float = _hop_fraction
	if frac <= 0.0 and progress_hint >= 0.0:
		frac = clampf(progress_hint, 0.0, 1.0)

	var ramp: float = lerpf(hop_scale_start, hop_scale_end, frac)
	# Tier's own ramp, right beside the scale one above — same `frac`, same
	# sentinel-resolution idiom (#686).
	var tier_start: float = emissive_tier_start if emissive_tier_start >= 0.0 else emissive_tier
	var tier_end: float = emissive_tier_end if emissive_tier_end >= 0.0 else emissive_tier
	var tier_ramp: float = lerpf(tier_start, tier_end, frac)

	var base: Color = _crit_tint if _has_crit else tint
	var tier: float = Emissive.ALERT if _has_crit else tier_ramp
	var col: Color = Emissive.tint(base, tier)
	col.a = base.a * clampf(_alpha, 0.0, 1.0)
	modulate = col

	var diameter: float = head_size * ramp * _crit_scale * arc_scale()
	var s: float = diameter / _TEXTURE_SIZE
	# Squash-and-stretch along local +X (the [Projectile] rotates us so +X is
	# forward when `face_velocity` is on). Volume-preserving: whatever the head
	# gains along travel it loses across it. Derived from `s` every time, so
	# stretch can never compound frame over frame.
	var k: float = 1.0 + stretch_along_velocity
	_head.scale = Vector2(s * k, s / k)

	for i in _segments.size():
		var seg: Sprite2D = _segments[i]
		var live: bool = i < trail_length
		seg.visible = live and (_emitting or _arrived)
		if not live:
			continue
		var back: float = float(i + 1) / float(MAX_TRAIL_SEGMENTS)
		var taper: float = lerpf(1.0, trail_taper, back)
		seg.scale = Vector2(s * taper, s * taper)
		# Alpha is the fade channel; the colour value stays at the body tier
		# (docs/domain/hdr-color.md) so a trail segment still blooms.
		seg.self_modulate = Color(1.0, 1.0, 1.0, lerpf(0.7, 0.05, back))


func _place_segments() -> void:
	if _history.is_empty():
		return
	for i in _segments.size():
		if i >= trail_length:
			continue
		var back: int = (i + 1) * trail_stride
		var idx: int = maxi(0, _history.size() - 1 - back)
		_segments[i].global_position = _history[idx]


## The size factor [member arc_weight] contributes — 1.0 whenever the spell has
## opted out, so the eight non-splitting spells provably take the old path.
func arc_scale() -> float:
	return lerpf(1.0, arc_weight, arc_weight_influence)
