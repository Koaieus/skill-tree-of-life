extends GutTest
## v4 #321 D8: the 4 hand-authored landmark SkillNode scenes each carry a
## Keystone whose baked StatEffect grants the headline modifier.
const _WARD    := preload("res://entity/keystone/instances/mythic_ward_node.tscn")
const _FARSIGHT:= preload("res://entity/keystone/instances/farsight_node.tscn")
const _TITAN   := preload("res://entity/keystone/instances/titan_node.tscn")
const _ARCHMAGE:= preload("res://entity/keystone/instances/archmage_node.tscn")
func _check(scene: PackedScene, stat_id: StringName, op: int, value: float, label: String) -> void:
	var n: SkillNode = autofree(scene.instantiate()) as SkillNode
	add_child(n)
	assert_not_null(n.keystone, "%s: keystone should be set on the node" % label)
	assert_true(n.keystone.effects.size() >= 1, "%s: keystone should carry >=1 effect" % label)
	var fx = n.keystone.effects[0]
	assert_true(fx is StatEffect, "%s: effect[0] should be a StatEffect" % label)
	assert_true((fx as StatEffect).modifiers.size() >= 1, "%s: StatEffect should carry >=1 modifier" % label)
	var m = (fx as StatEffect).modifiers[0] as StatModifier
	assert_eq(m.stat_id, stat_id, "%s: stat_id" % label)
	assert_eq(int(m.operation), op, "%s: operation" % label)
	assert_almost_eq(float(m.value), value, 0.001, "%s: value" % label)
func test_mythic_ward_grants_minus_one_min_damage_taken() -> void:
	_check(_WARD, &"min_damage_taken", StatModifier.Operation.ADD_BASE, -1.0, "mythic_ward")
func test_farsight_grants_plus_100_vision_range() -> void:
	_check(_FARSIGHT, &"vision_range", StatModifier.Operation.ADD_BASE, 100.0, "farsight")
func test_titan_grants_x2_strength() -> void:
	_check(_TITAN, &"strength", StatModifier.Operation.MULTIPLY, 2.0, "titan")
func test_archmage_grants_x2_intelligence() -> void:
	_check(_ARCHMAGE, &"intelligence", StatModifier.Operation.MULTIPLY, 2.0, "archmage")
