class_name MassAllocateCommand
extends Command

## "Walk this path, allocating as far as I can afford." Carries the PATH ONLY.
##
## `AllocationSystem.mass_allocate(entity, path, affordable_count)` takes a
## count, but that count is computed client-side today
## (`systems/player_input_controller.gd:801`) from the sender's own reading of
## the board. Putting it on the wire would let a stale client dictate how much
## the host spends, so the applier recomputes it (#510). Order matters: the
## path is walked from the sender's territory outward.

const TAG: StringName = &"mass_allocate"

## The path to walk, in order, as [member SkillNode.stable_id]s.
var path_ids: Array[int] = []


func _init(entity_id_: int = 0, path_ids_: Array[int] = []) -> void:
	super(entity_id_)
	path_ids = path_ids_


func type_tag() -> StringName:
	return TAG


## The wire form, declared once (#1000); see [WireFields].
static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"path_ids", TYPE_ARRAY).of(TYPE_INT))
	return fields


static func from_dict(d: Dictionary) -> MassAllocateCommand:
	return WireFields.from_dict(MassAllocateCommand, d)
