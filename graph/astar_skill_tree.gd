extends AStar2D
class_name AStarSkillTree

## Custom AStar implementation
# - Ensures cost function matches that of a skill tree


func _compute_cost(from_id: int, to_id: int) -> float:
	return 1.0
