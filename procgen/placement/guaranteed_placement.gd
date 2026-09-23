@tool
class_name GuaranteedPlacement
extends Resource

## Abstract base for the pre-roll constraint pass. Each placement runs against
## a [PlacementContext] *before* the per-node modifier roll, mutating role
## tags or (later) reserving content slots so the random fill respects
## designer-specified invariants.
##
## Concrete subclasses:
##   - RandomBudgetBoost — flag N random nodes with a role tag for budget boost
##   - MinNearStartingPoints — ensure every starter has a tagged node nearby
##   - ScenePlacement (step 10) — place authored landmark scenes (#330)

func apply(_context: PlacementContext) -> void:
	pass


## The [ScalarField]s this placement holds, so generation can hand each the
## resolved mask radius. Base: none.
func scalar_fields() -> Array[ScalarField]:
	return []
