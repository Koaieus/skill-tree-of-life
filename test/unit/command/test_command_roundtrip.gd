extends GutTest

## Every [Command] survives `from_dict(c.to_dict())` field-for-field (#509).
##
## One test per type, deliberately not a loop: a loop over a table would go
## green on a type whose extra field nobody remembered to serialize, because
## the table would not know to name it either.

const _PRIMITIVE_TYPES: Array[int] = [
	TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME
]


## Round-trip through the codec (the only path an applier ever uses) and
## assert the wire form is identical. `Dictionary.hash()` is content-based, so
## this catches a dropped or renamed field.
func _round_trip(cmd: Command) -> Command:
	var back := CommandCodec.from_dict(cmd.to_dict())
	assert_not_null(back, "codec rebuilt something")
	if back != null:
		assert_eq(back.to_dict().hash(), cmd.to_dict().hash(), "wire form identical")
	return back


func test_allocate_round_trips() -> void:
	var back := _round_trip(AllocateCommand.new(7, 42)) as AllocateCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_id, 42)
	assert_eq(back.type_tag(), AllocateCommand.TAG)


func test_deallocate_round_trips() -> void:
	var back := _round_trip(DeallocateCommand.new(7, 42)) as DeallocateCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_id, 42)
	assert_eq(back.type_tag(), DeallocateCommand.TAG)


func test_deallocate_set_round_trips() -> void:
	var ids: Array[int] = [3, 1, 4]
	var back := _round_trip(DeallocateSetCommand.new(7, ids)) as DeallocateSetCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_ids, ids)
	assert_eq(back.type_tag(), DeallocateSetCommand.TAG)


func test_mass_allocate_round_trips_the_path_and_carries_no_count() -> void:
	var path: Array[int] = [10, 11, 12]
	var cmd := MassAllocateCommand.new(7, path)
	var back := _round_trip(cmd) as MassAllocateCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.path_ids, path)
	# affordable_count is client-side today and must be recomputed by the
	# applier — it is deliberately absent from the wire form (#458).
	assert_false(cmd.to_dict().has("affordable_count"), "no affordable_count on the wire")


func test_stake_round_trips() -> void:
	var back := _round_trip(StakeCommand.new(7, 42)) as StakeCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_id, 42)
	assert_eq(back.type_tag(), StakeCommand.TAG)


func test_extract_round_trips() -> void:
	var back := _round_trip(ExtractCommand.new(7, 42)) as ExtractCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_id, 42)
	assert_eq(back.type_tag(), ExtractCommand.TAG)


func test_move_core_round_trips_the_whole_path_in_order() -> void:
	var path: Array[int] = [5, 6, 7, 8]
	var back := _round_trip(MoveCoreCommand.new(7, path)) as MoveCoreCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.path_ids, path, "order preserved — the applier walks the hops")
	assert_eq(back.type_tag(), MoveCoreCommand.TAG)


func test_end_turn_round_trips() -> void:
	var back := _round_trip(EndTurnCommand.new(7)) as EndTurnCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.type_tag(), EndTurnCommand.TAG)


func test_pick_loot_round_trips() -> void:
	var back := _round_trip(PickLootCommand.new(7, 99, 2)) as PickLootCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.request_id, 99)
	assert_eq(back.chosen_index, 2)
	assert_eq(back.type_tag(), PickLootCommand.TAG)


## A draw is a pick-ONE, so forfeiting is the only "no pick" a round can
## express — and it has to survive the wire, or a forfeit read back as index 0
## would silently grant the first candidate instead.
func test_a_forfeited_pick_round_trips_as_minus_one() -> void:
	var back := _round_trip(PickLootCommand.new(7, 99, -1)) as PickLootCommand
	assert_not_null(back)
	assert_eq(back.chosen_index, -1)


func test_toggle_temp_upgrade_round_trips_including_the_upgrade_id() -> void:
	var cmd := ToggleTempUpgradeCommand.new(7, 42, &"clamp")
	var back := _round_trip(cmd) as ToggleTempUpgradeCommand
	assert_not_null(back)
	assert_eq(back.entity_id, 7)
	assert_eq(back.node_id, 42)
	assert_eq(back.upgrade_id, &"clamp", "which upgrade, not just where")
	assert_eq(back.type_tag(), ToggleTempUpgradeCommand.TAG)


func _every_command() -> Array[Command]:
	var node_ids: Array[int] = [1, 2]
	var path: Array[int] = [1, 2, 3]
	return [
		AllocateCommand.new(1, 2),
		DeallocateCommand.new(1, 2),
		DeallocateSetCommand.new(1, node_ids),
		MassAllocateCommand.new(1, path),
		StakeCommand.new(1, 2),
		ExtractCommand.new(1, 2),
		MoveCoreCommand.new(1, path),
		EndTurnCommand.new(1),
		PickLootCommand.new(1, 5, 0),
		ToggleTempUpgradeCommand.new(1, 2, &"spike_ring"),
	]


func test_the_vocabulary_is_ten_commands() -> void:
	assert_eq(_every_command().size(), 10)


## The load-bearing invariant: a command NEVER holds a SkillNode or Entity
## reference (`.claude/rules/multiplayer-sync.md`). Checked structurally, so
## a future command that stashes an object fails here rather than at the far
## end of a wire.
func test_no_command_puts_an_object_on_the_wire() -> void:
	for cmd in _every_command():
		for key: Variant in cmd.to_dict():
			var value: Variant = cmd.to_dict()[key]
			if value is Array:
				for element: Variant in value:
					assert_eq(typeof(element), TYPE_INT,
							"%s.%s element is an int" % [cmd.type_tag(), key])
			else:
				assert_true(_PRIMITIVE_TYPES.has(typeof(value)),
						"%s.%s is a primitive, got %s" % [cmd.type_tag(), key, typeof(value)])


func test_every_command_has_a_distinct_nonempty_tag() -> void:
	var seen: Array[StringName] = []
	for cmd in _every_command():
		assert_ne(cmd.type_tag(), &"", "a concrete command overrides type_tag")
		assert_false(seen.has(cmd.type_tag()), "tag %s is unique" % cmd.type_tag())
		seen.append(cmd.type_tag())
