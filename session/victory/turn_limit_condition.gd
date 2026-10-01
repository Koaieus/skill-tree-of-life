class_name TurnLimitCondition
extends VictoryCondition

## STUB — filled in by #1257.

enum Unit { ROUNDS, ENTITY_TURNS }

@export_range(1, 500) var limit: int = 15
@export var unit: Unit = Unit.ROUNDS


func evaluate(_ctx: VictoryContext) -> RunOutcome:
	return null
