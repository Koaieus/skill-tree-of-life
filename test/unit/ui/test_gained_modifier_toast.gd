extends GutTest

## Gained-modifier toast (#306, epic #159 Phase 0) — standalone acceptance
## test. Covers: one row per FLATTENED modifier leaf with `format()`-verbatim
## text, staggered reveal driven via `ModSlabRow.set_progress` (never
## `play_entry`, which no longer exists), concurrent batches that stack below
## whatever's still on screen instead of replacing it, and the absorb exit
## converging every row on the anchor + reflowing survivors to close the gap.
##
## Drives the whole timeline with `Tween.custom_step()` rather than real
## waits, per `test/unit/ui/test_fan_unit.gd`'s pattern — `GainedModifierToast`
## chains its reveal -> dwell -> absorb via `tween_callback` + `set_delay`
## (the same idiom `FloaterToast.animate` uses), so a single large
## `custom_step` fast-forwards a whole phase and fires its callback inline.

const _SCENE := preload("res://ui/gained_modifier_toast/gained_modifier_toast.tscn")


func _make() -> GainedModifierToast:
	var toast := _SCENE.instantiate() as GainedModifierToast
	add_child(toast)
	autofree(toast)
	return toast


func _make_modifier(op: StatModifier.Operation, value: float, stat_id: StringName) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func _make_composite(children: Array[StatModifier]) -> CompositeStatModifier:
	var c := CompositeStatModifier.new()
	c.children = children
	return c


## All rows across every in-flight batch, in display order (top to bottom) —
## the multi-batch equivalent of the old flat `_rows` array.
func _all_rows(toast: GainedModifierToast) -> Array:
	var rows := []
	for batch in toast._batches:
		rows.append_array(batch.rows)
	return rows


# --- row count + flattening ---------------------------------------------------

func test_show_gains_spawns_one_row_per_modifier() -> void:
	var toast := _make()
	var mods: Array[StatModifier] = [
		_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength"),
		_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor"),
	]
	toast.show_gains(mods)
	assert_eq(_all_rows(toast).size(), 2)


func test_show_gains_flattens_composite_modifiers_into_one_row_per_leaf() -> void:
	var toast := _make()
	var leaf_a := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	var leaf_b := _make_modifier(StatModifier.Operation.INCREASE, 18.0, &"intelligence")
	var composite := _make_composite([leaf_a, leaf_b])
	toast.show_gains([composite])
	assert_eq(_all_rows(toast).size(), 2, "a composite must expand to one row per leaf")


func test_show_gains_with_no_leaves_spawns_nothing() -> void:
	var toast := _make()
	toast.show_gains([])
	assert_eq(_all_rows(toast).size(), 0)


# --- text is format() verbatim -------------------------------------------------

func test_row_text_matches_modifier_format_verbatim() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	assert_eq(_all_rows(toast)[0]._label.text, m.format())


# --- rows never pop to full alpha; play_entry does not exist -------------------

func test_freshly_spawned_rows_rest_at_zero_before_reveal_plays() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	assert_almost_eq(_all_rows(toast)[0].modulate.a, 0.0, 0.001,
		"a row must not pop to full alpha before the layer drives set_progress")


func test_mod_slab_row_has_no_play_entry_method() -> void:
	var row := preload("res://ui/tooltip_fan/mod_slab_row.tscn").instantiate()
	add_child(row)
	autofree(row)
	assert_false(row.has_method("play_entry"), "play_entry no longer exists on ModSlabRow (#221)")


func test_reveal_drives_rows_to_full_alpha() -> void:
	var toast := _make()
	var mods: Array[StatModifier] = [
		_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength"),
		_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor"),
	]
	toast.show_gains(mods)
	toast._batches[0].tween.custom_step(1000.0)
	for row in _all_rows(toast):
		assert_almost_eq(row.modulate.a, 1.0, 0.001)


# --- absorb: fades back out and converges on the anchor (position -> ZERO) ----

func test_absorb_fades_rows_back_to_zero_and_slides_to_anchor() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	var batch := toast._batches[0]
	var row := batch.rows[0]
	var start_position := row.position
	# Reveal -> dwell -> absorb callback all chained on one tween; a single
	# huge custom_step fast-forwards through the callback into the new
	# absorb tween `_play_absorb` assigns to `batch.tween`.
	batch.tween.custom_step(1000.0)
	var absorb_tween := batch.tween
	assert_ne(absorb_tween, null)
	# A PARTIAL step here, not another huge one — a huge step would also fire
	# the absorb's own tween_callback(_finish_batch) and free the row before
	# this test can inspect its mid-flight state (see the sibling test for
	# that full-completion behaviour).
	absorb_tween.custom_step(toast.exit_duration * 0.5)
	assert_true(row.modulate.a < 1.0, "absorb must fade the row back out")
	assert_true(row.position.length() < start_position.length(),
		"absorb must slide the row toward the anchor (local origin), not fade in place")


func test_absorb_clears_the_stack_when_finished() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	var batch := toast._batches[0]
	batch.tween.custom_step(1000.0)  # reveal + dwell -> triggers _play_absorb
	batch.tween.custom_step(1000.0)  # absorb -> triggers _finish_batch
	assert_eq(toast._batches.size(), 0)


# --- concurrent batches: append below, never replace ---------------------------

func test_retrigger_mid_dwell_appends_a_second_batch_instead_of_replacing() -> void:
	var toast := _make()
	var first := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([first])
	var first_row := toast._batches[0].rows[0]

	var second_a := _make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")
	var second_b := _make_modifier(StatModifier.Operation.INCREASE, 18.0, &"intelligence")
	toast.show_gains([second_a, second_b])

	assert_eq(toast._batches.size(), 2, "a retrigger mid-dwell must open a second batch")
	assert_eq(_all_rows(toast).size(), 3, "the first batch's row must still be on screen")
	assert_true(is_instance_valid(first_row) and first_row.is_inside_tree(),
		"the lingering first batch must not be dropped")


func test_second_batch_positions_below_the_first() -> void:
	var toast := _make()
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")])
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")])

	var first_row := toast._batches[0].rows[0]
	var second_row := toast._batches[1].rows[0]
	assert_almost_eq(second_row.position.y - first_row.position.y, toast.row_height, 0.001,
		"the second batch's row must sit exactly one row_height below the first batch's")


func test_retrigger_does_not_kill_the_first_batchs_tween() -> void:
	var toast := _make()
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")])
	var first_tween := toast._batches[0].tween
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")])
	assert_true(first_tween.is_valid(),
		"an in-flight batch's own tween must keep running, not get killed by a retrigger")


func test_batch_that_finishes_first_reflows_the_survivor_up_to_close_the_gap() -> void:
	var toast := _make()
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")])
	var first_batch := toast._batches[0]
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")])
	var second_row := toast._batches[1].rows[0]
	var second_row_start_y := second_row.position.y

	# Fast-forward only the FIRST batch all the way through absorb + finish;
	# the second batch's own tween is untouched (independent timelines).
	first_batch.tween.custom_step(1000.0)  # reveal + dwell -> _play_absorb
	first_batch.tween.custom_step(1000.0)  # absorb -> _finish_batch -> _reflow

	assert_eq(toast._batches.size(), 1, "the finished batch must be gone")
	# _reflow tweens the survivor upward rather than snapping it — let that
	# tween resolve before asserting the closed gap.
	await get_tree().create_timer(toast.reflow_duration + 0.05).timeout
	assert_almost_eq(second_row.position.y, toast.stack_offset.y, 0.5,
		"the surviving batch must slide up to close the gap the finished one left")
	assert_true(second_row.position.y < second_row_start_y,
		"the surviving row must have moved up, not stayed put")
