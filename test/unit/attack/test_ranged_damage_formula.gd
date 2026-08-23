extends GutTest

## RangedDamageFormula.compute: pure per-shot damage read off the firing
## node's local `ranged_damage` stat. Same shape as test_mitigation.gd.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _owned_node() -> SkillNode:
	var ent := Entity.new()
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	autofree(ent)
	var node := _NODE_SCENE.instantiate()
	autofree(node)
	add_child(ent)
	add_child(node)
	node.owned_by = ent
	return node


func _set_ranged_damage(node: SkillNode, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"ranged_damage"
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func test_amount_reads_firing_nodes_ranged_damage() -> void:
	var firing := _owned_node()
	await get_tree().process_frame
	_set_ranged_damage(firing, 12.5)
	var target := _NODE_SCENE.instantiate() as SkillNode
	autofree(target)
	var hit := RangedDamageFormula.compute(null, firing, target)
	assert_almost_eq(hit.amount, 12.5, 0.001)


func test_hit_is_physical_typed() -> void:
	var firing := _owned_node()
	await get_tree().process_frame
	var target := _NODE_SCENE.instantiate() as SkillNode
	autofree(target)
	var hit := RangedDamageFormula.compute(null, firing, target)
	assert_eq(hit.type, DamageInstance.Type.PHYSICAL)


func test_hit_target_and_origin_are_set() -> void:
	var firing := _owned_node()
	await get_tree().process_frame
	var target := _NODE_SCENE.instantiate() as SkillNode
	autofree(target)
	var hit := RangedDamageFormula.compute(null, firing, target)
	assert_eq(hit.target, target)
	assert_eq(hit.origin, firing)


func test_null_firing_node_yields_zero_amount() -> void:
	var target := _NODE_SCENE.instantiate() as SkillNode
	autofree(target)
	var hit := RangedDamageFormula.compute(null, null, target)
	assert_almost_eq(hit.amount, 0.0, 0.001)
	assert_null(hit.origin)


# ── Land-time gate + live read (#503) ───────────────────────────────────

func test_land_on_reads_ranged_damage_live_not_frozen_at_resolve() -> void:
	var firing := _owned_node()
	var target := _owned_node()
	await get_tree().process_frame
	_set_ranged_damage(firing, 5.0)
	var hit := RangedDamageFormula.compute(null, firing, target)
	assert_almost_eq(hit.amount, 5.0, 0.001, "resolve-time snapshot, for preview/AI use")

	# Mid-volley: the firing node's ranged_damage changes AFTER resolve, before land.
	_set_ranged_damage(firing, 9.0)
	var hp_before := target.get_current_hp()
	hit.land_on(target.get_combat(), CombatWorld.live())
	assert_almost_eq(hp_before - target.get_current_hp(), 9.0, 0.001,
			"land_on must apply the LIVE ranged_damage, not the resolve-time snapshot")


func test_land_on_vetoes_and_marks_gated_when_target_no_longer_allocated() -> void:
	var firing := _owned_node()
	var target := _owned_node()
	await get_tree().process_frame
	var hit := RangedDamageFormula.compute(null, firing, target)
	target.owned_by = null  # e.g. force-deallocated by an earlier shot's kill
	var hp_before := target.get_current_hp()
	hit.land_on(target.get_combat(), CombatWorld.live())
	assert_almost_eq(target.get_current_hp(), hp_before, 0.001, "a vetoed shot applies no damage")
	assert_true(hit.gated)
	assert_eq(hit.target, target, "a vetoed shot is not re-aimed")


func test_land_on_vetoes_and_marks_gated_when_origin_no_longer_allocated() -> void:
	var firing := _owned_node()
	var target := _owned_node()
	await get_tree().process_frame
	var hit := RangedDamageFormula.compute(null, firing, target)
	firing.owned_by = null  # the firing leaf itself was islanded mid-volley
	var hp_before := target.get_current_hp()
	hit.land_on(target.get_combat(), CombatWorld.live())
	assert_almost_eq(target.get_current_hp(), hp_before, 0.001,
			"the firing node dying mid-volley must also veto the shot")
	assert_true(hit.gated)


func test_land_on_applies_normally_and_leaves_gated_false_when_ungated() -> void:
	var firing := _owned_node()
	var target := _owned_node()
	await get_tree().process_frame
	_set_ranged_damage(firing, 5.0)
	var hit := RangedDamageFormula.compute(null, firing, target)
	hit.land_on(target.get_combat(), CombatWorld.live())
	assert_false(hit.gated)
	assert_almost_eq(hit.effective_amount, 5.0, 0.001)


func test_compute_leaves_arrival_time_unset() -> void:
	# arrival_time is authored by RangedAttackPlan.resolve() from the shot's
	# RANK in the volley ramp (docs/domain/attack-timeline.md "The ranged
	# volley ramp") — compute() has no rank to work from, so it must not
	# guess one from distance/speed (the old model, which is exactly what let
	# allocation order leak into combat outcome). See test_ranged_attack_plan.gd
	# for the ramp's own arrival_time coverage.
	var target := _NODE_SCENE.instantiate() as SkillNode
	autofree(target)
	target.global_position = Vector2(1000, 0)
	var firing := _owned_node()
	firing.global_position = Vector2(0, 0)
	await get_tree().process_frame
	var hit := RangedDamageFormula.compute(null, firing, target)
	assert_almost_eq(hit.arrival_time, 0.0, 0.001)
