class_name WireFields
extends RefCounted

## Reflective wire serialisation (#1000): a class declares its wire form ONCE
## as `static func wire_fields() -> Array[WireFields.Field]`, and
## [method to_dict] / [method from_dict] walk that list over `get` / `set`.
## Replaces the hand-rolled `to_dict` + mirror `from_dict` pairs whose only
## guard against a key typo was a silent default; the guard now is
## `test/unit/command/test_wire_roundtrip.gd`, which fuzzes every declared
## class through both directions and checks the list against the class's vars.
##
## [b]The list is the whole contract.[/b] A var not in `wire_fields()` never
## rides the wire (that is how [member Command.pre_fingerprint] stays
## transient); a subclass extends its base's list by calling the base's static
## by name (`Command.wire_fields()`) and appending, so a derived class's keys
## always follow its base's and the wire order is stable across a refactor.
##
## Decode is lenient the way the hand-rolled readers were: a missing key
## leaves the freshly-constructed default in place, a wire primitive is
## coerced to the declared type (`3.0` -> `3`, `"blade"` -> `&"blade"`), and a
## typed array is rebuilt through a duplicate of the declared one so it keeps
## its element type. Nested records (`Field.of_record`) recurse — one record
## or an array of them. A flat parallel-array record joins through typed
## packed columns instead ([AttackRecord]: one `Packed*` var per wire key).


## One declared field. Built fluently:
## `Field.new(&"path_ids", TYPE_ARRAY).of(TYPE_INT)`,
## `Field.new(&"resolve_seed", TYPE_INT).as_key(&"seed")`,
## `Field.new(&"entries", TYPE_ARRAY).of_record(DeallocEntry)`.
class Field extends RefCounted:
	## The var on the class; read with `get`, written with `set`.
	var name: StringName
	## The declared Variant type; decode coerces to it, the fuzzer draws from it.
	var type: Variant.Type
	## What a fresh instance holds; only consulted by [member omit_default].
	var default: Variant
	## The dictionary key. Defaults to [member name]; set when the wire has to
	## keep an older spelling (committed fixtures pin `seed`, not `resolve_seed`).
	var key: StringName
	## For `TYPE_ARRAY` of scalars: the element type each entry is coerced to.
	var elem_type: Variant.Type = TYPE_NIL
	## For `TYPE_OBJECT`, or `TYPE_ARRAY` of records: the element class, which
	## must itself declare `wire_fields()`.
	var nested: Script = null
	## Leave the key out entirely while the value equals [member default] —
	## for [member Command.intent_id], whose absence at 0 keeps every
	## `test/fixtures/outcome/*.tres` byte-identical.
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


## The declared list of `cls`, typed. A class without `wire_fields()` is a
## caller error and surfaces as the engine's "nonexistent function".
static func fields_of(cls: Script) -> Array[Field]:
	var out: Array[Field] = []
	out.assign(cls.call(&"wire_fields"))
	return out


## Fields only — no type tag, so a tagless record serialises the same way.
## [method Command.to_dict] prepends `type` itself.
static func to_dict(obj: Object) -> Dictionary:
	var d := {}
	for field in fields_of(obj.get_script()):
		var value: Variant = obj.get(field.name)
		if field.omit_default and value == field.default:
			continue
		d[field.key] = _encode(field, value)
	return d


## A fresh `cls` with every present key decoded onto it.
static func from_dict(cls: Script, d: Dictionary) -> Object:
	var obj: Object = cls.new()
	for field in fields_of(cls):
		if not d.has(field.key):
			continue
		if not (field.name in obj):
			push_error("%s.wire_fields() names '%s', which is not a var on the class"
					% [cls.resource_path, field.name])
			continue
		obj.set(field.name, _decode(field, d[field.key], obj.get(field.name)))
	return obj


static func _encode(field: Field, value: Variant) -> Variant:
	if value == null:
		return null
	if field.nested != null:
		if field.type == TYPE_ARRAY:
			var out: Array = []
			for element: Variant in value:
				out.append(null if element == null else to_dict(element))
			return out
		return to_dict(value)
	if value is Array:
		return (value as Array).duplicate()
	if _is_packed(value):
		# A packed array is a value type but shares its buffer copy-on-write;
		# hand the wire its own so a later append on the record never reaches
		# a dictionary already queued for send (AttackRecord's columns).
		return value.duplicate()
	return value


static func _is_packed(value: Variant) -> bool:
	return typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY


static func _decode(field: Field, raw: Variant, current: Variant) -> Variant:
	if raw == null:
		return null if field.type == TYPE_OBJECT else current
	match field.type:
		TYPE_OBJECT:
			return from_dict(field.nested, raw)
		TYPE_ARRAY:
			var typed: Array = (current as Array).duplicate() if current is Array else []
			typed.clear()
			var items: Array = []
			for element: Variant in raw:
				if field.nested != null:
					items.append(null if element == null else from_dict(field.nested, element))
				elif field.elem_type != TYPE_NIL:
					items.append(type_convert(element, field.elem_type))
				else:
					items.append(element)
			typed.assign(items)
			return typed
		TYPE_DICTIONARY:
			return raw
	return type_convert(raw, field.type)
