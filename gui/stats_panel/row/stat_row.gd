extends StatRowBase
class_name StatRow

@onready var label_value: Label = $LabelValue

@export var value_display: String:
	get(): return value_display
	set(value):
		if value_display != value:
			value_display = value
			if label_value:
				label_value.text = value_display


## Get the display value from currently held stat
func _get_display_value_from_stat() -> String:
	return stat.display_value()

func compute() -> void:
	value_display = _get_display_value_from_stat()
