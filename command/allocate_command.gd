class_name AllocateCommand
extends NodeCommand

## "Spend a point on this node." Applies through
## [method AllocationSystem.allocate] — the gated entry point, not the
## `force_allocate` primitive.

const TAG: StringName = &"allocate"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> AllocateCommand:
	return AllocateCommand.new(int(d.get("entity_id", 0)), int(d.get("node_id", 0)))
