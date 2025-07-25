@tool
extends IntGrowablePoolStat
class_name ExpStat

const STAT_ROW_BAR = preload("res://ui/stats_panel/row/stat_row_bar.tscn")


func grow():
	var new_value := int(_max.value * 1.25 + 10)
	print('growing: %s → %s' % [_max.base_value, new_value])
	_max.base_value = new_value

func _get_stat_row_resource():
	return STAT_ROW_BAR
	
func notify_value_changed() -> void:
	print("[%s]: Values before emit: current: %s | level: %s" % [name, _value, level])
	super()

#func _generate_row(manager: StatsManager) -> StatRow:
	##print('generating row with level %s, min/cur/max: %s/%s/%s' % [level, _min.value, value, _max.value])
	#var row: StatRow = STAT_ROW.instantiate()
	#row.stat_manager = manager
	#row.stat_key = get_key()
	#row.text_display = name
	#row.value_display = "Lv. %s" % [level]
	#row.get_node('LabelValue').hide()
	##var progressBar: DecoratedProgressBar = row.progress_bar
	#var progressBar: DecoratedProgressBar = row.get_node('%ProgressBar')
	#var innerProgressBar: ProgressBar = row.get_node('%ProgressBar/%ProgressBar')
#
	#if progressBar and innerProgressBar:
		##var bar: ProgressBar = progressBar._bar
		#innerProgressBar.value = value
		#if _min:
			#innerProgressBar.min_value = _min.value
		#if _max:
			#innerProgressBar.max_value = _max.value
		#progressBar.show()
	#return row
