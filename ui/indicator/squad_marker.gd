@tool
class_name SquadMarker
extends Indicator

## The ranged firing-squad marker: a band ring plus a fan of chevrons that aim
## along [member Indicator.facing] — outward from the leaf while ranged mode
## is armed, at the target once the leaf will fire. [member Indicator.charge]
## 0 (no shots left) keeps the same geometry but mutes it: [member spent_tint]
## at the INERT tier, hollow chevrons.
##
## The chevrons turn over [member aim_turn_seconds] (presentation only); the
## first facing a marker receives snaps. %Chevrons is a plain Node2D this
## script draws into through its [signal CanvasItem.draw] signal, so its
## rotation IS the aim.

## Gap from the wrapped boundary to the ring's INNER edge; matches the reticle.
@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
@export var chevron_count: int = 3:
	set(value):
		chevron_count = value
		_apply_geometry()
## Total arc the chevron fan spans, centred on the facing.
@export_range(0.0, 360.0, 1.0) var chevron_spread_deg: float = 50.0:
	set(value):
		chevron_spread_deg = value
		_apply_geometry()
## Length and width of one chevron (world px); it sits just outside the ring.
@export var chevron_size: float = 7.0:
	set(value):
		chevron_size = value
		_apply_geometry()
## Seconds the chevrons take to swing to a new facing; 0 = instant.
@export_range(0.0, 2.0, 0.01) var aim_turn_seconds: float = 0.15
## The whole marker's colour once spent (charge 0), drawn at the INERT tier.
@export var spent_tint: Color = Color(0.55, 0.58, 0.6, 0.7):
	set(value):
		spent_tint = value
		_update_modulate()

## No shots left: the muted look.
var spent: bool:
	get:
		return charge <= 0.0

var _aimed := false
var _last_facing := Vector2.ZERO
var _aim_from := 0.0
var _aim_to := 0.0
var _aim_elapsed := 0.0


func _ready() -> void:
	var chevrons := get_node_or_null(^"%Chevrons") as Node2D
	if chevrons != null and not chevrons.draw.is_connected(_draw_chevrons):
		chevrons.draw.connect(_draw_chevrons)
	super()


func _process(delta: float) -> void:
	super(delta)
	if _aim_elapsed >= aim_turn_seconds:
		return
	_aim_elapsed = minf(_aim_elapsed + delta, aim_turn_seconds)
	var t := _aim_elapsed / aim_turn_seconds
	_set_aim(lerp_angle(_aim_from, _aim_to, smoothstep(0.0, 1.0, t)))


func _update_modulate() -> void:
	if spent:
		modulate = Emissive.at(spent_tint, Emissive.stops(Emissive.Tier.INERT))
	else:
		super()


func _apply_geometry() -> void:
	_update_modulate()
	_retarget()
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		var w := stroke(ring_width)
		ring.width = w
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, w)
	var chevrons := get_node_or_null(^"%Chevrons") as Node2D
	if chevrons != null:
		chevrons.visible = facing != Vector2.ZERO
		chevrons.queue_redraw()


# Starts a swing (or snaps) when the facing changed since the last call.
func _retarget() -> void:
	if facing == _last_facing:
		return
	_last_facing = facing
	if facing == Vector2.ZERO:
		return
	var angle := facing.angle()
	var chevrons := get_node_or_null(^"%Chevrons") as Node2D
	if not _aimed or aim_turn_seconds <= 0.0 or chevrons == null:
		_aim_from = angle
		_aim_elapsed = aim_turn_seconds
		_set_aim(angle)
	else:
		_aim_from = chevrons.rotation
		_aim_elapsed = 0.0
	_aim_to = angle
	_aimed = true


func _set_aim(angle: float) -> void:
	var chevrons := get_node_or_null(^"%Chevrons") as Node2D
	if chevrons != null:
		chevrons.rotation = angle


func _draw_chevrons() -> void:
	var chevrons := get_node_or_null(^"%Chevrons") as Node2D
	if chevrons == null or chevron_count <= 0 or chevron_size <= 0.0:
		return
	var w := stroke(ring_width)
	var ring_outer := SkillNode.ring_centerline(radius, ring_inner_offset, w) + w * 0.5
	var mid := ring_outer + chevron_size * 0.6
	var half := chevron_size * 0.5
	var spread := deg_to_rad(chevron_spread_deg)
	for i in chevron_count:
		var offset := 0.0
		if chevron_count > 1:
			offset = spread * (float(i) / float(chevron_count - 1) - 0.5)
		var d := Vector2.from_angle(offset)
		var side := d.orthogonal() * half
		var tip := d * (mid + half)
		var back := d * (mid - half)
		var notch := d * (mid - half * 0.3)
		var points := PackedVector2Array([tip, back + side, notch, back - side])
		if spent:
			points.append(tip)
			chevrons.draw_polyline(points, Color.WHITE, stroke(ring_width * 0.4), true)
		else:
			chevrons.draw_colored_polygon(points, Color.WHITE)
