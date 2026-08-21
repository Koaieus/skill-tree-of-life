class_name StakeCommand
extends NodeCommand

## "Stake this node."

const TAG: StringName = &"stake"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> StakeCommand:
	return StakeCommand.new(int(d.get("entity_id", 0)), int(d.get("node_id", 0)))
