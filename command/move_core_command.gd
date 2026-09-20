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


## The wire form, declared once (#1000); see [WireFields].
static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"path_ids", TYPE_ARRAY).of(TYPE_INT))
	return fields


static func from_dict(d: Dictionary) -> MoveCoreCommand:
	return WireFields.from_dict(MoveCoreCommand, d)
