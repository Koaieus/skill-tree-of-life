extends GutTest

## The load a landing's head carries to the gather's go-off (#1799): a spell
## landing stamps its cast's [member LoadBag.detonate_load], a blade contact
## its piece's charges, an arrow stays at 0. Nothing reads it yet.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _EXPLOSIVE_ID := preload("res://identity/defs/explosive.tres")

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _spell_heads(detonate: int) -> Array[HitInstance]:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(FanAllSpread.new(), helper.owner_enemy(), helper.max_reducer(), {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	if detonate > 0:
		var row := AspectIntake.new()
		row.identity = _EXPLOSIVE_ID
		row.innate = detonate
		spell.intakes = [row] as Array[AspectIntake]
	var inf := Infusion.innate(spell)
	assert_eq(inf.detonate_load(spell), detonate, "fixture: the cast's detonation load")
	var n := graph.get_skill_nodes()
	return SpellResolver.resolve(spell, n[1], n[0], atk, graph, null, inf).hits


func _assert_spell(detonate: int) -> void:
	var heads := 0
	for h in _spell_heads(detonate):
		if h.is_head:
			heads += 1
			assert_eq(h.hit_load, detonate, "a spell landing's head carries the cast's detonate load")
		else:
			assert_eq(h.hit_load, 0, "only the head carries a load")
	assert_gt(heads, 0, "fixture: the landing has a head")


func test_a_spell_head_carries_its_detonate_load() -> void:
	_assert_spell(3)


func test_a_spell_without_a_detonate_load_stamps_zero() -> void:
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
	var hits: Array[HitInstance] = [di]
	gate.arm_blasts(ev, di, hits, CombatWorld.live(), [])
	return di


func test_a_blade_contact_carries_its_pieces_charges() -> void:
	assert_eq(_blade_contact(2).hit_load, 2)
	assert_eq(_blade_contact(5).hit_load, 5)


func test_a_blade_contact_on_a_plain_piece_carries_zero() -> void:
	assert_eq(_blade_contact(0).hit_load, 0)


func test_an_arrow_carries_no_load() -> void:
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], _f.target)
	var hits: Array[HitInstance] = [arrow]
	RangedDamageFormula.ride(arrow, hits)
	for h in hits:
		assert_eq(h.hit_load, 0, "an arrow landing never sets a load")
