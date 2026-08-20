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
