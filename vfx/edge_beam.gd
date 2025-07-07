extends Line2D
class_name EdgeBeam

@export var travel_time: float = 4.0
var path_points : PackedVector2Array
var offset: float = 0.
@onready var orig_curve = width_curve

signal completed


func _process(delta: float) -> void:
	width_curve = make_offset_curve(orig_curve, offset)

func start(path: PackedVector2Array):
	path_points = path.duplicate()
	points = path_points  # draw the full line
	texture_mode = LINE_TEXTURE_STRETCH
	gradient = gradient  # assign your custom Gradient
	width_curve = width_curve  # assign your custom Curve

	# Animate the “draw” offset from 0→1
	var tween = create_tween()
	
	#tween.tween_property(self, "gradient_offset", 1.0, travel_time) \
		 #.from(0) \
		 #.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "offset", 1.0, travel_time) \
		 .from(0) \
		 .set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_complete)
	

func _on_complete() -> void:
	print('[VFX] done beamin!')
	texture_mode = Line2D.LINE_TEXTURE_NONE
	completed.emit()
	queue_free()

func make_offset_curve(orig: Curve, offset: float) -> Curve:
	var c = Curve.new()
	for i in range(orig.get_point_count()):
		var point = Vector2(orig.get_point_position(i))
		# wrap or clamp x between 0 and 1 as needed
		point.x = fmod(point.x + offset, 1.0)
		c.add_point(point)
	return c
