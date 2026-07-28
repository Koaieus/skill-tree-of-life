extends GutTest

## Tooltip V2 (epic #159, #221) — glass-slab row acceptance test.
## Covers: text is StatModifier.format() verbatim (no reimplemented grammar),
## background tint reads StatDef.tint_color raw, and set_progress(t) drives
## scale/fade directly (no Tween to await). Also proves the row renders
## correctly instantiated bare, with nothing else in the scene (#221 §4 — the
## standalone contract #306's toast depends on).

const _SCENE := preload("res://ui/tooltip_fan/mod_slab_row.tscn")


func _make_modifier(op: StatModifier.Operation, value: float, stat_id: StringName = &"armor") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func test_bind_renders_format_text_verbatim() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"armor")
	row.bind(m)
	assert_eq(row._label.text, m.format())


func test_bind_tints_background_from_stat_def_raw() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	var m := _make_modifier(StatModifier.Operation.INCREASE, 20.0, &"armor")
	row.bind(m)
	var def := StatRegistry.get_def(&"armor")
	assert_eq(row._background.color, def.tint_color)


func test_bind_falls_back_to_white_when_def_unresolved() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	var m := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"not_a_real_stat")
	row.bind(m)
	assert_eq(row._background.color, Color.WHITE)


func test_bind_renders_correctly_with_no_parent_panel() -> void:
	# #221 §4 — the row must work standalone, bound and revealed with nothing
	# else present (no FanPanel, no AddonItem driving it).
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	var m := _make_modifier(StatModifier.Operation.SET, 3.0, &"armor")
	row.bind(m)
	row.set_progress(1.0)
	assert_eq(row._label.text, m.format())
	assert_almost_eq(row.modulate.a, 1.0, 0.001)
	assert_almost_eq(row.scale.x, 1.0, 0.001)


func test_set_progress_at_zero_is_rest_state() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.start_scale = 0.9
	row.set_progress(0.0)
	assert_almost_eq(row.scale.x, 0.9, 0.001)
	assert_almost_eq(row.modulate.a, 0.0, 0.001)


func test_set_progress_at_half_is_partial() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.start_scale = 0.9
	row.set_progress(0.5)
	assert_true(row.modulate.a > 0.0 and row.modulate.a < 1.0)
	assert_true(row.scale.x > 0.9 and row.scale.x < 1.0)


func test_set_progress_at_one_is_fully_revealed() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.start_scale = 0.9
	row.set_progress(1.0)
	assert_almost_eq(row.scale.x, 1.0, 0.001)
	assert_almost_eq(row.modulate.a, 1.0, 0.001)
