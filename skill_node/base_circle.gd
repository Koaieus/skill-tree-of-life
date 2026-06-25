@tool
extends Node2D

## Two-channel disc visual:
##   • `border_color` — base-type identity (set once by procgen, persistent).
##   • `fill_color`   — owner / allocation status (white-ish when unallocated,
##                       owner colour when allocated). Driven by SkillNode.
##   • `flash_amount` — 0..1 hit-flash channel. Lerps fill toward red so the
##                       per-node modulate stays free for other effects.

const BORDER_WIDTH: float = 8.0
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
var border_color: Color = Color.DIM_GRAY:
	set(value):
		border_color = value
		queue_redraw()
var fill_color: Color = Color.DIM_GRAY:
	set(value):
		fill_color = value
		queue_redraw()
## Toggled by SkillNode based on owner state. Drives the bright inner disk
## that signals ownership at a glance — same shape the core marker used to
## render, just promoted here so every allocated node gets it (the star
## label on CoreMarker stays the core-only flag).
var allocated: bool = false:
	set(value):
		allocated = value
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

## Set by SkillNode._sync_visuals — BaseCircle has no inset policy of its
## own; the owning SkillNode is the authority.
var inner_radius: float = 24.0:
	set(value):
		inner_radius = value
		queue_redraw()

## Back-compat one-shot used by SkillNode._sync_visuals when border + fill
## should match (i.e. the legacy single-colour mode — fill alpha kicks in
## as before). Procgen calls `border_color =` directly to override later.
func configure(r: float, color: Color) -> void:
	_radius = r
	border_color = color
	fill_color = color


func _draw() -> void:
	if sensed:
		# Sensed-only: a single faint base-type-tinted ring, no wash, no
		# inner disk — owner colour and modifier content stay hidden.
		var outline := Color(border_color.r, border_color.g, border_color.b, SENSED_OUTLINE_ALPHA)
		draw_circle(Vector2.ZERO, _radius, outline, false, SENSED_OUTLINE_WIDTH, true)
		return
	var fc := fill_color.lerp(FLASH_COLOR, flash_amount)
	var bc := border_color.lerp(FLASH_COLOR, flash_amount)
	# Faint full-radius wash always present so the disc shape stays legible
	# even when nothing owns the node.
	var wash := Color(fc.r, fc.g, fc.b, FILL_ALPHA_UNALLOCATED)
	draw_circle(Vector2.ZERO, _radius, wash, true)
	if allocated:
		# Bright inner disk = "owned." Inset matches the legacy CoreMarker
		# render so core nodes look identical to before; the star label is
		# what now distinguishes core from non-core.
		draw_circle(Vector2.ZERO, inner_radius, fc, true)
	draw_circle(Vector2.ZERO, _radius - BORDER_WIDTH/2, bc, false, BORDER_WIDTH, true)
