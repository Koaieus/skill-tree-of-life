extends GutTest

## Gained-modifier toast (#306, epic #159 Phase 0) — standalone acceptance
## test. Covers: one row per FLATTENED modifier leaf with `format()`-verbatim
## text, staggered reveal driven via `ModSlabRow.set_progress` (never
## `play_entry`, which no longer exists), replace-on-retrigger (no queueing,
## no stacked dwells), and the absorb exit converging every row on the anchor.
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


# --- row count + flattening ---------------------------------------------------

func test_show_gains_spawns_one_row_per_modifier() -> void:
	var toast := _make()
	var mods: Array[StatModifier] = [
		_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength"),
		_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor"),
	]
	toast.show_gains(mods)
	assert_eq(toast._rows.size(), 2)


func test_show_gains_flattens_composite_modifiers_into_one_row_per_leaf() -> void:
	var toast := _make()
	var leaf_a := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	var leaf_b := _make_modifier(StatModifier.Operation.INCREASE, 18.0, &"intelligence")
	var composite := _make_composite([leaf_a, leaf_b])
	toast.show_gains([composite])
	assert_eq(toast._rows.size(), 2, "a composite must expand to one row per leaf")


func test_show_gains_with_no_leaves_spawns_nothing() -> void:
	var toast := _make()
	toast.show_gains([])
	assert_eq(toast._rows.size(), 0)


# --- text is format() verbatim -------------------------------------------------

func test_row_text_matches_modifier_format_verbatim() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	assert_eq(toast._rows[0]._label.text, m.format())


# --- rows never pop to full alpha; play_entry does not exist -------------------

func test_freshly_spawned_rows_rest_at_zero_before_reveal_plays() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	assert_almost_eq(toast._rows[0].modulate.a, 0.0, 0.001,
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
	toast._tween.custom_step(1000.0)
	for row in toast._rows:
		assert_almost_eq(row.modulate.a, 1.0, 0.001)


# --- absorb: fades back out and converges on the anchor (position -> ZERO) ----

func test_absorb_fades_rows_back_to_zero_and_slides_to_anchor() -> void:
	var toast := _make()
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([m])
	var row := toast._rows[0]
	var start_position := row.position
	# Reveal -> dwell -> absorb callback all chained on one tween; a single
	# huge custom_step fast-forwards through the callback into the new
	# absorb tween `_play_absorb` assigns to `_tween`.
	toast._tween.custom_step(1000.0)
	var absorb_tween := toast._tween
	assert_ne(absorb_tween, null)
	# A PARTIAL step here, not another huge one — a huge step would also fire
	# the absorb's own tween_callback(_clear_rows) and free the row before
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
	toast._tween.custom_step(1000.0)  # reveal + dwell -> triggers _play_absorb
	toast._tween.custom_step(1000.0)  # absorb -> triggers _clear_rows
	assert_eq(toast._rows.size(), 0)


# --- replace, never queue -------------------------------------------------------

func test_retrigger_mid_dwell_replaces_the_stack_instead_of_queueing() -> void:
	var toast := _make()
	var first := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	toast.show_gains([first])
	var first_row := toast._rows[0]

	var second_a := _make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")
	var second_b := _make_modifier(StatModifier.Operation.INCREASE, 18.0, &"intelligence")
	toast.show_gains([second_a, second_b])

	assert_eq(toast._rows.size(), 2, "retrigger replaces the stack outright")
	assert_false(is_instance_valid(first_row) and first_row.is_inside_tree(),
		"the old stack must not linger once replaced")


func test_retrigger_does_not_stack_dwells() -> void:
	var toast := _make()
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")])
	var first_tween := toast._tween
	toast.show_gains([_make_modifier(StatModifier.Operation.ADD_BONUS, 3.0, &"armor")])
	assert_false(first_tween.is_valid(), "the old sequence's tween must be killed, not left running")
