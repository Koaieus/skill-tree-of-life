@tool
extends Node2D

## Legibility backdrop for a SkillNode, since #16's cutover moved the real
## disk/rim/allocation render to NodeVisualsComposite:
##   • a faint always-on `fill_color` wash, so the node's footprint reads
##     even fully unallocated (NodeVisualsComposite's InnerDisk is hidden
##     when unallocated — see .claude/rules/skill-node-visuals.md).
##   • the sensed-fog outline (`sensed`), tinted by `border_color` — kept
##     deliberately separate from `fill_color` (owner colour when allocated):
##     a sensed-but-not-visible node must read archetype only, never leak
##     who owns it.
##   • `flash_amount` — 0..1 hit-flash channel. Lerps the wash toward red so
##     the per-node modulate stays free for other effects.

const FILL_ALPHA_UNALLOCATED: float = 0.2
const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3)
# Sensed-only outline: thinner than the live border and partially transparent,
# so the node reads as "I know it's there, can't see detail" against the fog.
const SENSED_OUTLINE_WIDTH: float = 1.5
# Low floor: sensed nodes z-promote above the fog overlay, so this alpha is
# what they render at regardless of local darkness. Keep it below what a
# barely-visible (fade-zone) node would render at, so a node transitioning
# from sensed → visible-but-faded doesn't appear to JUMP darker.
const SENSED_OUTLINE_ALPHA: float = 0.30

var _radius: float = 32.0
var fill_color: Color = Color.DIM_GRAY:
	set(value):
		fill_color = value
		queue_redraw()
## Base-type identity (persistent, set once by procgen) — used ONLY for the
## sensed outline now that the allocated border ring moved to
## NodeVisualsComposite's RimRing.
var border_color: Color = Color.DIM_GRAY:
	set(value):
		border_color = value
		queue_redraw()
## Sensed-but-not-visible flag. When true (and the node isn't visible, which
## the renderer can't know directly — VisionSystem only sets this on
## sensed-and-not-visible nodes), draw a faint base-type-tinted outline so
## the player reads its archetype without owner/modifier info leaking.
var sensed: bool = false:
	set(value):
		sensed = value
		queue_redraw()
var flash_amount: float = 0.0:
	set(value):
		flash_amount = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	if sensed:
		# Sensed-only: a single faint base-type-tinted ring, no wash — owner
		# colour and modifier content stay hidden.
		var outline := Color(border_color.r, border_color.g, border_color.b, SENSED_OUTLINE_ALPHA)
		# Straddles the boundary: inner_offset = -width/2 → centerline at radius.
		var sensed_c := SkillNode.ring_centerline(_radius, -SENSED_OUTLINE_WIDTH / 2.0, SENSED_OUTLINE_WIDTH)
		draw_circle(Vector2.ZERO, sensed_c, outline, false, SENSED_OUTLINE_WIDTH, true)
		return
	var fc := fill_color.lerp(FLASH_COLOR, flash_amount)
	# Faint full-radius wash always present so the disc shape stays legible
	# even when nothing owns the node (or NodeVisualsComposite's InnerDisk is
	# hidden pending allocation).
	var wash := Color(fc.r, fc.g, fc.b, FILL_ALPHA_UNALLOCATED)
	draw_circle(Vector2.ZERO, _radius, wash, true)
