@tool
class_name EntityNavigator
extends GraphMirror

## Per-entity owned-subgraph mirror. Only nodes where `owned_by == entity`
## enter the mirror — i.e. the entity's induced subgraph.
##
## Drives connectivity questions like "would deallocating this node island
## any of my other owned nodes from my core?"
## ([code]would_disconnect_from(node, core_location)[/code]). Combat code
## reads the inherited `astar` directly for path / reach queries on the
## owned territory.
##
## Mutation contract: ownership writes happen through [AllocationSystem],
## which calls [method GraphMirror.mirror_add] / [method GraphMirror.mirror_remove]
## on us. We don't subscribe to per-node `owner_changed` — programmatic
## `node.owned_by = X` outside the system would drift the mirror. Structural
## edge changes still come via graph signals so procgen / runtime topology
## edits stay in sync.

@export var entity: Entity

## Bumped on every structural change to this mirror — a node entering/leaving
## the owned subgraph, or an edge between two already-mirrored nodes. The cheap
## fingerprint [AuraDistanceCache] compares against its own cached generation
## to know whether a shared hop-distance walk is still valid (#626). Overriding
## the base's mutation points rather than listening to a signal keeps this to
## one integer write per real topology event, on the object that already knows
## about every one of them (see the mutation-contract doc above).
var topology_generation: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if entity == null:
		push_warning("EntityNavigator has no Entity reference")
		return
	if graph == null:
		push_warning("EntityNavigator has no Graph reference")
		return
	wire_to(graph)


func _exit_tree() -> void:
	AuraDistanceCache.forget_mirror(self)


func _should_mirror(node: SkillNode) -> bool:
	return node.owned_by == entity


func mirror_add(node: SkillNode) -> void:
	super.mirror_add(node)
	topology_generation += 1


func mirror_remove(node: SkillNode) -> void:
	super.mirror_remove(node)
	topology_generation += 1


func _on_edge_added(edge: Edge) -> void:
	super._on_edge_added(edge)
	topology_generation += 1


func _on_edge_removed(edge: Edge) -> void:
	super._on_edge_removed(edge)
	topology_generation += 1


## Does [param node] touch this territory from OUTSIDE it — not mirrored here,
## with at least one whole-board neighbour that is (#941)? The one "borders
## territory" question: the allocation gate ("can I grow onto this unowned
## node") and the AI's door rule ([method AiRecon.is_ai_target] /
## [method AiCombatScorer.score] — a capped entity may punch through ANY
## owner's node that walls it in) both read it.
##
## Adjacency, not degree: the question is membership in the neighbour set,
## so [method GraphMirror.neighbours_of] on the board [Navigator] is the right
## call and the degree rule does not apply. Ownership is answered by mirror
## membership, never `owned_by == entity`
## (.claude/rules/ownership-vocabulary.md) — so a shadow-world mirror answers
## for its own world.
func borders(node: SkillNode) -> bool:
	if node == null or graph == null or graph.navigator == null:
		return false
	if vertex_id(node) >= 0:
		return false
	for nb in graph.navigator.neighbours_of(node):
		if vertex_id(nb) >= 0:
			return true
	return false
