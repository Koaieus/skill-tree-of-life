class_name DeallocateCommand
extends NodeCommand

## "Give this node back." Applies through
## [method AllocationSystem.deallocate], which is where the cut-vertex /
## islanding gate lives.

const TAG: StringName = &"deallocate"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> DeallocateCommand:
	return DeallocateCommand.new(int(d.get("entity_id", 0)), int(d.get("node_id", 0)))
