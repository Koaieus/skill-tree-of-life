extends StatRowBase
class_name StatRow

@onready var label_value: Label = $LabelValue

@export var value_display: String:
	get(): return value_display
	set(v):
		if value_display != v:
			if label_value:
				#label_value.set_text("%s" % v)
				label_value.text = "%s" % v
			value_display = v
			notify_property_list_changed()

func _ready() -> void:
	super()
	compute()
	#label_value.text = value_display


## Get the display value from currently held stat
func _get_display_value_from_stat() -> String:
	return stat.display_value()

func compute() -> void:
	if not stat:
		return
	value_display = _get_display_value_from_stat()
