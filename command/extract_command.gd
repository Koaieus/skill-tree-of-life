class_name ExtractCommand
extends NodeCommand

## "Extract from this node."

const TAG: StringName = &"extract"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> ExtractCommand:
	return ExtractCommand.new(int(d.get("entity_id", 0)), int(d.get("node_id", 0)))
