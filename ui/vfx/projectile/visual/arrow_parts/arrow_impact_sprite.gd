@tool
class_name ArrowImpactSprite
extends ArrowPart

## A mark left by a counting landing that outlives the shaft — a hex sigil, a
## pustule, a gilt ring. Draws [member texture] (or, with none, a ring) at the
## arrowhead or the node's centre, its size and alpha following
## [member scale_curve] / [member alpha_curve] over [member lifetime].
## Crit-grammar rings are [ImpactRing]'s, not this part's.

enum Anchor {
	## Where the arrow stuck.
	TIP,
	## The target node's centre ([member ArrowImpactContext.position]).
	NODE,
}

@export var texture: Texture2D
@export var anchor: Anchor = Anchor.TIP
## Seconds the mark lives — also this part's drain.
@export_range(0.05, 6.0, 0.01) var lifetime: float = 1.0
## Size in world pixels at curve value 1 (the ring's radius, the texture's long side).
@export_range(1.0, 256.0, 0.5) var size: float = 16.0
## Ring stroke, world pixels, when there is no texture.
@export_range(0.5, 12.0, 0.1) var ring_width: float = 1.5
## Scale over normalised lifetime; none = 1 throughout.
@export var scale_curve: Curve
## Alpha over normalised lifetime; none = a linear fade out.
@export var alpha_curve: Curve
@export var tier: Emissive.Tier = Emissive.Tier.VALUE

var _tint: Color = Color(0, 0, 0, 0)
## Normalised age; < 0 until the impact.
var _t: float = -1.0


func _ready() -> void:
	set_process(false)


func paint(tint: Color, dud: bool, absorbed: bool) -> void:
	super.paint(tint, dud, absorbed)
	_tint = tint
	queue_redraw()


func arrive(ctx: ArrowImpactContext) -> void:
	if anchor == Anchor.NODE and ctx != null:
		top_level = true
		global_position = ctx.position
		rotation = 0.0
	_t = 0.0
	set_process(true)


func drain_seconds() -> float:
	return lifetime


func _process(delta: float) -> void:
	_t += delta / maxf(lifetime, 0.001)
	if _t >= 1.0:
		_t = 1.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _t < 0.0 or _tint.a <= 0.0:
		return
	var k := clampf(_t, 0.0, 1.0)
	var s := scale_curve.sample(k) if scale_curve != null else 1.0
	var a := alpha_curve.sample(k) if alpha_curve != null else 1.0 - k
	var col := ArrowPart.lit(_tint, tier)
	col.a = a
	if texture == null:
		draw_arc(Vector2.ZERO, size * s, 0.0, TAU, 32, col, ring_width, true)
		return
	var tex_size := texture.get_size()
	var fit := size * s / maxf(tex_size.x, tex_size.y)
	var extent := tex_size * fit
	draw_texture_rect(texture, Rect2(-extent * 0.5, extent), false, col)
