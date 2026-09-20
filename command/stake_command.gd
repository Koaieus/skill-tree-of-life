class_name StakeCommand
extends NodeCommand

## "Stake this node."

const TAG: StringName = &"stake"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> StakeCommand:
	return WireFields.from_dict(StakeCommand, d)
