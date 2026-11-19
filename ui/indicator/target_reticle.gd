@tool
class_name TargetReticle
extends Indicator

## The aim-point reticle: a static band ring plus a spinning crosshair outside
## it. Every offset is relative to [member Indicator.radius], so it grows with
## the wrapped node. The spin is its own — [member %Spinner]'s rotation advances
## in [method _process]; nothing outside redraws per frame.

## Gap from the wrapped boundary to the ring's INNER edge. Past 8 it clears
## the hover glow band (radius..+8).
@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
@export var arm_count: int = 4:
	set(value):
		arm_count = value
		_apply_geometry()
## Gap from the wrapped boundary to each arm's inner tip.
@export var arm_inner_offset: float = 15.0:
	set(value):
		arm_inner_offset = value
		_apply_geometry()
@export var arm_length: float = 8.0:
	set(value):
		arm_length = value
		_apply_geometry()
@export var arm_width: float = 3.0:
	set(value):
		arm_width = value
		_apply_geometry()
## 0 = static.
@export var spin_degrees_per_second: float = 45.0

@export_group("Overclock pip")
## Gap from the wrapped boundary to the pip's centre, up and to the right.
@export var pip_offset: float = 14.0:
	set(value):
		pip_offset = value
		_apply_geometry()
@export_range(6, 48, 1) var pip_font_size: int = 14:
	set(value):
		pip_font_size = value
		_apply_geometry()
## Multiplied by the role's tint (the inherited modulate).
@export var pip_color: Color = Color.WHITE:
	set(value):
		pip_color = value
		_apply_geometry()
## The loadout is above the node's cap: a pick here trims it.
@export var pip_red_color: Color = Color(1.0, 0.18, 0.15):
	set(value):
		pip_red_color = value
		_apply_geometry()
## Appended to the red pip's text, so "over the cap" survives a role tint that
## swallows the colour (a committed HOSTILE_TARGET is red itself).
@export var pip_red_suffix: String = "!":
	set(value):
		pip_red_suffix = value
		_apply_geometry()

@export_group("Muted look")
## 0 = the role's tint as-is, 1 = its luminance grey.
@export_range(0.0, 1.0, 0.01) var muted_desaturation: float = 0.7:
	set(value):
		muted_desaturation = value
		_update_modulate()
## Alpha factor on the muted reticle.
@export_range(0.0, 1.0, 0.01) var muted_alpha: float = 0.55:
	set(value):
		muted_alpha = value
		_update_modulate()
@export_group("")


func _process(delta: float) -> void:
	super(delta)
	if spin_degrees_per_second == 0.0:
		return
	var spinner := get_node_or_null(^"%Spinner") as Node2D
	if spinner != null:
		spinner.rotation = wrapf(spinner.rotation + deg_to_rad(spin_degrees_per_second) * delta, -PI, PI)


## A committed pick that trimmed the loadout: greyed and faded, drawn at the
## INERT tier — "not using your full spec" (ADR 0089 §4).
func _update_modulate() -> void:
	if not muted:
		super()
		return
	var grey := tint.get_luminance()
	var dull := tint.lerp(Color(grey, grey, grey, tint.a), muted_desaturation)
	dull.a *= muted_alpha
	modulate = Emissive.at(dull, Emissive.stops(Emissive.Tier.INERT))


func _apply_geometry() -> void:
	var pip_label := get_node_or_null(^"%Pip") as IndicatorPipLabel
	if pip_label != null:
		pip_label.text = ("+%d%s" % [pip, pip_red_suffix if pip_red else ""]) if pip > 0 else ""
		pip_label.color = pip_red_color if pip_red else pip_color
		pip_label.font_size = pip_font_size
		pip_label.position = Vector2.from_angle(-PI / 4.0) * (radius + pip_offset)
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		var w := stroke(ring_width)
		ring.width = w
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, w)
	var arms := get_node_or_null(^"%Spinner") as IndicatorCrosshairArms
	if arms != null:
		arms.arm_count = arm_count
		arms.inner_radius = radius + arm_inner_offset
		arms.arm_length = arm_length
		arms.arm_width = stroke(arm_width)
