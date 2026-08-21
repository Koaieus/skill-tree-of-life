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


func to_dict() -> Dictionary:
	var d := super()
	d["path_ids"] = path_ids.duplicate()
	return d


static func from_dict(d: Dictionary) -> MassAllocateCommand:
	var ids: Array[int] = []
	ids.assign(d.get("path_ids", []))
	return MassAllocateCommand.new(int(d.get("entity_id", 0)), ids)
