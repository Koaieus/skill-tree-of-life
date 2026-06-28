@tool
extends Node2D

## Hover feedback as a soft radial GLOW (#73), not a hard stroke. Hover is its
## own visual register — "the pointer is on this node" — so it layers cleanly
## UNDER the crisp role/selection rings (NodeHighlightOverlay), which carry
## mechanical meaning (ORIGIN / TARGET / IN_RANGE / reachable). Two registers,
## two meanings, no clash — and hover composes with ANY role instead of needing
## a merged state per combination. See `.claude/rules/skill-node-visuals.md`.
##
## The glow shape lives in a shared [GlowStyle] resource (one `@export`, not a
## setter per knob): editing the style in the inspector auto-emits `changed`,
## which we rebind to rebuild the halo texture live.

@export var style: GlowStyle:
	set(value):
		if style == value:
			return
		if style != null and style.changed.is_connected(_rebuild_texture):
			style.changed.disconnect(_rebuild_texture)
		style = value
		if style != null and not style.changed.is_connected(_rebuild_texture):
			style.changed.connect(_rebuild_texture)
		_rebuild_texture()

var _radius: float = 32.0
var _texture: GradientTexture2D


func _ready() -> void:
	_rebuild_texture()


func configure(r: float) -> void:
	if is_equal_approx(_radius, r):
		return
	_radius = r
	_rebuild_texture()


# Radial halo authored as a Gradient sampled center→edge, built as a GPU texture
# so the falloff is smooth (no concentric-circle banding). White-keyed so the
# style's `color` tints it via draw_texture_rect's modulate. The three control
# radii map to gradient offsets against `outer_total` (the px distance where
# offset == 1).
func _rebuild_texture() -> void:
	if style == null:
		_texture = null
		queue_redraw()
		return
	var outer_total := _radius + style.outset
	if outer_total <= 0.0:
		_texture = null
		queue_redraw()
		return
	var peak_r := minf(_radius + style.peak_outset, outer_total)
	var inner_r := clampf(peak_r - style.inner_feather, 0.0, peak_r)
	var inner_off := inner_r / outer_total
	var peak_off := clampf(peak_r / outer_total, inner_off, 0.999)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, inner_off, peak_off, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)  # center
	tex.fill_to = Vector2(1.0, 0.5)    # offset 1.0 lands at `outer_total` px from center
	tex.gradient = grad
	var size := int(ceil(outer_total * 2.0))
	tex.width = size
	tex.height = size
	_texture = tex
	queue_redraw()


func _draw() -> void:
	if _texture == null or style == null:
		return
	var outer_total := _radius + style.outset
	draw_texture_rect(_texture, Rect2(-outer_total, -outer_total, outer_total * 2.0, outer_total * 2.0), false, style.color)
