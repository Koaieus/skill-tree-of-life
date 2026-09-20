class_name ExtractCommand
extends NodeCommand

## "Extract from this node."

const TAG: StringName = &"extract"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> ExtractCommand:
	return WireFields.from_dict(ExtractCommand, d)
