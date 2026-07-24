@tool
class_name GreedyBfsBallPolicy
extends AllocationPolicy

## First concrete [AllocationPolicy] (#275) — the greedy BFS ball. The caller
## (TerritorySeeder) hands us the current frontier (nodes exactly one hop from
## already-owned territory), so every candidate is already "nearest" — picking
## reduces to breaking ties uniformly via `rng`. Same seed -> same RNG stream
## -> same tiebreaks -> identical territory (deterministic seeding, D-19/D-24).
##
## `AIController._pick_frontier_node()` is the AI's degenerate sibling of this
## same policy shape — it differs only in tiebreak (first-edge-found, no RNG)
## and call rate (once per turn vs. N times at spawn). Weighted growth (score
## by modifier value x archetype match) is a separate, later `AllocationPolicy`
## — the AI v2 scoring heuristic, not this one (see D-24 NOTES correction).
##
## `objective` is accepted for interface parity with [AllocationPolicy] but
## unused — this policy carries no tactical intent.

func pick_next(_entity: Entity, candidates: Array[SkillNode], _objective) -> SkillNode:
	if candidates.is_empty():
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
	return candidates[rng.randi() % candidates.size()]
