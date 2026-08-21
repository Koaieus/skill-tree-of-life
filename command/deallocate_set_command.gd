class_name DeallocateSetCommand
extends Command

## "Give all of these back, at once." One command, never N — splitting a mass
## action would let a peer observe an intermediate state that never legally
## existed (`docs/domain/multiplayer-sync-model.md`). Applies through
## [method AllocationSystem.deallocate_set], which gates the set as a whole.
##
## A SET, not a path: order carries no meaning here, unlike
## [MassAllocateCommand].

const TAG: StringName = &"deallocate_set"

## The nodes to release, as [member SkillNode.stable_id]s.
var node_ids: Array[int] = []


func _init(entity_id_: int = 0, node_ids_: Array[int] = []) -> void:
	super(entity_id_)
	node_ids = node_ids_


func type_tag() -> StringName:
	return TAG


func to_dict() -> Dictionary:
	var d := super()
	d["node_ids"] = node_ids.duplicate()
	return d


static func from_dict(d: Dictionary) -> DeallocateSetCommand:
	var ids: Array[int] = []
	ids.assign(d.get("node_ids", []))
	return DeallocateSetCommand.new(int(d.get("entity_id", 0)), ids)
