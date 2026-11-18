extends GutTest

## The load a landing's head carries ([member HitInstance.hit_load]): a blade
## contact its piece's charges; a spell landing (a Catalyst row plants, never
## loads) and an arrow stay at 0.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _POISON := preload("res://effects/status/poison.tres")
const _CATALYST_ID := preload("res://identity/defs/catalyst.tres")

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _poison_rider() -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = _POISON
	return e


func _spell_heads(catalyst: int) -> Array[HitInstance]:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(FanAllSpread.new(), helper.owner_enemy(), helper.max_reducer(), {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new(), _poison_rider()], 10.0)
	if catalyst > 0:
		var row := AspectIntake.new()
		row.identity = _CATALYST_ID
		row.innate = catalyst
		spell.intakes = [row] as Array[AspectIntake]
	var inf := Infusion.innate(spell)
	assert_eq(inf.riders(spell).size(), 1 if catalyst > 0 else 0, "fixture: a Catalyst row plants a rider")
	var n := graph.get_skill_nodes()
	return SpellResolver.resolve(spell, n[1], n[0], atk, graph, null, inf).hits


func _assert_spell(catalyst: int) -> void:
	var heads := 0
	var riders := 0
	for h in _spell_heads(catalyst):
		if h.is_head:
			heads += 1
		else:
			riders += 1
		assert_eq(h.hit_load, 0, "a spell landing never sets a load")
	assert_gt(heads, 0, "fixture: the landing has a head")
	assert_gt(riders, 0, "fixture: the span holds a non-head hit")


func test_a_catalyst_infused_spell_head_carries_no_load() -> void:
	_assert_spell(3)


func test_a_spell_without_catalyst_stamps_zero() -> void:
	_assert_spell(0)


func _blade_contact(charges: int) -> HitInstance:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	s.vertex_node[0] = _f.hub
	s.vertex_node[1] = _f.leaves[0]
	s.vertex_charges[1] = charges
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var ev := BladeHitEvent.new(0.5, 1, -1, _f.target)
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = _f.target
	di.attacker = _f.attacker
	gate.stamp_load(ev, di)
	return di


func test_a_blade_contact_carries_its_pieces_charges() -> void:
	assert_eq(_blade_contact(2).hit_load, 2)
	assert_eq(_blade_contact(5).hit_load, 5)


func test_an_arrow_carries_no_load() -> void:
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], _f.target)
	var hits: Array[HitInstance] = [arrow]
	RangedDamageFormula.ride(arrow, hits)
	assert_true(arrow.is_head, "fixture: the arrow is its landing's head")
	for h in hits:
		assert_eq(h.hit_load, 0, "an arrow landing never sets a load")
