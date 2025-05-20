@tool
extends IntGrowablePoolStat
class_name ExpStat


static func name():
	return "Experience"

static func abbreviation():
	return "EXP"
	
static func description():
	return "muh experience"

func grow():
	var new_value := int(_max.value * 1.25 + 10)
	print('growing: %s → %s' % [_max.base_value, new_value])
	_max.base_value = new_value

func _generate_row() -> StatRow:
	#print('generating row with level %s, min/cur/max: %s/%s/%s' % [level, _min.value, value, _max.value])
	var row: StatRow = STAT_ROW.instantiate()
	row.stat = self
	row.text_display = name()
	row.value_display = "Lv. %s" % [level]
	row.get_node('LabelValue').hide()
	#var progressBar: DecoratedProgressBar = row.progress_bar
	var progressBar: DecoratedProgressBar = row.get_node('%ProgressBar')
	var innerProgressBar: ProgressBar = row.get_node('%ProgressBar/%ProgressBar')

	if progressBar and innerProgressBar:
		#var bar: ProgressBar = progressBar._bar
		innerProgressBar.value = value
		if _min:
			innerProgressBar.min_value = _min.value
		if _max:
			innerProgressBar.max_value = _max.value
		progressBar.show()
	return row
