extends GutTest

## One [StackTerm], two readers: an [AspectIntake]'s `stack_terms` ride its PLANT
## rider out of [method Infusion.riders] and land as extra stacks, and an
## [AddStackTermDamageEffect] adds the same term's value to the payload damage —
## both read against the cast's world, so a shadow resolve sees earlier sunder.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SUNDER := preload("res://effects/status/sunder.tres")

const _RATIO := 0.25
const _ARMOR := 12.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _blade: SkillNode
var _target: SkillNode


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_alloc = TestWorld.around(_graph).allocator()
	_attacker = _entity("Attacker")
	_defender = _entity("Defender")
	_blade = _node()
	_target = _node()
	var core := _node()
	await get_tree().process_frame
	_alloc.force_allocate(_attacker, _blade)
	_attacker.core_location = _blade
	_alloc.force_allocate(_defender, core)
	_alloc.force_allocate(_defender, _target)
	_defender.core_location = core


func _entity(display_name: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = display_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func _node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	return n


func _armor(world: CombatWorld = CombatWorld.live()) -> float:
	return float(world.combat_for(_target).get_local_value(&"armor"))


func _set_armor(value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - _armor()
	_target.add_local_modifier(m)
	assert_almost_eq(_armor(), value, 0.001, "arranged armor")


func _share() -> DefenderStatShare:
	var t := DefenderStatShare.new()
	t.stat_id = &"armor"
	t.ratio = _RATIO
	return t


func _sunder_spell(innate: int, terms: Array[StackTerm]) -> SpellDef:
	var row := AspectIntake.new()
	row.identity = _SUNDER.identity
	row.innate = innate
	row.face = AspectIntake.Face.PLANT
	row.stack_terms = terms
	var spell := SpellDef.new()
	spell.intakes = [row] as Array[AspectIntake]
	return spell


func _sunder_rider(spell: SpellDef) -> ApplyStatusEffect:
	for r in Infusion.for_cast(spell, {}).riders(spell):
		var a := r as ApplyStatusEffect
		if a != null and a.def != null and a.def.identity == _SUNDER.identity:
			return a
	return null


## The rider's landed power on [member _target], read by [member _blade].
func _land_rider(rider: ApplyStatusEffect, world: CombatWorld = CombatWorld.live()) -> float:
	var landing := HitLanding.new()
	landing.attacker = _attacker
	landing.read_node = _blade
	landing.target = _target
	rider.apply(landing)
	var s := landing.hits[0] as StatusInstance
	s.land_on(world.combat_for(_target), world)
	return s.power


## Payload damage after one [AddStackTermDamageEffect] landing on [member _target].
func _damage_after(damage: float, terms: Array[StackTerm], world: CombatWorld = CombatWorld.live()) -> float:
	var p := CastSpell.blank()
	p.damage = damage
	p.source = _blade
	p.current_node = _target
	p.graph = _graph
	var cast := PropagationContext.new()
	cast.graph = _graph
	cast.world = world
	var effect := AddStackTermDamageEffect.new()
	effect.stack_terms = terms
	effect.apply(LandingContext.for_test(p, _target, cast))
	return p.damage


# ── the intake's rider ─────────────────────────────────────────────────────


func test_riders_carry_the_intakes_stack_terms() -> void:
	var t := _share()
	var rider := _sunder_rider(_sunder_spell(4, [t] as Array[StackTerm]))
	assert_not_null(rider, "a PLANT sunder row emits a rider")
	assert_eq(rider.stack_terms, [t] as Array[StackTerm], "the row's terms ride along")


func test_the_carried_term_lands_a_share_of_armor_as_extra_stacks() -> void:
	_set_armor(_ARMOR)
	var shadow := CombatWorld.shadow()
	var plain := _land_rider(_sunder_rider(_sunder_spell(4, [] as Array[StackTerm])), shadow)
	var termed := _land_rider(_sunder_rider(_sunder_spell(4, [_share()] as Array[StackTerm])),
			CombatWorld.shadow())
	assert_almost_eq(termed - plain, _RATIO * _ARMOR, 0.5, "the term adds ratio × armor stacks")
	assert_gt(termed, plain, "the term adds stacks")


func test_a_row_without_terms_emits_a_rider_without_terms() -> void:
	var rider := _sunder_rider(_sunder_spell(4, [] as Array[StackTerm]))
	assert_eq(rider.stack_terms.size(), 0)


# ── the damage reader ──────────────────────────────────────────────────────


func test_the_damage_rises_by_the_terms_share_of_armor() -> void:
	_set_armor(_ARMOR)
	var base := 10.0
	assert_almost_eq(_damage_after(base, [_share()] as Array[StackTerm]) - base, _RATIO * _ARMOR, 0.001,
			"damage + ratio × armor")


func test_no_terms_leave_the_damage_alone() -> void:
	_set_armor(_ARMOR)
	assert_eq(_damage_after(10.0, [] as Array[StackTerm]), 10.0)


func test_negative_armor_adds_no_damage() -> void:
	_set_armor(-4.0)
	assert_eq(_damage_after(10.0, [_share()] as Array[StackTerm]), 10.0, "the term clamps at 0")


func test_the_damage_reads_the_shadow_worlds_lowered_armor() -> void:
	_set_armor(_ARMOR)
	var shadow := CombatWorld.shadow()
	var sunder := ApplyStatusEffect.new()
	sunder.def = _SUNDER
	sunder.power = 4.0
	_land_rider(sunder, shadow)
	var lowered := _armor(shadow)
	assert_lt(lowered, _ARMOR, "the earlier contact's sunder broke the shadow")
	assert_almost_eq(_damage_after(10.0, [_share()] as Array[StackTerm], shadow) - 10.0, _RATIO * lowered,
			0.001, "the damage reads the shadow's armor")
	assert_almost_eq(_armor(), _ARMOR, 0.001, "the live world is untouched")
