class_name CombinedVictoryCondition
extends VictoryCondition

## Layers 0..N bonus conditions on top of the shipped floor, OR-ed: any bonus
## fires and wins (authored order breaks ties, bonus beats floor on the same
## tick); otherwise the floor decides. The floor is a preloaded `_FLOOR`, never
## an export, and this class's inherited `contestants` is inert.
## See docs/domain/victory-system.md

const _FLOOR := preload("res://session/victory/last_camp_standing.tres")

## Layered on top of the floor, OR-ed, checked in this order. Empty ships
## today (#746 scope: mechanism only, no bonus conditions authored yet) and
## must degrade to exactly the floor's own answer.
@export var bonus_conditions: Array[VictoryCondition] = []


func evaluate(ctx: VictoryContext) -> RunOutcome:
	for bonus in bonus_conditions:
		var result := bonus.evaluate(ctx)
		if result != null:
			return result
	return _FLOOR.evaluate(ctx)


## The bonuses' descriptions, joined — the floor is implicit in every run, so it
## is only named when no bonus says anything.
func describe() -> String:
	var parts: PackedStringArray = []
	for bonus in bonus_conditions:
		var text := bonus.describe() if bonus != null else ""
		if not text.is_empty():
			parts.append(text)
	if parts.is_empty():
		return _FLOOR.describe()
	return " or ".join(parts)
