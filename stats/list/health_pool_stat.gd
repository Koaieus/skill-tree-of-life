extends IntPoolStat
class_name HealthPoolStat


const STAT_ROW_BAR = preload("res://ui/stats_panel/row/stat_row_bar.tscn")


func _get_stat_row_resource():
	return STAT_ROW_BAR
