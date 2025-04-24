extends StatModifier
class_name ComputedStatModifier

func apply(_value, _stat):
	push_error('Cannot call `apply` on Abstract ComputedStatModifier instance')
	return null
