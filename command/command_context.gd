class_name CommandContext
extends RefCounted

## The system bundle a [CommandHandler] mutates through (#999) — what
## [CommandApplier] used to reach off its own exports. Built by the applier per
## drained command, so a handler never holds a reference to anything that
## outlives the call: handlers are shared, stateless, one instance per verb in
## [CommandRegistry].

var graph: Graph
var allocation_system: AllocationSystem
var battle_system: BattleSystem
var turn_manager: TurnManager
## The outstanding-loot-pick book, for [PickLootCommand] (#522).
var loot_pick_registry: LootPickRegistry
## For the one verb whose apply waits on a clock ([MoveCoreCommand]'s hop
## beat) — a [RefCounted] handler has no `get_tree()` of its own.
var tree: SceneTree


func resolve_actor(entity_id: int) -> Entity:
	return graph.get_by_entity_id(entity_id) if graph != null else null


func resolve_node(id: int) -> SkillNode:
	return graph.get_by_stable_id(id) if graph != null else null


## Ids -> live nodes, dropping any that no longer resolve. A dropped node is a
## node that left the graph between submission and application; the gated verb
## behind this is what decides whether the remainder is still legal.
func resolve_nodes(ids: Array[int]) -> Array[SkillNode]:
	var nodes: Array[SkillNode] = []
	for id in ids:
		var node := resolve_node(id)
		if node != null:
			nodes.append(node)
	return nodes
