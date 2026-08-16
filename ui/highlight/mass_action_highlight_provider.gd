class_name MassActionHighlightProvider
extends HighlightProvider

## Highlight provider for a pending MassActionRequest confirmation. A pure
## view-state snapshot, rebuilt by HighlightController whenever the request
## changes (armed/cancelled/confirmed) — same shape as CoreMoveHighlightProvider.
##
## ALLOCATE: the SP-affordable prefix reads ALLOCATABLE, the unaffordable
## remainder (if the path was budget-truncated) reads PENDING_REMAINDER —
## visible but visually demoted, per the "show what you're leaving on the
## table" design. The route itself is chained PATH edges.
## DEALLOCATE: every node in the cascade reads HOSTILE_TARGET ("this goes
## away"); no route to draw.

var request: MassActionRequest = null
var graph: Graph = null


func configure(p_request: MassActionRequest, p_graph: Graph) -> void:
	request = p_request
	graph = p_graph


func get_node_role(node: SkillNode) -> HighlightRole:
	if request == null or node == null:
		return HighlightRole.NONE
	if request.verb == MassActionRequest.Verb.DEALLOCATE:
		return HighlightRole.HOSTILE_TARGET if request.nodes.has(node) else HighlightRole.NONE
	var idx := request.nodes.find(node)
	if idx <= 0:
		return HighlightRole.NONE
	return HighlightRole.ALLOCATABLE if idx <= request.affordable_count else HighlightRole.PENDING_REMAINDER


func get_range_visual() -> RangeVisual:
	if request == null or graph == null or request.verb != MassActionRequest.Verb.ALLOCATE:
		return null
	var rv := RangeVisual.new()
	var path := request.nodes
	if path.size() < 2:
		return rv
	var edges := graph.get_edges()
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		for e in edges:
			if (e.from == a and e.to == b) or (e.from == b and e.to == a):
				rv.edges.append(RangeVisual.EdgeEntry.new(e, 0, 0, HighlightRole.PATH))
				break
	return rv
