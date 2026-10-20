extends GutTest

## A status rider's [StackTerm]s add to the folded `stacks_per_hit` at land —
## before crit, `stack_scale`, rounding and Greed — read against the world the
## status lands in. [DefenderStatShare] is the first: a share of the receiving
## node's live stat, gated on the read node's allocation level.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _SUNDER := preload("res://effects/status/sunder.tres")
const _GREED := preload("res://effects/status/greed.tres")

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
	_blade.stake_level = 8


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


## Moves the target's live armor to exactly [param value] with a node-local
## ADD_BASE, whatever the board starts at.
func _set_armor(value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - _armor()
	_target.add_local_modifier(m)
	assert_almost_eq(_armor(), value, 0.001, "arranged armor")


func _share(unlock: int = 1) -> DefenderStatShare:
	var t := DefenderStatShare.new()
	t.stat_id = &"armor"
	t.ratio = 0.25
	t.unlock_level = unlock
	return t


## One landing of [param def] at authored [param power] through
## [ApplyStatusEffect] carrying [param terms], read by the blade.
func _rider(def: StatusDef, power: float, terms: Array[StackTerm]) -> StatusInstance:
	var landing := HitLanding.new()
	landing.attacker = _attacker
	landing.read_node = _blade
	landing.target = _target
	var effect := ApplyStatusEffect.new()
	effect.def = def
	effect.power = power
	effect.stack_terms = terms
	effect.apply(landing)
	return landing.hits[0] as StatusInstance


func _land(s: StatusInstance, world: CombatWorld = CombatWorld.live()) -> float:
	s.land_on(world.combat_for(_target), world)
	return s.power


func _poison(terms: Array[StackTerm]) -> StatusInstance:
	return _rider(_POISON, 2.0, terms)


func test_the_rider_copies_its_terms() -> void:
	var t := _share()
	assert_eq(_poison([t] as Array[StackTerm]).stack_terms, [t] as Array[StackTerm])


func test_a_quarter_of_twelve_armor_adds_three() -> void:
	_set_armor(12.0)
	assert_eq(_land(_poison([_share()] as Array[StackTerm])), 5.0, "2 + 12 × 0.25")


func test_negative_armor_adds_nothing() -> void:
	_set_armor(-4.0)
	assert_eq(_land(_poison([_share()] as Array[StackTerm])), 2.0, "a term is clamped at 0")


func test_the_term_waits_for_the_read_nodes_level() -> void:
	_set_armor(12.0)
	_blade.allocation_level = 2
	assert_eq(_land(_poison([_share(3)] as Array[StackTerm])), 2.0, "2/X is below the gate")
	_blade.allocation_level = 3
	assert_eq(_land(_poison([_share(3)] as Array[StackTerm])), 5.0, "3/X opens it")


func test_a_crit_doubles_the_whole_sum() -> void:
	_set_armor(12.0)
	var s := _poison([_share()] as Array[StackTerm])
	s.crit_multiplier = 2.0
	assert_eq(_land(s), 10.0, "(2 + 3) × 2")


func test_greed_doubles_the_whole_sum() -> void:
	_set_armor(12.0)
	_target.get_combat().apply_status(_GREED, 1.0)
	assert_eq(_land(_poison([_share()] as Array[StackTerm])), 10.0, "(2 + 3) × 2")


func test_no_terms_change_nothing() -> void:
	_set_armor(12.0)
	assert_eq(_land(_poison([] as Array[StackTerm])), 2.0)


func test_a_shadow_landing_reads_the_shadow_hosts_armor() -> void:
	_set_armor(12.0)
	var shadow := CombatWorld.shadow()
	_land(_rider(_SUNDER, 4.0, [] as Array[StackTerm]), shadow)
	assert_almost_eq(_armor(shadow), 8.0, 0.001, "the earlier contact's sunder broke the shadow")
	assert_eq(_land(_poison([_share()] as Array[StackTerm]), shadow), 4.0, "2 + 8 × 0.25")
	assert_almost_eq(_armor(), 12.0, 0.001, "the live world is untouched until replay")
	assert_eq(_land(_poison([_share()] as Array[StackTerm])), 5.0, "the live host still reads 12")


func test_a_resolved_power_lands_as_recorded() -> void:
	_set_armor(12.0)
	var s := _poison([_share()] as Array[StackTerm])
	s.power = 4.0
	s.power_resolved = true
	assert_eq(_land(s), 4.0, "a replay never re-evaluates a term")


func test_an_entity_host_gets_no_term() -> void:
	_set_armor(12.0)
	var s := _poison([_share()] as Array[StackTerm])
	s.host_kind = StatusInstance.HostKind.ENTITY
	s.power_resolved = false
	assert_eq(_land(s), 2.0, "a status on a core reads no node stat")


# describe(): mirrors LevelGatedModifier's readout.
func test_describe_off_a_carrier_names_the_gate() -> void:
	assert_eq(_share(3).describe(), "+25% of target armor at 3/X")


func test_describe_below_the_gate_is_dormant() -> void:
	_blade.allocation_level = 2
	assert_eq(_share(3).describe(_blade), "")


func test_describe_at_the_gate_is_the_plain_value() -> void:
	_blade.allocation_level = 3
	assert_eq(_share(3).describe(_blade), "+25% of target armor")


func test_the_rider_description_carries_the_term_line() -> void:
	var effect := ApplyStatusEffect.new()
	effect.def = _POISON
	effect.power = 2.0
	effect.stack_terms = [_share(3)] as Array[StackTerm]
	assert_eq(effect.get_description(), "Applies Poison (2 per hit, +25% of target armor at 3/X).")
	_blade.allocation_level = 2
	assert_false(effect.get_description(null, null, _blade).contains("target armor"), "dormant: no line")
