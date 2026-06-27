class_name CoreMoveHighlightProvider
extends HighlightProvider

## Highlight provider for core-move targeting (#21). A pure view-state snapshot
## the [HighlightController] (re)builds when the player picks their core or drags
## a landing preview: the core slot, the set of owned nodes reachable within the
## MP budget, and the current preview landing. Nodes get ORIGIN / REACHABLE /
## HOSTILE_TARGET rings; the induced edges of the reachable set get PATH edges.

## The core slot the move starts from.
var source: SkillNode = null
## { SkillNode: hops } reachable within budget (from AllocationSystem). Excludes source.
var reachable: Dictionary = {}
## Current click/drag landing preview (brightened), or null.
var target: SkillNode = null
## Graph, for enumerating the reachable induced edges in get_range_visual().
var graph: Graph = null


func configure(p_source: SkillNode, p_reachable: Dictionary, p_graph: Graph) -> void:
	source = p_source
	reachable = p_reachable
	graph = p_graph


## Update the preview landing during a click/drag and repaint. Source + reachable
## set are unchanged (the BFS only depends on the immobile source), so this is cheap.
func set_target(p_target: SkillNode) -> void:
	if target == p_target:
		return
	target = p_target
	state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null:
		return HighlightRole.NONE
	if node == source:
		return HighlightRole.ORIGIN
	if node == target and reachable.has(node):
		return HighlightRole.HOSTILE_TARGET
	if reachable.has(node):
		return HighlightRole.REACHABLE
	return HighlightRole.NONE


## Induced edges of (source ∪ reachable) tagged PATH, so the overlay paints the
## owned subgraph you can move through, not just the landing rings.
func get_range_visual() -> RangeVisual:
	if graph == null or source == null:
		return null
	var rv := RangeVisual.new()
	for e in graph.get_edges():
		if e.from == e.to or e.from == null or e.to == null:
			continue
		var a_in := e.from == source or reachable.has(e.from)
		var b_in := e.to == source or reachable.has(e.to)
		if a_in and b_in:
			rv.edges.append(RangeVisual.EdgeEntry.new(e, 0, 0, HighlightRole.PATH))
	return rv
