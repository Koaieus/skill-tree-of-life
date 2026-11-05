class_name ContestantRule
extends Resource

## Is this entity in the contest at all? The predicate a `VictoryCondition`
## applies before it counts anyone. Pure (no state, no signals); computed at
## evaluation time, never stamped on entities. Bespoke run-end logic is a
## `VictoryCondition` subclass, not a cleverer rule.
## See docs/domain/victory-system.md

## Override. The base rule is "everyone counts", which is also what a null rule
## means at every call site: no crash, and no silently never-ending run.
func includes(_ent: Entity) -> bool:
	return true
