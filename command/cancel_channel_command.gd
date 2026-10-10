class_name CancelChannelCommand
extends NodeCommand

## "Cancel the staking channel on this node."

const TAG: StringName = &"cancel_channel"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> CancelChannelCommand:
	return WireFields.from_dict(CancelChannelCommand, d)
