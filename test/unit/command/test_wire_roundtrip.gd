extends GutTest

## The round-trip guard behind [WireFields] (#1000): every class that declares
## `wire_fields()` survives `from_dict(to_dict(x))` under fuzzed values, and
## the declared field list agrees with the class's actual vars — so a renamed
## var without the matching `wire_fields()` edit (or vice versa) is red here,
## not a silent default on a peer.
##
## Commands are enumerated through [CommandRegistry], not a hand-kept table,
## so a new verb is covered the moment it is registered. The nested-record
## path (`Field.of_record`) is proven on test-local classes; tagless records
## such as [AttackRecord] are listed in `_records` and get the same guards.

const ITERATIONS := 25

## Vars that deliberately never ride the command's own dictionary — see the
## notes on [member Command.pre_fingerprint] and
## [member LaunchAttackCommand.computed_here]. A new var on a command is
## either declared in `wire_fields()` or named here, on purpose.
const TRANSIENT: Array[StringName] = [
	&"pre_fingerprint", &"host_fingerprint", &"computed_here",
]

## Tagless records — classes that join [WireFields] without being a [Command],
## so [CommandRegistry] cannot enumerate them. Covered by the field-match and
## fuzz guards below; never by the tag test.
var _records: Array[Script] = [AttackRecord]

var _rng := RandomNumberGenerator.new()


class Leaf extends RefCounted:
	var id: int = 0
	var label: StringName = &""

	static func wire_fields() -> Array[WireFields.Field]:
		return [
			WireFields.Field.new(&"id", TYPE_INT),
			WireFields.Field.new(&"label", TYPE_STRING_NAME),
		]


class Grove extends RefCounted:
	var root: Leaf = null
	var leaves: Array[Leaf] = []
	var ids: Array[int] = []
	var weight: float = 0.0

	static func wire_fields() -> Array[WireFields.Field]:
		return [
			WireFields.Field.new(&"root", TYPE_OBJECT).of_record(Leaf),
			WireFields.Field.new(&"leaves", TYPE_ARRAY).of_record(Leaf),
			WireFields.Field.new(&"ids", TYPE_ARRAY).of(TYPE_INT),
			WireFields.Field.new(&"weight", TYPE_FLOAT).as_key(&"w"),
		]


func before_each() -> void:
	_rng.seed = 0xC0FFEE


# --- fuzzing -----------------------------------------------------------------

func _word() -> String:
	var s := ""
	for i in _rng.randi_range(1, 8):
		s += char(_rng.randi_range(97, 122))
	return s


func _fuzz_scalar(type: Variant.Type) -> Variant:
	match type:
		TYPE_INT:
			return _rng.randi_range(-100000, 100000)
		TYPE_FLOAT:
			return _rng.randf_range(-1000.0, 1000.0)
		TYPE_BOOL:
			return _rng.randi() % 2 == 0
		TYPE_STRING:
			return _word()
		TYPE_STRING_NAME:
			return StringName(_word())
		TYPE_DICTIONARY:
			return {_word(): _rng.randi(), "inner": {"k": _word()}, "list": [1, 2, 3]}
		TYPE_PACKED_BYTE_ARRAY:
			var bytes := PackedByteArray()
			for i in _rng.randi_range(0, 6):
				bytes.append(_rng.randi_range(0, 255))
			return bytes
		TYPE_PACKED_INT32_ARRAY:
			var ints := PackedInt32Array()
			for i in _rng.randi_range(0, 6):
				ints.append(_rng.randi_range(-100000, 100000))
			return ints
		TYPE_PACKED_FLOAT64_ARRAY:
			var floats := PackedFloat64Array()
			for i in _rng.randi_range(0, 6):
				floats.append(_rng.randf_range(-1000.0, 1000.0))
			return floats
		TYPE_PACKED_STRING_ARRAY:
			var words := PackedStringArray()
			for i in _rng.randi_range(0, 6):
				words.append(_word())
			return words
	fail_test("no fuzzer for Variant type %d" % type)
	return null


func _fuzz_value(field: WireFields.Field) -> Variant:
	if field.omit_default and _rng.randi() % 2 == 0:
		return field.default
	if field.type == TYPE_OBJECT:
		return _fuzz_object(field.nested)
	if field.type == TYPE_ARRAY:
		var out: Array = []
		for i in _rng.randi_range(0, 5):
			out.append(_fuzz_object(field.nested) if field.nested != null
					else _fuzz_scalar(field.elem_type))
		return out
	return _fuzz_scalar(field.type)


## A fresh instance with every wire field randomised. Typed arrays are filled
## through a duplicate of the declared (typed) array so `set` keeps the type.
func _fuzz_object(cls: Script) -> Object:
	var obj: Object = cls.new()
	for field in WireFields.fields_of(cls):
		var value: Variant = _fuzz_value(field)
		var current: Variant = obj.get(field.name)
		if current is Array:
			var typed: Array = current.duplicate()
			typed.assign(value)
			value = typed
		obj.set(field.name, value)
	return obj


# --- comparison --------------------------------------------------------------

func _assert_same_fields(expected: Object, actual: Object, cls: Script, where: String) -> void:
	for field in WireFields.fields_of(cls):
		var path := "%s.%s" % [where, field.name]
		var a: Variant = expected.get(field.name)
		var b: Variant = actual.get(field.name)
		if field.nested != null and field.type == TYPE_OBJECT:
			if a == null or b == null:
				assert_eq(b, a, path)
			else:
				_assert_same_fields(a, b, field.nested, path)
		elif field.nested != null:
			assert_eq((b as Array).size(), (a as Array).size(), path + " size")
			for i in mini((a as Array).size(), (b as Array).size()):
				_assert_same_fields(a[i], b[i], field.nested, "%s[%d]" % [path, i])
		else:
			assert_eq(b, a, path)
			assert_eq(typeof(b), typeof(a), path + " type")


func _command_scripts() -> Array[Script]:
	var out: Array[Script] = []
	for tag in CommandRegistry.tags():
		var cmd := CommandRegistry.decode({"type": tag})
		assert_not_null(cmd, "registry builds %s from a bare tag" % tag)
		if cmd != null:
			out.append(cmd.get_script())
	return out


func _script_var_names(cls: Script) -> Array[StringName]:
	var names: Array[StringName] = []
	for p in cls.get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(p.name))
	return names


# --- the guard ---------------------------------------------------------------

func test_every_command_declares_wire_fields_that_match_its_vars() -> void:
	var scripts := _command_scripts()
	assert_gt(scripts.size(), 0, "the registry knows some commands")
	for cls in scripts:
		_assert_fields_match_vars(cls)


func test_every_record_declares_wire_fields_that_match_its_vars() -> void:
	for cls in _records:
		_assert_fields_match_vars(cls)


func test_every_record_round_trips_fuzzed() -> void:
	for cls in _records:
		for i in ITERATIONS:
			var record := _fuzz_object(cls)
			var wire := WireFields.to_dict(record)
			var back := WireFields.from_dict(cls, wire)
			assert_eq(back.get_script(), cls, "%s decodes to its own class" % cls.resource_path)
			_assert_same_fields(record, back, cls, cls.resource_path.get_file())
			assert_eq(WireFields.to_dict(back).hash(), wire.hash(),
					"%s wire form identical after a round trip" % cls.resource_path)


func _assert_fields_match_vars(cls: Script) -> void:
	var fields := WireFields.fields_of(cls)
	var instance: Object = cls.new()
	var declared: Array[StringName] = []
	assert_gt(fields.size(), 0, "%s declares wire_fields()" % cls.resource_path)
	for field in fields:
		assert_true(field.name in instance,
				"%s.%s names a real var" % [cls.resource_path, field.name])
		assert_false(declared.has(field.name),
				"%s.%s declared once" % [cls.resource_path, field.name])
		declared.append(field.name)
	for var_name in _script_var_names(cls):
		if TRANSIENT.has(var_name):
			assert_false(declared.has(var_name),
					"%s.%s is transient, never on the wire" % [cls.resource_path, var_name])
		else:
			assert_true(declared.has(var_name),
					"%s.%s is on the wire (or listed as TRANSIENT)" % [cls.resource_path, var_name])


func test_every_command_round_trips_fuzzed_through_the_registry() -> void:
	for cls in _command_scripts():
		for i in ITERATIONS:
			var cmd := _fuzz_object(cls) as Command
			var wire := cmd.to_dict()
			var back := CommandRegistry.decode(wire)
			assert_not_null(back, "%s decodes" % cmd.type_tag())
			if back == null:
				continue
			assert_eq(back.get_script(), cls, "%s decodes to its own class" % cmd.type_tag())
			_assert_same_fields(cmd, back, cls, String(cmd.type_tag()))
			assert_eq(back.to_dict().hash(), wire.hash(),
					"%s wire form identical after a round trip" % cmd.type_tag())


func test_wire_form_starts_with_the_tag_and_holds_no_transient_state() -> void:
	for cls in _command_scripts():
		var cmd := _fuzz_object(cls) as Command
		cmd.pre_fingerprint = 123
		cmd.host_fingerprint = 456
		var wire := cmd.to_dict()
		assert_eq(wire.keys()[0], "type", "%s: type is the first key" % cmd.type_tag())
		assert_eq(wire["type"], cmd.type_tag())
		for transient in TRANSIENT:
			assert_false(wire.has(String(transient)),
					"%s: %s stays off the wire" % [cmd.type_tag(), transient])


func test_intent_id_is_omitted_at_zero_and_carried_when_minted() -> void:
	var cmd := AllocateCommand.new(7, 42)
	assert_false(cmd.to_dict().has("intent_id"), "unminted: key absent")
	cmd.intent_id = 9
	var wire := cmd.to_dict()
	assert_eq(wire.get("intent_id"), 9, "minted: key present")
	var back := CommandRegistry.decode(wire)
	assert_eq(back.intent_id, 9)


func test_a_missing_key_leaves_the_fresh_default_in_place() -> void:
	var back := WireFields.from_dict(PickLootCommand, {"entity_id": 3}) as PickLootCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 3)
	assert_eq(back.chosen_index, -1, "default of the var, not a zero")


func test_from_dict_coerces_wire_primitives_to_the_declared_types() -> void:
	var back := WireFields.from_dict(ToggleTempUpgradeCommand,
			{"entity_id": 3.0, "node_id": "12", "upgrade_id": "blade"}) as ToggleTempUpgradeCommand
	assert_eq(typeof(back.entity_id), TYPE_INT)
	assert_eq(back.node_id, 12)
	assert_eq(typeof(back.upgrade_id), TYPE_STRING_NAME)
	assert_eq(back.upgrade_id, &"blade")


func test_to_dict_copies_arrays_and_keeps_them_typed_after_decode() -> void:
	var cmd := MoveCoreCommand.new(1, [4, 5])
	var wire := cmd.to_dict()
	(wire["path_ids"] as Array).append(99)
	assert_eq(cmd.path_ids, [4, 5] as Array[int], "wire array is a copy")
	var back := WireFields.from_dict(MoveCoreCommand, {"path_ids": [1, 2]}) as MoveCoreCommand
	assert_true(back.path_ids.is_typed(), "decoded array keeps the declared element type")
	assert_eq(back.path_ids.get_typed_builtin(), TYPE_INT)


# --- the nested seam (unit 2 hooks AttackRecord in here) ---------------------

func test_nested_records_and_record_arrays_round_trip() -> void:
	for i in ITERATIONS:
		var tree := _fuzz_object(Grove) as Grove
		var wire := WireFields.to_dict(tree)
		assert_true(wire.has("w"), "a renamed wire key is honoured")
		assert_false(wire.has("weight"))
		for leaf: Variant in wire.get("leaves", []):
			assert_eq(typeof(leaf), TYPE_DICTIONARY, "nested records serialise as dictionaries")
		var back := WireFields.from_dict(Grove, wire) as Grove
		assert_not_null(back)
		if back == null:
			continue
		_assert_same_fields(tree, back, Grove, "tree")
		assert_true(back.leaves.is_typed(), "decoded record array keeps its element class")
		assert_eq(WireFields.to_dict(back).hash(), wire.hash())


func test_a_null_nested_record_rides_as_null_and_decodes_to_null() -> void:
	var tree := Grove.new()
	var wire := WireFields.to_dict(tree)
	assert_true(wire.has("root"))
	assert_null(wire["root"])
	var back := WireFields.from_dict(Grove, wire) as Grove
	assert_null(back.root)
