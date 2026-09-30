extends GutTest

## The AttackPlan domain verbs — set_pivot / clear_pivot / toggle_member
## (melee) and set_target (ranged, magic). Each verb builds the expected plan
## state, emits one state_changed per change, and refuses illegal inputs,
## returning whether it changed anything. The clicks that drive them are the
## armed stack's (test_click_grammar.gd).
##
## Board: Pivot - Joint - Tip owned by the attacker; Hostile adjacent to Tip;
## Far adjacent to Hostile only (2 hops from any owned node); Loose unowned.
## Tip is the only owned leaf in ranged reach of Hostile.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPELL_TEST_HELPER := preload("res://test/unit/spell/spell_test_helper.gd")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _pivot: SkillNode
var _joint: SkillNode
var _tip: SkillNode
var _enemy: SkillNode
var _far: SkillNode
var _loose: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = pos
	_graph.add_skill_node(sn)
	return sn


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_pivot = _spawn("Pivot", Vector2(0, 0))
	_joint = _spawn("Joint", Vector2(200, 0))
	_tip = _spawn("Tip", Vector2(400, 0))
	_enemy = _spawn("Hostile", Vector2(450, 0))
	_far = _spawn("Far", Vector2(900, 0))
	_loose = _spawn("Loose", Vector2(0, 600))
	_graph.add_edge(_pivot, _joint)
	_graph.add_edge(_joint, _tip)
	_graph.add_edge(_tip, _enemy)
	_graph.add_edge(_enemy, _far)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 20)
	_graph.add_child(_attacker)
	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	for n in [_pivot, _joint, _tip]:
		_alloc.force_allocate(_attacker, n)
	_alloc.force_allocate(_hostile, _enemy)
	_alloc.force_allocate(_hostile, _far)
	autofree(_attacker)
	autofree(_hostile)

	for n in [_pivot, _tip]:
		_set_stat(n, &"range", 100.0)  # only Tip (50px away) reaches Hostile
		_set_stat(n, &"max_shots_per_leaf", 1.0)


# ── Melee ─────────────────────────────────────────────────────────────────

func _melee(budget: float = 3.0) -> MeleeAttackPlan:
	_attacker.stat_board.blade_size.base_value = budget
	var plan: MeleeAttackPlan = autofree(MeleeAttackPlan.new())
	plan.attacker = _attacker
	return plan


func _assert_melee(verb: MeleeAttackPlan, pivot: SkillNode, members: Array[SkillNode]) -> void:
	assert_eq(verb.source, pivot, "the expected pivot")
	assert_eq(verb.blade_nodes, members, "the expected members, in order")


func test_set_pivot_arms_the_pivot() -> void:
	var verb := _melee()
	watch_signals(verb)
	assert_true(verb.set_pivot(_pivot), "arming a pivot changes state")
	assert_signal_emit_count(verb, "state_changed", 1)
	_assert_melee(verb, _pivot, [])


func test_toggle_member_mass_selects_a_far_member() -> void:
	var verb := _melee()
	verb.set_pivot(_pivot)
	watch_signals(verb)
	assert_true(verb.toggle_member(_tip), "a far member pulls its path in")
	assert_signal_emit_count(verb, "state_changed", 1)
	_assert_melee(verb, _pivot, [_joint, _tip])


func test_toggle_member_deselects_with_its_cascade() -> void:
	var verb := _melee()
	verb.set_pivot(_pivot)
	verb.toggle_member(_joint)
	verb.toggle_member(_tip)
	assert_true(verb.toggle_member(_joint), "a selected member toggles off")
	assert_true(verb.blade_nodes.is_empty(), "the islanded tip goes with it")
	_assert_melee(verb, _pivot, [])


func test_clear_pivot_empties_the_plan_once() -> void:
	var verb := _melee()
	verb.set_pivot(_pivot)
	verb.toggle_member(_joint)
	watch_signals(verb)
	assert_true(verb.clear_pivot())
	assert_null(verb.source)
	assert_true(verb.blade_nodes.is_empty())
	assert_false(verb.clear_pivot(), "nothing left to clear")
	assert_signal_emit_count(verb, "state_changed", 1)


func test_set_pivot_refuses_a_node_the_attacker_does_not_own() -> void:
	var verb := _melee()
	watch_signals(verb)
	assert_false(verb.set_pivot(_loose), "unowned")
	assert_false(verb.set_pivot(_enemy), "hostile")
	assert_null(verb.source)
	assert_signal_emit_count(verb, "state_changed", 0)


func test_toggle_member_refuses_an_over_budget_path() -> void:
	var verb := _melee(1.0)
	verb.set_pivot(_pivot)
	assert_false(verb.toggle_member(_tip), "joint + tip overrun a budget of one")
	assert_true(verb.blade_nodes.is_empty(), "no partial selection")
	_assert_melee(verb, _pivot, [])


func test_toggle_member_refuses_without_a_pivot_or_path() -> void:
	var verb := _melee()
	assert_false(verb.toggle_member(_joint), "no pivot armed yet")
	verb.set_pivot(_pivot)
	watch_signals(verb)
	assert_false(verb.toggle_member(_enemy), "not the attacker's node")
	assert_false(verb.toggle_member(_loose), "unowned, no owned path to it")
	assert_signal_emit_count(verb, "state_changed", 0)


## The self-click "never mind" pop is click grammar, not a verb: the pivot is
## never a member, so toggling it is refused and the pivot stays armed.
func test_toggle_member_on_the_pivot_is_refused_not_popped() -> void:
	var verb := _melee()
	verb.set_pivot(_pivot)
	assert_false(verb.toggle_member(_pivot))
	assert_eq(verb.source, _pivot, "still armed")
	assert_false(verb.blade_nodes.has(_pivot), "the pivot never becomes a member")


# ── Ranged ────────────────────────────────────────────────────────────────

func _ranged() -> RangedAttackPlan:
	var plan: RangedAttackPlan = autofree(RangedAttackPlan.new())
	plan.attacker = _attacker
	return plan


func test_ranged_set_target_aims_the_volley() -> void:
	var verb := _ranged()
	watch_signals(verb)
	assert_true(verb.set_target(_enemy))
	assert_false(verb.set_target(_enemy), "re-targeting the same node changes nothing")
	assert_signal_emit_count(verb, "state_changed", 1)
	assert_eq(verb.target, _enemy)
	assert_true(verb.is_valid(), "fixture sanity: Tip reaches Hostile")


func test_ranged_set_target_refuses_a_non_hostile_node() -> void:
	var verb := _ranged()
	watch_signals(verb)
	assert_false(verb.set_target(_tip), "own node")
	assert_false(verb.set_target(_loose), "neutral node")
	assert_false(verb.set_target(null))
	assert_null(verb.target)
	assert_signal_emit_count(verb, "state_changed", 0)


# ── Magic ─────────────────────────────────────────────────────────────────

func _magic() -> MagicAttackPlan:
	var targeting := NodeTargeting.new()
	targeting.ownership_filter = SkillNode.Ownership.HOSTILE
	var finder := HopRangeFinder.new()
	finder.max_hops = 1
	targeting.range_finder = finder
	var h: RefCounted = _SPELL_TEST_HELPER.new()
	var spell := SpellDef.new()
	spell.name = "TestBolt"
	spell.mana_cost = 5
	spell.min_degree = 0
	spell.power = 1.0
	spell.targeting = targeting
	spell.propagation = h.make_config(h.fan_all(), h.owner_enemy(), h.sum_reducer(), {max_hops = 0})
	spell.on_hit_effects = [DamageEffect.new()] as Array[OnHitEffect]
	var plan := MagicAttackPlan.new()
	autofree(plan)
	plan.attacker = _attacker
	plan.spell = spell
	return plan


func test_magic_set_target_stamps_the_source() -> void:
	var verb := _magic()
	watch_signals(verb)
	assert_true(verb.set_target(_enemy))
	assert_false(verb.set_target(_enemy), "same pick again changes nothing")
	assert_signal_emit_count(verb, "state_changed", 1)
	assert_eq(verb.target, _enemy)
	assert_eq(verb.source, _tip, "the caster comes from the union")
	assert_true(verb.is_valid(), "fixture sanity: Tip casts on Hostile")


func test_magic_set_target_refuses_out_of_range_and_own_nodes() -> void:
	var verb := _magic()
	watch_signals(verb)
	assert_false(verb.set_target(_far), "two hops out of a one-hop spell")
	assert_false(verb.set_target(_joint), "own node is not a hostile target")
	assert_null(verb.target)
	assert_null(verb.source, "a refused pick stamps no source")
	assert_signal_emit_count(verb, "state_changed", 0)
