extends NumberStatModifier
class_name IncrementalStatModifier

@export_custom(PROPERTY_HINT_NONE, 'suffix:%') var operation_value: int:
	get():
		return operation_value
	set(new_value):
		operation_value = new_value
		#compute()

func get_operation_value() -> float:
	return operation_value / 100.

func apply(value, stat: IntStat):
	#print("Applying modifier of value x%s (%s) to %s of %s, %s time(s) [%s]" % [
		#_operation_value, 
		#operation_value, 
		#value, 
		#stat.name, 
		#apply_count,
		#operation
	#])
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
	#print('modifier is now: %s' % stat._multiplier)
	return value

func as_string() -> String:
	var stat_name = stat_meta.name
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
