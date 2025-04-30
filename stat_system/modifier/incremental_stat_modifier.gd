extends NumberStatModifier
class_name IncrementalStatModifier

@export_custom(PROPERTY_HINT_NONE, 'suffix:%') var operation_value: int = 0

func get_operation_value() -> float:
	return operation_value / 100.

func apply(value: float, stat: NumberStat):
	match operation:
		Operation.ADD:
			stat._multiplier += _operation_value * apply_count
		Operation.SUBSTRACT:
			stat._multiplier -= _operation_value * apply_count
		Operation.MULTIPLY:
			stat._multiplier *= _operation_value * apply_count
		Operation.DIVIDE:
			if _operation_value == 0:
				push_error("NumberStatModifier cannot divide by 0")
				return value
			stat._multiplier /= _operation_value * apply_count
	return value

func as_string() -> String:
	var stat_name = get_stat_name()
	match operation:
		Operation.ADD:
			return "+{0}% {1}".format([operation_value, stat_name])
		Operation.SUBSTRACT:
			return "-{0}% {1}".format([operation_value, stat_name])
		Operation.MULTIPLY:
			return "{0}% More {1}".format([operation_value, stat_name])
		Operation.DIVIDE:
			return "{0}% Less {1}".format([1. - operation_value, stat_name])
	return super()		
