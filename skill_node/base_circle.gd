@tool
extends Node2D

## Legibility backdrop for a SkillNode, since #16's cutover moved the real
## disk/rim/allocation render to NodeVisualsComposite:
##   • a faint always-on `fill_color` wash, so the node's footprint reads
##     even fully unallocated (NodeVisualsComposite's InnerDisk is hidden
##     when unallocated — see .claude/rules/skill-node-visuals.md).
##   • `flash_amount` — 0..1 hit-flash channel. Lerps the wash toward red so
##     the per-node modulate stays free for other effects.
##
## The sensed-fog outline used to live here too; it moved onto the composite's
## [SensedOutline] component (#141), and SkillNode now hides BaseCircle entirely
## when sensed (its wash carries the owner colour, which must not leak).

const FILL_ALPHA_UNALLOCATED: float = 0.2
const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3)

var _radius: float = 32.0
var fill_color: Color = Color.DIM_GRAY:
	set(value):
		fill_color = value
		queue_redraw()
var flash_amount: float = 0.0:
	set(value):
		flash_amount = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var fc := fill_color.lerp(FLASH_COLOR, flash_amount)
	# Faint full-radius wash always present so the disc shape stays legible
	# even when nothing owns the node (or NodeVisualsComposite's InnerDisk is
	# hidden pending allocation).
	var wash := Color(fc.r, fc.g, fc.b, FILL_ALPHA_UNALLOCATED)
	draw_circle(Vector2.ZERO, _radius, wash, true)
