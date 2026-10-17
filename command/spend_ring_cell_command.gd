class_name SpendRingCellCommand
extends Command
## Intent: entity `entity_id` buys the inner-ring cell named `cell` (a node
## name in the ring scene, never a stable_id). Validated by the host against
## [RingTable]; applied through [method Entity.buy_ring_cell].


const TAG: StringName = &"spend_ring_cell"

var cell: StringName = &""


func _init(entity_id_: int = 0, cell_: StringName = &"") -> void:
	super(entity_id_)
	cell = cell_


func type_tag() -> StringName:
	return TAG


static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"cell", TYPE_STRING_NAME))
	return fields


static func from_dict(d: Dictionary) -> SpendRingCellCommand:
	return WireFields.from_dict(SpendRingCellCommand, d)
