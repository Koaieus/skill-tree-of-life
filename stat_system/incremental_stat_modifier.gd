extends FloatStatModifier
class_name IncrementalStatModifier

func apply(value: float, stat: NumberStat):
	stat._multiplier += value
	return value
