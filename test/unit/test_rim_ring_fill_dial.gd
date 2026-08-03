extends GutTest
## #341: the allocation dial folded into rim_ring.gdshader as `fill_slots`.
## Legibility (the actual point of the issue) is an eyeball pass on the
## committed matrix scene, not something GDScript can assert without a real
## rendering backend — this file covers only the discrete semantics GDScript
## CAN check: 0/* pushes a zero fill, 1/1 is flagged as the gapless special
## case, M clamps to N, and RimRing never reads entity_tint (rim is archetype
## identity only, never the owner's).

const RimRingScene := preload("res://skill_node/visuals/rim_ring.tscn")


func _make_rim() -> Node2D:
	var rim: Node2D = add_child_autofree(RimRingScene.instantiate())
	return rim


func test_zero_current_pushes_a_zero_fill() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.fill_max = 3
	rim.fill_current = 0
	var pushed: Variant = rim.get_instance_shader_parameter("fill_slots")
	assert_not_null(pushed, "a visible rim binds its shader uniforms")
	assert_eq((pushed as Vector2).x, 0.0, "0/* pushes fill_current == 0 to the shader")


func test_one_of_one_is_flagged_gapless() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.fill_max = 1
	rim.fill_current = 1
	assert_true(rim.is_gapless, "M == N == 1 is the single-unbroken-ring special case")


func test_partial_fill_is_not_gapless() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.fill_max = 3
	rim.fill_current = 1
	assert_false(rim.is_gapless, "N > 1 always shows gaps, even fully lit (3/3)")

	rim.fill_current = 3
	assert_false(rim.is_gapless, "3/3 is fully lit but still gapped — only 1/1 is gapless")


func test_zero_max_has_no_gapless_reading_either() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.fill_max = 1
	rim.fill_current = 0
	assert_false(rim.is_gapless, "0/1 draws nothing at all, not a gapless ring")


func test_current_clamps_to_max() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.fill_max = 2
	rim.fill_current = 8
	assert_eq(rim.fill_current, 2, "fill_current clamps to fill_max")

	rim.fill_max = 1
	assert_eq(rim.fill_current, 1, "lowering fill_max re-clamps the already-set fill_current")


func test_rim_ring_never_reads_entity_tint() -> void:
	var rim := _make_rim()
	await get_tree().process_frame

	rim.entity_tint = Color(1.0, 0.0, 0.0)
	rim.archetype_tint = Color(0.0, 1.0, 0.0)
	rim.fill_max = 1
	rim.fill_current = 1

	var pushed: Variant = rim.get_instance_shader_parameter("ring_tint")
	assert_not_null(pushed, "a visible rim binds its shader uniforms")
	assert_ne(
		(pushed as Color).g, 0.0,
		"ring_tint is derived from archetype_tint (green channel), never entity_tint"
	)
	# Flip entity_tint alone; the pushed ring_tint must not move, since RimRing
	# is archetype-tinted only — it is structure, not ownership.
	var before: Color = pushed
	rim.entity_tint = Color(0.0, 0.0, 1.0)
	var after: Variant = rim.get_instance_shader_parameter("ring_tint")
	assert_eq(after, before, "entity_tint has no effect on RimRing's pushed tint")
