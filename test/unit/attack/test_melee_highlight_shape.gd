extends GutTest

## MeleeAttackPlan's indicator inputs: the pivot is order 0 and faces the
## blade's centroid; members count 1..n in blade order; everything else is -1.


const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _node(pos: Vector2) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(n)
	n.global_position = pos
	return n


func _plan() -> Dictionary:
	var plan := MeleeAttackPlan.new()
	var pivot := _node(Vector2.ZERO)
	var a := _node(Vector2(10, 0))
	var b := _node(Vector2(30, 40))
	var stray := _node(Vector2(-50, 5))
	plan.source = pivot
	plan.blade_nodes.append(a)
	plan.blade_nodes.append(b)
	return {"plan": plan, "pivot": pivot, "a": a, "b": b, "stray": stray}


func test_order_pivot_zero_members_in_blade_order_else_minus_one() -> void:
	var c := _plan()
	var plan: MeleeAttackPlan = c.plan
	assert_eq(plan.get_node_order(c.pivot), 0)
	assert_eq(plan.get_node_order(c.a), 1)
	assert_eq(plan.get_node_order(c.b), 2)
	assert_eq(plan.get_node_order(c.stray), -1)
	assert_eq(plan.get_node_order(null), -1)


func test_pivot_faces_blade_centroid() -> void:
	var c := _plan()
	var plan: MeleeAttackPlan = c.plan
	var want := Vector2(20, 20).normalized()
	assert_almost_eq(plan.get_node_facing(c.pivot), want, Vector2(0.0001, 0.0001))


func test_no_blade_or_non_pivot_faces_nowhere() -> void:
	var c := _plan()
	var plan: MeleeAttackPlan = c.plan
	assert_eq(plan.get_node_facing(c.stray), Vector2.ZERO)
	plan.blade_nodes.clear()
	assert_eq(plan.get_node_facing(c.pivot), Vector2.ZERO)
