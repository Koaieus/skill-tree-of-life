@tool
extends Node2D

## Two-channel disc visual:
##   • `border_color` — base-type identity (set once by procgen, persistent).
##   • `fill_color`   — owner / allocation status (white-ish when unallocated,
##                       owner colour when allocated). Driven by SkillNode.
##   • `flash_amount` — 0..1 hit-flash channel. Lerps fill toward red so the
##                       per-node modulate stays free for other effects.

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.2
const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3)

var _radius: float = 32.0
var border_color: Color = Color.DIM_GRAY:
	set(value):
		border_color = value
		queue_redraw()
var fill_color: Color = Color.DIM_GRAY:
	set(value):
		fill_color = value
		queue_redraw()
var flash_amount: float = 0.0:
	set(value):
		flash_amount = clampf(value, 0.0, 1.0)
		queue_redraw()


## Back-compat one-shot used by SkillNode._sync_visuals when border + fill
## should match (i.e. the legacy single-colour mode — fill alpha kicks in
## as before). Procgen calls `border_color =` directly to override later.
func configure(r: float, color: Color) -> void:
	_radius = r
	border_color = color
	fill_color = color


func _draw() -> void:
	var fc := fill_color.lerp(FLASH_COLOR, flash_amount)
	var bc := border_color.lerp(FLASH_COLOR, flash_amount)
	var fill := Color(fc.r, fc.g, fc.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, _radius, fill, true)
	draw_circle(Vector2.ZERO, _radius, bc, false, BORDER_WIDTH, true)
