class_name MoveCoreCommand
extends Command

## "Walk my core along this path." The WHOLE path, one command — not one per
## hop.
##
## The applier walks the hops and stops on the first failure, exactly as
## `systems/player_input_controller.gd:591` does today. "Atomic" here means
## *one command*, not all-or-nothing: a partial core walk is already an
## observable legal state offline, and this deliberately does not invent a
## new rollback rule for it (#458 decision 4).

const TAG: StringName = &"move_core"

## The hops, in walk order, as [member SkillNode.stable_id]s.
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


static func from_dict(d: Dictionary) -> MoveCoreCommand:
	var ids: Array[int] = []
	ids.assign(d.get("path_ids", []))
	return MoveCoreCommand.new(int(d.get("entity_id", 0)), ids)
