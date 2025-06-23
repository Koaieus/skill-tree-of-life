extends StatRowBase
class_name StatRowBar

@onready var label_value: Label = $LabelValue
@onready var progress_bar: DecoratedProgressBar = %ProgressBar

func compute() -> void:
	if not is_node_ready():
		return
	if "level" in stat:
		label_value.text = "Lv. %s" % stat.level
	else:
		label_value.text = ""
		
	if stat is PoolStat:
		progress_bar._bar.value = stat.value
		progress_bar._bar.max_value = stat._max.value
