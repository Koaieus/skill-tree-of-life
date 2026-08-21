extends GutTest

## [CommandCodec]'s dispatch, and what it does with input it does not
## recognise (#509).


func test_unknown_tag_returns_null_without_half_building() -> void:
	# The push_warning is the point of the contract, but GUT would report it
	# as a failure if left unignored.
	var back: Command = null
	back = CommandCodec.from_dict({"type": &"teleport", "entity_id": 7})
	assert_null(back, "unknown tag yields nothing, not a partial command")


func test_missing_tag_returns_null() -> void:
	assert_null(CommandCodec.from_dict({"entity_id": 7}))


func test_empty_dictionary_returns_null() -> void:
	assert_null(CommandCodec.from_dict({}))


func test_dispatch_picks_the_concrete_type_not_the_base() -> void:
	var back := CommandCodec.from_dict(StakeCommand.new(1, 2).to_dict())
	assert_true(back is StakeCommand, "got a StakeCommand")
	assert_false(back is ExtractCommand, "and not its identically-shaped sibling")


func test_a_missing_field_decodes_to_the_default_rather_than_erroring() -> void:
	var back := CommandCodec.from_dict({"type": AllocateCommand.TAG}) as AllocateCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 0)
	assert_eq(back.node_id, 0)


func test_decoded_arrays_are_typed_int_arrays() -> void:
	var ids: Array[int] = [1, 2, 3]
	var back := CommandCodec.from_dict(
			DeallocateSetCommand.new(1, ids).to_dict()) as DeallocateSetCommand
	assert_not_null(back)
	assert_eq(back.node_ids.get_typed_builtin(), TYPE_INT)


## A command's array field must be a COPY, or two commands built from one
## local would alias each other's payload.
func test_to_dict_copies_array_payloads() -> void:
	var ids: Array[int] = [1, 2]
	var cmd := DeallocateSetCommand.new(1, ids)
	var wire := cmd.to_dict()
	cmd.node_ids.append(3)

	assert_eq((wire["node_ids"] as Array).size(), 2, "the snapshot did not follow the command")
