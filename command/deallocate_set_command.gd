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


## The wire form, declared once (#1000); see [WireFields].
static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"node_ids", TYPE_ARRAY).of(TYPE_INT))
	return fields


static func from_dict(d: Dictionary) -> DeallocateSetCommand:
	return WireFields.from_dict(DeallocateSetCommand, d)
