extends AStar2D
class_name AStarSkillTree

## Custom AStar over a skill graph: every edge costs the same, so paths are
## ranked by HOP COUNT, not geometric distance.
##
## Both hooks must agree on that. `_compute_cost` is a flat 1.0 per edge.
## `_estimate_cost` MUST be ≤ the true remaining cost (admissible) or A* can
## return a non-shortest path; AStar2D's default heuristic is euclidean point
## distance, which wildly overestimates against unit edge costs and silently
## yields non-fewest-hop paths. A constant 0 heuristic is trivially admissible
## (this degrades A* to Dijkstra/BFS over unit weights — exactly right here) and
## means `get_id_path` is a correct, native replacement for hand-rolled hop BFS.


func _compute_cost(_from_id: int, _to_id: int) -> float:
	return 1.0


func _estimate_cost(_from_id: int, _to_id: int) -> float:
	return 0.0
