extends GutTest

## [FaultLineCrack] is [EdgeEnergize]'s sibling and restates its claims: every
## instance shares ONE material (so 60 cracks are one batch), per-instance
## animation rides transform + `modulate` never a uniform, endpoints derive
## from the entry, and `finished` waits on BOTH the seal and the shatter. The
## one inversion against EdgeEnergize: the bar's y-scale IS the width channel.

const CRACK := preload("res://ui/vfx/fault_line/fault_line_crack.tscn")
const ZLayers = preload("res://ui/z_layers.gd")
const COORDINATOR := preload("res://ui/vfx/coordinator/spells/fault_line_coordinator.tscn")

const PEAK: int = 60
const A := Vector2(120.0, 340.0)
const B := Vector2(520.0, 100.0)


func _spawn() -> FaultLineCrack:
	var crack: FaultLineCrack = CRACK.instantiate()
	crack.clock.manual = true
	add_child_autofree(crack)
	crack.edge_origin = A
	crack.edge_target = B
	return crack


func _bar(crack: FaultLineCrack) -> Sprite2D:
	return crack.get_node("%Bar") as Sprite2D


func _status(status_id: StringName, power: float) -> StatusInstance:
	var def := StatusDef.new()
	def.id = status_id
	var inst := StatusInstance.new()
	inst.def = def
	inst.power = power
	return inst


func _entry(hits: Array) -> ScheduleEntry:
	var entry := ScheduleEntry.new()
	for hit in hits:
		entry.hits.append(hit)
	return entry


## Every shader parameter currently set on the material's shader.
func _params(material: ShaderMaterial) -> Dictionary:
	var out: Dictionary = {}
	for uniform in material.shader.get_shader_uniform_list():
		var key: StringName = uniform[&"name"]
		out[key] = material.get_shader_parameter(key)
	return out


# ------------------------------------------------------------------- batching


func test_sixty_cracks_share_one_material() -> void:
	var materials: Array = []
	for _i in PEAK:
		var mat := _bar(_spawn()).material
		if not materials.has(mat):
			materials.append(mat)
	assert_eq(materials.size(), 1, "60 cracks must resolve to exactly one material resource")
	assert_eq(materials[0], FaultLineCrack.SHARED_MATERIAL, "and it is the one named on the class")


func test_a_full_flight_writes_no_parameter_on_either_shared_material() -> void:
	# Scoped to the two shared resources: the crit's ShatterField legitimately
	# writes uniforms on its own resource_local_to_scene material.
	var crack := _spawn()
	var shared_before := _params(FaultLineCrack.SHARED_MATERIAL)
	var edge_before := _params(FaultLineCrack.EDGE_MATERIAL)
	crack._on_context(_entry([_status(&"sunder", 4.0)]))
	crack._on_launch()
	for i in 20:
		crack._on_progress(float(i) / 19.0)
	crack._on_crit(2)
	crack._on_arrival()
	crack.clock.advance(crack.linger_seconds + crack.shatter_window + 0.1)
	assert_eq(_params(FaultLineCrack.SHARED_MATERIAL), shared_before,
		"a flight must not write the shared crack material (edge_width is idempotent)")
	assert_eq(_params(FaultLineCrack.EDGE_MATERIAL), edge_before,
		"and never the edge's own material")


# ------------------------------------------------------------- crack amount


func test_landed_stacks_sum_only_the_status_id_hits() -> void:
	var crack := _spawn()
	crack._on_context(_entry([
		_status(&"sunder", 3.0), _status(&"sunder", 2.0), _status(&"poison", 5.0)]))
	assert_eq(crack.crack_stacks, 5.0, "sunder 3 + sunder 2; poison is not the crack")


func test_an_entry_without_hits_leaves_the_crack_untouched() -> void:
	var crack := _spawn()
	crack.set_crack(7.0)
	crack._on_context({&"magnitude": 0.9})
	assert_eq(crack.crack_stacks, 7.0, "no hits field reads as no information")


func test_crack_fraction_clamps_to_unit_range() -> void:
	var crack := _spawn()
	crack.full_crack_stacks = 10.0
	crack.set_crack(5.0)
	assert_almost_eq(crack.crack_fraction(), 0.5, 0.0001)
	crack.set_crack(500.0)
	assert_eq(crack.crack_fraction(), 1.0)
	crack.set_crack(-3.0)
	assert_eq(crack.crack_fraction(), 0.0)


# ------------------------------------------------------------------ geometry


func test_bar_y_scale_is_the_width_channel() -> void:
	var crack := _spawn()
	crack.full_crack_stacks = 10.0
	crack.set_crack(5.0)
	var expected := lerpf(crack.min_width, crack.max_width, 0.5)
	assert_almost_eq(_bar(crack).scale.y, expected, 0.0001, "width = lerp(min, max, fraction)")
	crack._seal = 0.5
	crack._refresh_crack()
	assert_almost_eq(_bar(crack).scale.y, expected * 0.5, 0.0001, "scaled by the seal")


func test_context_with_origin_and_target_derives_world_endpoints_and_top_level() -> void:
	var crack := _spawn()
	assert_false(crack.top_level)
	var origin := SkillNode.new()
	origin.global_position = Vector2(15.0, 25.0)
	autofree(origin)
	var target := SkillNode.new()
	target.global_position = Vector2(415.0, 25.0)
	autofree(target)
	crack._on_context({&"origin": origin, &"target": target})
	assert_true(crack.top_level)
	assert_eq(crack.edge_origin, origin.global_position)
	assert_eq(crack.edge_target, target.global_position)


func test_context_without_endpoints_never_touches_top_level() -> void:
	var crack := _spawn()
	crack._on_context(_entry([_status(&"sunder", 1.0)]))
	assert_false(crack.top_level, "a sandbox stamps parent-space endpoints itself")


func test_a_degenerate_edge_draws_nothing() -> void:
	var crack := _spawn()
	crack.edge_target = crack.edge_origin
	crack._on_progress(1.0)
	assert_almost_eq(_bar(crack).scale.x, 0.0, 0.0001)


func test_it_draws_on_the_spell_vfx_layer() -> void:
	assert_eq(_spawn().z_index, ZLayers.SPELL_VFX)


# ------------------------------------------------------------------ finished


func test_no_linger_and_no_crit_finishes_after_one_frame() -> void:
	var crack := _spawn()
	crack.linger_seconds = 0.0
	watch_signals(crack)
	crack._on_arrival()
	await get_tree().process_frame
	assert_signal_emit_count(crack, "finished", 1)


func test_finished_waits_for_both_the_seal_and_the_shatter() -> void:
	var crack := _spawn()
	crack.linger_seconds = 0.5
	crack.shatter_window = 0.9
	crack.set_crack(5.0, 1)
	watch_signals(crack)
	crack._on_arrival()
	crack.clock.advance(0.6)
	await get_tree().process_frame
	assert_signal_not_emitted(crack, "finished", "the seal settled but the shatter has not")
	crack.clock.advance(0.5)
	await get_tree().process_frame
	assert_signal_emit_count(crack, "finished", 1, "exactly once, after BOTH settle")
	crack._on_arrival()
	await get_tree().process_frame
	assert_signal_emit_count(crack, "finished", 1, "a repeat arrival does not re-emit")


# -------------------------------------------------------------------- wiring


func test_fault_lines_coordinator_uses_the_crack_as_its_edge_visual() -> void:
	var coord = COORDINATOR.instantiate()
	autofree(coord)
	assert_eq(coord.edge_visual.resource_path, CRACK.resource_path)
