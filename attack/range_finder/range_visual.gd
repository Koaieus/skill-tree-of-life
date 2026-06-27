class_name RangeVisual
extends RefCounted

## Data payload returned by [method RangeFinder.get_visual]. Pure description
## of what reach looks like — the overlay decides how to render. Subclasses of
## RangeFinder fill whichever fields fit their reach model:
##
## - Euclidean reach → one [member rings] entry at source with the radius.
## - Hop-based reach → [member edges] entries for each edge the BFS traversed,
##   each tagged with [code]hops_remaining[/code] so the renderer can fade or
##   thin the visualization as reach runs out.
##
## Decoupling rationale: the finder owns "what's in range" (model); the visual
## scenes own "how it looks" (view); the overlay glues them. Adding a new
## reach model (line-of-sight, owned-territory, cone) means a new finder +
## maybe a new scene — overlay code stays put.

class Ring:
	var position: Vector2
	var radius: float

	func _init(p_position: Vector2 = Vector2.ZERO, p_radius: float = 0.0) -> void:
		position = p_position
		radius = p_radius


class EdgeEntry:
	var edge: Edge
	var hops_remaining: int
	var max_hops: int
	## Optional semantic role ([enum HighlightProvider.HighlightRole]) so the
	## overlay can colour the edge by meaning (PATH = core-move reach, etc.).
	## Default NONE → overlay keeps the finder's stock golden range look.
	var role: int = HighlightProvider.HighlightRole.NONE

	func _init(p_edge: Edge = null, p_hops_remaining: int = 0, p_max_hops: int = 0,
			p_role: int = HighlightProvider.HighlightRole.NONE) -> void:
		edge = p_edge
		hops_remaining = p_hops_remaining
		max_hops = p_max_hops
		role = p_role


var rings: Array[Ring] = []
var edges: Array[EdgeEntry] = []


func is_empty() -> bool:
	return rings.is_empty() and edges.is_empty()
