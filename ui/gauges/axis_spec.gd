@tool
class_name AxisSpec
extends Resource
## One radar axis: its short label + plot color. Replaces the parallel
## axis_labels/axis_colors arrays [AttributeRadar] used to carry (#241);
## plotted values stay separate (they're runtime state, not spec).

@export var label: String = ""
@export var color: Color = Color.WHITE


func _init(p_label: String = "", p_color: Color = Color.WHITE) -> void:
	label = p_label
	color = p_color
