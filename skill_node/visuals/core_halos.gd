@tool
extends SkillNodeRingVisual
## Core presence halos (#128): concentric halo marks scaled for "this is a
## nucleus" presence. Spikes are explicitly excluded — that mark is
## reserved for the addons system (fortify/plates), not core identity.

enum CoreStyle { NONE, RINGS, ORBIT, GIMBAL, COG }

## The entity/owner's color — core presence marks "this is your nucleus", so
## it tracks the allocating entity's tint rather than a private fixed hue.
## The composer syncs this to entity_tint; a standalone preview keeps the
## default.
@export var halo_color: Color = Color(0.85, 0.9, 1.0, 0.8):
	set(value):
		halo_color = value
		queue_redraw()

@export var core: CoreStyle = CoreStyle.NONE:
	set(value):
		core = value
		set_process(core != CoreStyle.NONE)
		queue_redraw()

## Scales the halo radius outward from the rim.
@export_range(1.0, 2.0, 0.01) var halo_scale: float = 1.3:
	set(value):
		halo_scale = value
		queue_redraw()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0

var _t: float = 0.0


func _ready() -> void:
	set_process(core != CoreStyle.NONE)


func _process(delta: float) -> void:
	_t += delta * spin_speed
	queue_redraw()


func _draw() -> void:
	if core == CoreStyle.NONE:
		return
	var base_r := radius * halo_scale
	match core:
		CoreStyle.RINGS:
			_draw_rings(base_r)
		CoreStyle.ORBIT:
			_draw_orbit(base_r)
		CoreStyle.GIMBAL:
			_draw_gimbal(base_r)
		CoreStyle.COG:
			_draw_cog(base_r)


func _draw_rings(base_r: float) -> void:
	for i in 3:
		var r := base_r * (1.0 + i * 0.18)
		var rate := 1.0 + i * 0.5
		_draw_dashed_circle(r, _t * rate, 10, halo_color)


func _draw_orbit(base_r: float) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var dot_count := 4
	for i in dot_count:
		var theta := _t + (TAU / dot_count) * i
		#var r := base_r * (1.0 + 0.1 * sin(_t * 0.7 + i))
		var r = base_r
		var halo_col_no_alpha = halo_color
		halo_col_no_alpha.a = 1.0
		draw_circle(polar_point(r, theta), 2.5, halo_col_no_alpha)


## 3 ring-arcs tilted ~45 degrees apart, each spinning at its own rate.
# TODO: this is not at all what they should look like wtf
func _draw_gimbal(base_r: float) -> void:
	for i in 3:
		var tilt := i * PI / 4.0
		var rate := 0.6 + i * 0.3
		var theta_start := _t * rate + tilt
		draw_arc(Vector2.ZERO, base_r * (1.0 + i * 0.05), theta_start, theta_start + PI * 1.4, 24, halo_color, 1.5, true)


func _draw_cog(base_r: float) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var teeth := 10
	var tooth_len := base_r * 0.12
	for i in teeth:
		var theta := _t * 0.3 + (TAU / teeth) * i
		draw_line(polar_point(base_r, theta), polar_point(base_r + tooth_len, theta), halo_color, 2.0, true)


func _draw_dashed_circle(r: float, offset: float, dash_count: int, color: Color) -> void:
	var step := TAU / dash_count
	for i in dash_count:
		var a0 := i * step + offset
		draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, color, 1.5, true)
