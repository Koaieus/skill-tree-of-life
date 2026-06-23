class_name SpellTestHelper
extends RefCounted

## Lightweight builders for spell-resolver tests. Construct a Graph + a few
## SkillNodes + Entities + a SpellDef, all in-memory — no scene files driving
## test layout, no .tres fixtures per case. Resolver behaviour is pure
## w.r.t. world state (damage is deferred to VFX), so these fixtures are
## enough to assert on `AttackOutcome.hits`.
##
## Usage pattern:
## ```
## var h := SpellTestHelper.new()
## var graph := h.make_graph([[0,1],[1,2],[2,3]], test)   # line of 4
## var attacker := h.make_entity(graph, "A", Color.RED)
## var defender := h.make_entity(graph, "D", Color.BLUE)
## h.give_big_hp(defender)                                  # avoid mid-cast death noise
## h.assign_owner(graph, defender, [1, 2, 3])
## h.assign_owner(graph, attacker, [0])
## var spell := h.make_spell(AllNeighboursPropagation.new(), [DamageEffect.new()], 10.0)
## var out := SpellResolver.resolve(spell, graph.get_skill_nodes()[1], graph.get_skill_nodes()[0], attacker, graph)
## ```

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")


## Construct a Graph with `node_count` SkillNodes (auto-derived from the
## adjacency) and one Edge per pair. `gut` is the GutTest invoking this —
## used to add the graph to the test's tree so SkillNode._ready can run.
## Returns the graph; nodes are accessible via `graph.get_skill_nodes()`
## in index order.
func make_graph(adjacency: Array, gut: GutTest) -> Graph:
	var node_count: int = 0
	for pair in adjacency:
		node_count = max(node_count, int(pair[0]) + 1, int(pair[1]) + 1)
	var graph := Graph.new()
	graph.name = "TestGraph"
	graph.skill_nodes_container = Node2D.new()
	graph.skill_nodes_container.name = "Nodes"
	graph.add_child(graph.skill_nodes_container)
	graph.edges_container = Node2D.new()
	graph.edges_container.name = "Edges"
	graph.add_child(graph.edges_container)
	gut.add_child_autofree(graph)
	for i in node_count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		graph.skill_nodes_container.add_child(sn)
	for pair in adjacency:
		var a: SkillNode = graph.get_skill_nodes()[int(pair[0])]
		var b: SkillNode = graph.get_skill_nodes()[int(pair[1])]
		var e := Edge.new()
		e.from = a
		e.to = b
		graph.edges_container.add_child(e)
	return graph


## Make an Entity, parented under the graph so `_find_graph` succeeds and
## `EntityNavigator` wires up. Each entity gets its own duplicated stat
## board (intrinsic-modifier instances mustn't be shared across entities).
func make_entity(graph: Graph, display_name: String, color: Color = Color.WHITE) -> Entity:
	var ent := Entity.new()
	ent.display_name = display_name
	ent.color = color
	ent.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	graph.add_child(ent)
	return ent


## Pump node_health up so per-node HP is effectively infinite for tests
## that only care about *what was hit*, not death-cascades. Mutates the
## entity's own copy of node_health base_value — won't bleed into other
## entities.
func give_big_hp(entity: Entity, value: float = 9999.0) -> void:
	if entity == null or entity.stat_board == null:
		return
	var nh: Stat = entity.stat_board.get_stat(&"node_health")
	if nh != null:
		nh.base_value = value


## Assign `owned_by` directly on every node at `indices`. Skips
## AllocationSystem (we're testing resolver semantics, not allocation
## rules). Setting `owned_by` fires the node's own bindings, so HP refills
## automatically to whatever the entity's node_health resolves to.
func assign_owner(graph: Graph, entity: Entity, indices: Array) -> void:
	var nodes := graph.get_skill_nodes()
	for i in indices:
		nodes[int(i)].owned_by = entity


## Build a SpellDef in-memory. The targeting / VFX / mana fields are left
## defaulted because SpellResolver doesn't read them; tests focusing on
## resolver shape don't need them.
func make_spell(prop: SpellPropagation, on_hits: Array[OnHitEffect], base_damage: float = 10.0) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "TestSpell"
	spell.base_damage = base_damage
	spell.propagation = prop
	spell.on_hit_effects = on_hits
	return spell


## Group an outcome's hits by target node — keeps assertions readable
## ("node 3 was hit twice for [10, 5]") versus walking the flat array.
func hits_by_node(outcome: AttackOutcome) -> Dictionary:
	var out: Dictionary = {}
	for hit in outcome.hits:
		if not out.has(hit.target):
			out[hit.target] = []
		out[hit.target].append(hit)
	return out


## Sum the damage landed on `node` across an outcome's hits.
func total_damage_on(outcome: AttackOutcome, node: SkillNode) -> float:
	var total: float = 0.0
	for hit in outcome.hits:
		if hit.target == node:
			total += hit.amount
	return total
