extends ComputedStatModifier
class_name NumberStatModifier

enum Operation {
	ADD = 10,
	SUBSTRACT = 20,
	#INCREASE = 30,
	#DECREASE = 40,
	MULTIPLY = 50,
	DIVIDE = 60
}

@export var operation: Operation = Operation.ADD:
	get():
		return operation
	set(value):
		operation = value
		application_order = value

var _operation_value:
	get = get_operation_value

func get_operation_value():
	return 0

func apply(value, _stat):
	match operation:
		Operation.ADD:
			return value + (_operation_value * apply_count)
		Operation.SUBSTRACT:
			return value - (_operation_value * apply_count)
		Operation.MULTIPLY:
			return value * (_operation_value ** apply_count)
		Operation.DIVIDE:
			if _operation_value == 0:
				push_error("NumberStatModifier cannot divide by 0")
				return value			
			return value / (_operation_value * apply_count)
	return value


func as_string() -> String:
	var stat_name = stat_meta.name if stat_meta else 'uhh'
	match operation:
		Operation.ADD:
			return "+{0} {1}".format([_operation_value, stat_name])
		Operation.SUBSTRACT:
			return "-{0} {1}".format([_operation_value, stat_name])
		Operation.MULTIPLY:
			return "x{0} {1}".format([_operation_value, stat_name])
		Operation.DIVIDE:
			return "÷{0} {1}".format([_operation_value, stat_name])
	return super()
