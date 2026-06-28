@tool
extends Node2D

## Hover feedback as a soft radial GLOW (#73), not a hard stroke. Hover is its
## own visual register — "the pointer is on this node" — so it layers cleanly
## UNDER the crisp role/selection rings (NodeHighlightOverlay), which carry
## mechanical meaning (ORIGIN / TARGET / IN_RANGE / reachable). Two registers,
## two meanings, no clash — and hover composes with ANY role instead of needing
## a merged state per combination. See `.claude/rules/skill-node-visuals.md`.
##
## The glow is a radial alpha profile defined by three radii from the node
## center, all authored RELATIVE to the node boundary (`radius`) so they track
## node size: inner fade-in → peak → outer fade-out. Defaults put the inner edge
## right at the boundary ("feather at the rim") so the colored archetype ring
## (which ends at `radius`) keeps its pure type colour.
##
## All knobs are @export + live: tweak them on the HoverRing node in the editor
## (set `visible = true` on it first) and the texture rebuilds on every change.

## Glow tint. The alpha channel scales overall brightness — drop it for a
## subtler glow. Driven from the scene.
@export var color: Color = Color.YELLOW_GREEN:
	set(value):
		color = value
		queue_redraw()

@export_group("Glow shape")
## Outer reach: the glow has fully faded to 0 this many px past the node
## boundary (`radius`).
@export var glow_outset: float = 14.0:
	set(value):
		glow_outset = value
		_rebuild_texture()
## Where the glow is brightest, in px past the node boundary. A small positive
## value puts the peak just outside the rim — a halo that hugs the node without
## eating into the colored ring.
@export var glow_peak_outset: float = 2.0:
	set(value):
		glow_peak_outset = value
		_rebuild_texture()
## How far INSIDE the peak the glow fades in (px). Larger = softer inner edge
## that bleeds further toward the node center (and starts tinting the archetype
## ring). Default keeps the inner edge at the boundary.
@export var glow_inner_feather: float = 2.0:
	set(value):
		glow_inner_feather = value
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
# so the falloff is smooth (no concentric-circle banding). White-keyed so
# `color` tints it via draw_texture_rect's modulate. The three control radii map
# to gradient offsets against `outer_total` (the px distance where offset == 1).
func _rebuild_texture() -> void:
	var outer_total := _radius + glow_outset
	if outer_total <= 0.0:
		_texture = null
		queue_redraw()
		return
	var peak_r := minf(_radius + glow_peak_outset, outer_total)
	var inner_r := clampf(peak_r - glow_inner_feather, 0.0, peak_r)
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
	if _texture == null:
		return
	var outer_total := _radius + glow_outset
	draw_texture_rect(_texture, Rect2(-outer_total, -outer_total, outer_total * 2.0, outer_total * 2.0), false, color)
