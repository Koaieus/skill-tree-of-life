@tool
class_name LocalExtremumCondition
extends LandingCondition

## Stub — implemented in the next commit.

enum Mode { MAX, MIN }

@export var ranker: NodeRanker = null
@export var mode: Mode = Mode.MAX
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15")
var neighbours: int = 14


func evaluate(_lctx: LandingContext) -> bool:
	return false
