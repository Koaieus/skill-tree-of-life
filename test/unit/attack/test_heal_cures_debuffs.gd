extends GutTest

## Healing and curing are orthogonal: [method HealInstance.land_on] never
## reaches the status slice, so a heal leaves every debuff's power unchanged.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Cured"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Heals crit too (HealInstance.land_on) — zero it so the exact-power
	# asserts below don't flake on the default board's 5% baseline.
	_entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


## Damages [member _node] for HALF its max hp (raw — mitigation may soak
## some of it) so a later heal always has room to land, without risking a
## depleted-node cascade that would `release_statuses()` out from under us.
func _open_a_heal_deficit() -> void:
	var combat := _node.get_combat()
	combat.take_damage(combat.get_max_hp() * 0.5, null)
	assert_lt(combat.get_current_hp(), combat.get_max_hp(),
		"fixture: the node must actually be short of full hp")


func _heal(amount: float) -> HealInstance:
	var h := HealInstance.new()
	h.amount = amount
	h.target = _node
	return h


func test_a_heal_leaves_every_debuffs_power_unchanged() -> void:
	_open_a_heal_deficit()
	var combat := _node.get_combat()
	combat.apply_status(load("res://effects/status/poison.tres") as StatusDef, 4.0)
	combat.apply_status(load("res://effects/status/curse.tres") as StatusDef, 4.0)
	var poison_before := combat.get_status_power(&"poison")
	var curse_before := combat.get_status_power(&"curse")
	assert_gt(poison_before, 0.0, "fixture: poison is on the node")
	assert_gt(curse_before, 0.0, "fixture: curse is on the node")

	var heal := _heal(50.0)
	OutcomeApplier.land_one(heal, CombatWorld.live())
	assert_gt(heal.effective_amount, 0.0, "fixture: the heal must have actually landed some hp")

	assert_almost_eq(combat.get_status_power(&"poison"), poison_before, 0.0001, "poison untouched")
	assert_almost_eq(combat.get_status_power(&"curse"), curse_before, 0.0001, "curse untouched")
