extends GutTest

## NodeTargeting.valid_targets() over a real mixed-owner graph — the
## enumerated candidate SET (#357), complementing test_node_targeting.gd's
## per-candidate is_valid_target() coverage. Explicitly asserts the negative
## case: hostile targeting must not return allied/own nodes and vice versa.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _attacker: Entity
var _ally: Entity
var _hostile: Entity
var _mine_node: SkillNode
var _ally_node: SkillNode
var _hostile_node: SkillNode
var _neutral_node: SkillNode
var _source: SkillNode
var _plan: RangedAttackPlan


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_mine_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_ally_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_hostile_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_neutral_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_source = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_mine_node)
	_graph.add_skill_node(_ally_node)
	_graph.add_skill_node(_hostile_node)
	_graph.add_skill_node(_neutral_node)
	_graph.add_skill_node(_source)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_ally = Entity.new()
	_ally.faction = _PLAYER_FACTION
	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_graph.add_child(_attacker)
	_graph.add_child(_ally)
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_mine_node.owned_by = _attacker
	_ally_node.owned_by = _ally
	_hostile_node.owned_by = _hostile
	_source.owned_by = _attacker

	_plan = RangedAttackPlan.new()
	autofree(_plan)
	_plan.attacker = _attacker


func _targeting(filter: int) -> NodeTargeting:
	var t := NodeTargeting.new()
	t.ownership_filter = filter
	return t


func test_hostile_targeting_candidate_set_excludes_allied_and_own_nodes() -> void:
	var t := _targeting(SkillNode.Ownership.HOSTILE)
	var candidates := t.valid_targets(_plan, _source)
	assert_true(candidates.has(_hostile_node))
	assert_false(candidates.has(_mine_node),
			"hostile targeting must not return the attacker's own node")
	assert_false(candidates.has(_ally_node),
			"hostile targeting must not return an allied node")
	assert_false(candidates.has(_neutral_node))


func test_allied_targeting_candidate_set_excludes_hostile_nodes() -> void:
	# Friendly:6 = Mine(2) | Ally(4) — the allied-inclusive filter a heal spell uses.
	var t := _targeting(SkillNode.Ownership.MINE | SkillNode.Ownership.ALLY)
	var candidates := t.valid_targets(_plan, _source)
	assert_true(candidates.has(_mine_node))
	assert_true(candidates.has(_ally_node))
	assert_false(candidates.has(_hostile_node),
			"allied targeting must not return a hostile node")
	assert_false(candidates.has(_neutral_node))
