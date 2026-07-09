@tool
extends SkillNodeVisual
## Core presence halos (#128): concentric halo marks scaled for "this is a
## nucleus" presence. Spikes are explicitly excluded — that mark is
## reserved for the addons system (fortify/plates), not core identity.
##
## Reads [member SkillNodeVisual.entity_tint]: a core marks "this is YOUR
## nucleus", so it carries ownership, not archetype. Only the halo's own
## translucency is private ([member halo_opacity]).

enum CoreStyle { NONE, RINGS, ORBIT, GIMBAL, COG }

## Alpha the halo marks are drawn at — the halo's own material property, kept
## private so the identity color it reads stays a plain opaque tint.
@export_range(0.0, 1.0, 0.01) var halo_opacity: float = 0.8:
	set(value):
		halo_opacity = value
		queue_redraw()

var _halo_color: Color:
	get():
		var c := entity_tint
		c.a = halo_opacity
		return c

@export var core: CoreStyle = CoreStyle.NONE:
	set(value):
		core = value
		set_animating(core != CoreStyle.NONE)
		queue_redraw()

## Scales the halo radius outward from the rim.
@export_range(1.0, 2.0, 0.01) var halo_scale: float = 1.3:
	set(value):
		halo_scale = value
		queue_redraw()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0


## Shared clock, scaled at read time so a spin_speed tweak never jumps the phase.
func _spin() -> float:
	return anim_time * spin_speed


func _draw() -> void:
	if core == CoreStyle.NONE:
		return
	var halo_color := _halo_color
	var base_r := radius * halo_scale
	match core:
		CoreStyle.RINGS:
			_draw_rings(base_r, halo_color)
		CoreStyle.ORBIT:
			_draw_orbit(base_r, halo_color)
		CoreStyle.GIMBAL:
			_draw_gimbal(base_r, halo_color)
		CoreStyle.COG:
			_draw_cog(base_r, halo_color)


func _draw_rings(base_r: float, halo_color: Color) -> void:
	for i in 3:
		var r := base_r * (1.0 + i * 0.18)
		var rate := 1.0 + i * 0.5
		_draw_dashed_circle(r, _spin() * rate, 10, halo_color)


func _draw_orbit(base_r: float, halo_color: Color) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	# The orbiting dots read as solid beads on a translucent track.
	var dot_color := Color(halo_color, 1.0)
	var dot_count := 4
	for i in dot_count:
		var theta := _spin() + (TAU / dot_count) * i
		draw_circle(polar_point(base_r, theta), 2.5, dot_color)


## 3 ring-arcs tilted ~45 degrees apart, each spinning at its own rate.
# TODO: this is not at all what they should look like wtf
func _draw_gimbal(base_r: float, halo_color: Color) -> void:
	for i in 3:
		var tilt := i * PI / 4.0
		var rate := 0.6 + i * 0.3
		var theta_start := _spin() * rate + tilt
		draw_arc(Vector2.ZERO, base_r * (1.0 + i * 0.05), theta_start, theta_start + PI * 1.4, 24, halo_color, 1.5, true)


func _draw_cog(base_r: float, halo_color: Color) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var teeth := 10
	var tooth_len := base_r * 0.12
	for i in teeth:
		var theta := _spin() * 0.3 + (TAU / teeth) * i
		draw_line(polar_point(base_r, theta), polar_point(base_r + tooth_len, theta), halo_color, 2.0, true)


func _draw_dashed_circle(r: float, offset: float, dash_count: int, color: Color) -> void:
	var step := TAU / dash_count
	for i in dash_count:
		var a0 := i * step + offset
		draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, color, 1.5, true)
