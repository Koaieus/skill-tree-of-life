@tool
class_name GateRope
extends Node2D

## The transient rope a [Gate] plays when its edge appears or vanishes —
## presentation only: the topology has already flipped, nothing waits on it.
## Closed form in `gate_rope.gdshader`: a throw (eased tip, trailing sag), a
## latch flash on the far node, then a damped string ring
## `A·sin(πu)·e^(−t/τ)·cos(ωt)` + a second harmonic, with ω ∝ 1/span; a close
## snaps at the midpoint and whips each half home. Frees itself when done.
## See `docs/design/skill_node_addons.md` § Gate, "The flip has a body".

## Fraction of the real edge that should show, 0 → 1 across the settle window;
## the rope fades out as `1 − reveal`. Emitted every frame of an open.
signal reveal_changed(value: float)
signal finished

enum Mode { THROW, HANDSHAKE, SNAP }

const SEGMENTS := 16

@export_group("Throw")
@export_range(0.02, 2.0, 0.01, "suffix:s") var throw_duration := 0.22
## Trailing sag at the start of the throw, as a fraction of the span.
@export_range(0.0, 1.0, 0.01) var sag := 0.25
@export_group("Thwang")
## Peak string displacement at the latch, as a fraction of the span.
@export_range(0.0, 0.5, 0.005) var thwang_amplitude := 0.08
@export_range(0.02, 3.0, 0.01, "suffix:s") var decay_tau := 0.35
## Ring frequency at [member reference_span_px]; a longer rope rings lower.
@export_range(0.5, 40.0, 0.1, "suffix:Hz") var base_frequency_hz := 9.0
@export_range(0.0, 1.0, 0.01) var harmonic2_mix := 0.2
## Span that rings at exactly [member base_frequency_hz]. 0 = use what the
## caller passes to [method play] (a Gate passes its graph's median edge).
@export_range(0.0, 2000.0, 1.0, "suffix:px") var reference_span_px := 0.0
## After the latch: how long the real edge takes to fade in under the rope.
@export_range(0.05, 4.0, 0.01, "suffix:s") var settle_duration := 1.0
@export_group("Snap")
@export_range(0.02, 2.0, 0.01, "suffix:s") var snap_duration := 0.18
## How far each snapped half's free end flails, as a fraction of the span.
@export_range(0.0, 0.5, 0.005) var snap_whip := 0.15
@export_group("Look")
@export_range(0.5, 16.0, 0.1) var width := 3.0
@export var rope_tier := Emissive.Tier.VALUE
## Flash on the far node when a single throw latches.
@export var latch_flash := Emissive.Tier.PEAK
## Flash of the knot where a handshake's two ropes meet.
@export var handshake_meet_flash := Emissive.Tier.PEAK
@export_range(1.0, 60.0, 0.5, "suffix:px") var flash_radius := 12.0
## How long the latch / meet flash takes to fade out (quadratic falloff).
@export_range(0.02, 1.0, 0.01, "suffix:s") var flash_duration := 0.3

var mode := Mode.THROW
var elapsed := 0.0
var span := 0.0

var _flash_color := Color.WHITE
var _playing := false

@onready var _strip: MeshInstance2D = $Strip


func _ready() -> void:
	set_process(_playing)


## Start playing between two world points. [param from_global] is the
## thrower's rim (a snap's `from` end); [param color_from] / [param color_to]
## are the ends' SDR hues — the rope lifts them to [member rope_tier].
func play(p_mode: Mode, from_global: Vector2, to_global: Vector2,
		color_from: Color, color_to: Color, reference_span := 0.0) -> void:
	mode = p_mode
	elapsed = 0.0
	span = maxf(from_global.distance_to(to_global), 1.0)
	global_position = from_global
	global_rotation = (to_global - from_global).angle()
	var ref := reference_span_px if reference_span_px > 0.0 else reference_span
	if ref <= 0.0:
		ref = span
	var stops := Emissive.stops(rope_tier)
	_flash_color = Emissive.at(color_to if mode == Mode.THROW else color_from.lerp(color_to, 0.5),
		Emissive.stops(handshake_meet_flash if mode == Mode.HANDSHAKE else latch_flash))
	_strip.mesh = RopeStrip.build(span, SEGMENTS, 2)
	var mat := _strip.material as ShaderMaterial
	mat.set_shader_parameter(&"mode", int(mode))
	mat.set_shader_parameter(&"span_px", span)
	mat.set_shader_parameter(&"width", width)
	mat.set_shader_parameter(&"throw_duration", throw_duration)
	mat.set_shader_parameter(&"sag", sag)
	mat.set_shader_parameter(&"thwang_amplitude", thwang_amplitude)
	mat.set_shader_parameter(&"decay_tau", decay_tau)
	mat.set_shader_parameter(&"omega", TAU * base_frequency_hz * ref / span)
	mat.set_shader_parameter(&"harmonic2_mix", harmonic2_mix)
	mat.set_shader_parameter(&"snap_duration", snap_duration)
	mat.set_shader_parameter(&"snap_whip", snap_whip)
	mat.set_shader_parameter(&"color_a", Emissive.at(color_from, stops))
	mat.set_shader_parameter(&"color_b", Emissive.at(color_to, stops))
	var reach := maxf(maxf(sag, thwang_amplitude * (1.0 + harmonic2_mix)), snap_whip) * span + width * 4.0
	RenderingServer.canvas_item_set_custom_rect(_strip.get_canvas_item(), true,
		Rect2(-reach, -reach, span + 2.0 * reach, 2.0 * reach))
	_playing = true
	_push_time()
	set_process(true)


## Total play time of the current mode.
func duration() -> float:
	if mode == Mode.SNAP:
		return snap_duration
	return throw_duration + settle_duration


## 0 until the latch, then eased to 1 across [member settle_duration].
func reveal() -> float:
	if mode == Mode.SNAP:
		return 0.0
	return smoothstep(0.0, 1.0, (elapsed - throw_duration) / settle_duration)


func _process(delta: float) -> void:
	if not _playing:
		return
	elapsed += delta
	_push_time()
	queue_redraw()
	if mode != Mode.SNAP:
		reveal_changed.emit(reveal())
	if elapsed >= duration():
		_playing = false
		set_process(false)
		finished.emit()
		queue_free()


func _push_time() -> void:
	var mat := _strip.material as ShaderMaterial
	mat.set_shader_parameter(&"t", elapsed)
	mat.set_shader_parameter(&"fade", 1.0 - reveal())


## The latch / meet flash: a disc on the far node (throw) or the knot at the
## midpoint (handshake), decaying from the latch.
func _draw() -> void:
	if not _playing or mode == Mode.SNAP:
		return
	var since := elapsed - throw_duration
	if since < 0.0:
		return
	var fall := 1.0 - since / flash_duration
	if fall <= 0.0:
		return
	var k := fall * fall
	var at := Vector2(span, 0.0) if mode == Mode.THROW else Vector2(span * 0.5, 0.0)
	var c := _flash_color
	c.a *= k
	draw_circle(at, flash_radius * (1.0 + 0.6 * (1.0 - k)), c)
