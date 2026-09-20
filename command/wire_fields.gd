class_name WireFields
extends RefCounted

## Reflective wire serialisation (#1000): a class declares its wire form ONCE
## as `static func wire_fields() -> Array[WireFields.Field]`, and
## [method to_dict] / [method from_dict] walk that list over `get` / `set`.
## Replaces the hand-rolled `to_dict` + mirror `from_dict` pairs whose only
## guard against a key typo was a silent default.
##
## Stub — filled in behind `test/unit/command/test_wire_roundtrip.gd`.


## One declared field. Built fluently:
## `Field.new(&"path_ids", TYPE_ARRAY).of(TYPE_INT)`.
class Field extends RefCounted:
	var name: StringName
	var type: Variant.Type
	var default: Variant
	var key: StringName
	var elem_type: Variant.Type = TYPE_NIL
	var nested: Script = null
	var omit_default: bool = false

	func _init(name_: StringName, type_: Variant.Type, default_: Variant = null) -> void:
		name = name_
		type = type_
		key = name_
		default = default_ if default_ != null else type_convert(null, type_)

	func of(elem_type_: Variant.Type) -> Field:
		elem_type = elem_type_
		return self

	func as_key(key_: StringName) -> Field:
		key = key_
		return self

	func of_record(script: Script) -> Field:
		nested = script
		return self

	func omitted_at_default() -> Field:
		omit_default = true
		return self


static func fields_of(cls: Script) -> Array[Field]:
	return []


static func to_dict(obj: Object) -> Dictionary:
	return {}


static func from_dict(cls: Script, d: Dictionary) -> Object:
	return null
