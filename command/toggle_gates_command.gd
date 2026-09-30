class_name ToggleGatesCommand
extends Command

## "Flip exactly these gates, at once." One command for a toggle-all — the
## submitter expands it — because the flips apply together and connectivity is
## judged once, after all of them (order-independent by construction).
##
## [b]Host-stamped cascade.[/b] [member stranded_ids] is empty on an intent;
## the authority's validate stamps the preview's stranded set into it before the
## confirm, and every peer — the authority included — applies that stamped set
## without re-walking a navigator (the [AttackRecord] precedent: a fogged
## client cannot derive the actor's cascade).

const TAG: StringName = &"toggle_gates"

## The gates to flip, flat: `[from_stable_id, to_stable_id, …]`. A pair names a
## gate in either direction.
var pairs: Array[int] = []

## The owned nodes the flip strands, as stable ids — stamped by the authority.
var stranded_ids: Array[int] = []


func _init(entity_id_: int = 0, pairs_: Array[int] = []) -> void:
	super(entity_id_)
	pairs = pairs_


func type_tag() -> StringName:
	return TAG


## The wire form, declared once (#1000); see [WireFields].
static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"pairs", TYPE_ARRAY).of(TYPE_INT))
	fields.append(WireFields.Field.new(&"stranded_ids", TYPE_ARRAY).of(TYPE_INT))
	return fields


static func from_dict(d: Dictionary) -> ToggleGatesCommand:
	return WireFields.from_dict(ToggleGatesCommand, d)
