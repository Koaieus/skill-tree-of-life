extends GutTest

## MagicAttackPlan: cost/reach/legality against a real Graph + Entity
## fixture. Chain Source - InRange - OutOfRange; a HopRangeFinder(max_hops=1)
## gates targeting reach, so InRange (1 hop) is a legal click target and
## OutOfRange (2 hops) is silently rejected — exercising the same
## Targeting.is_valid_target() path the click handler drives in play.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SPELL_TEST_HELPER := preload("res://test/unit/spell/spell_test_helper.gd")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _source: SkillNode
var _in_range_target: SkillNode
var _out_of_range_target: SkillNode
var _spell: SpellDef


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_source = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_in_range_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_out_of_range_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_source)
	_graph.add_skill_node(_in_range_target)
	_graph.add_skill_node(_out_of_range_target)
	_graph.add_edge(_source, _in_range_target)
	_graph.add_edge(_in_range_target, _out_of_range_target)  # 2 hops from source

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)

	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _source)
	_alloc.force_allocate(_hostile, _in_range_target)
	_alloc.force_allocate(_hostile, _out_of_range_target)

	autofree(_attacker)
	autofree(_hostile)

	var targeting := NodeTargeting.new()
	targeting.ownership_filter = SkillNode.Ownership.HOSTILE
	var finder := HopRangeFinder.new()
	finder.max_hops = 1
	targeting.range_finder = finder

	var h: RefCounted = _SPELL_TEST_HELPER.new()
	_spell = SpellDef.new()
	_spell.name = "TestBolt"
	_spell.mana_cost = 5
	_spell.min_degree = 0
	_spell.power = 1.0
	_spell.targeting = targeting
	_spell.propagation = h.make_config(h.fan_all(), h.owner_enemy(), h.sum_reducer(), {max_hops = 0})
	_spell.on_hit_effects = [DamageEffect.new()] as Array[OnHitEffect]


func _plan() -> MagicAttackPlan:
	var p := MagicAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	p.spell = _spell
	return p


# ── Reach (click-driven, real HopRangeFinder over the mirrored graph) ──────

func test_click_source_then_in_range_hostile_sets_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	assert_eq(p.source, _source)
	p._on_node_left_clicked(_in_range_target)
	assert_eq(p.target, _in_range_target)


func test_click_out_of_range_hostile_is_rejected() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	p._on_node_left_clicked(_out_of_range_target)
	assert_null(p.target)


func test_click_source_must_be_owned_by_attacker() -> void:
	var p := _plan()
	p._on_node_left_clicked(_in_range_target)  # owned by hostile
	assert_null(p.source)


# ── Legality ────────────────────────────────────────────────────────────

func test_validate_requires_source() -> void:
	var p := _plan()
	assert_has(p.validate(), &'No source selected')


func test_validate_requires_target() -> void:
	var p := _plan()
	p.source = _source
	assert_has(p.validate(), &'No target selected')


func test_validate_gates_on_min_degree() -> void:
	_spell.min_degree = 5
	var p := _plan()
	p.source = _source
	p.target = _in_range_target
	assert_has(p.validate(), &'Source node degree too low for spell')


func test_validate_passes_with_source_and_reachable_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	p._on_node_left_clicked(_in_range_target)
	assert_eq(p.validate(), [] as Array[String])
	assert_true(p.is_valid())


# ── Cost + resolution ────────────────────────────────────────────────────

func test_resolve_transfers_mana_cost_and_hits_the_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	p._on_node_left_clicked(_in_range_target)
	var outcome := p.resolve()
	assert_eq(outcome.mana_cost, 5)
	assert_eq(outcome.hits.size(), 1)
	assert_eq(outcome.hits[0].target, _in_range_target)


func test_resolve_on_invalid_plan_returns_default_outcome() -> void:
	var p := _plan()
	var outcome := p.resolve()
	assert_eq(outcome.mana_cost, 0)
	assert_true(outcome.hits.is_empty())
