class_name VictoryContext
extends RefCounted

## Everything a [VictoryCondition] is allowed to read, gathered once per
## evaluation. Not a Resource: it is a throwaway snapshot of live runtime
## state, never authored or saved.
##
## Built by [method VictorySystem.build_context], which is the seam the
## `GameSession` autoload fills — the run's config picks the condition, and the
## condition reads this. Deliberately broader than last-camp-standing needs,
## because the pluggable siblings the owner named do need it: a territory
## threshold reads owned node counts off [member entities] + [member graph], and
## a survive-N-turns condition reads [member turn_count].
##
## Point-of-view-free by construction (#517). There is no "local camp" here: a
## run has one winner and as many points of view as there are machines watching,
## so the local reading is resolved at display time from [SeatPolicy], not
## baked into the world's terminal state.

## Every [Entity] in the run, alive or dead — a condition decides for itself
## what "still in it" means. Freed entities are filtered out at build time.
var entities: Array[Entity] = []
## The level's [Graph], for territory/objective-node conditions.
var graph: Graph = null
## Turns served so far ([member TurnManager.turns_taken]).
var turn_count: int = 0


## Camps with at least one living entity that [param contestants] admits to the
## contest. Survival is measured in LIVING ENTITIES, not roster seats — a camp
## whose participants are all dead has lost, per the owner call. Identity is by
## [member Faction.id], matching [method Entity.attitude_to], so two copies of
## the same `.tres` are one camp.
##
## Three filters, deliberately of different kinds:
## - **Validity** — a freed entity is nobody.
## - **Liveness** — a snapshot read of [member Entity.is_dead], NOT a group.
##   [method GameRoot._pull_from_turn_loop] already takes corpses out of
##   [constant Entity.GROUP], but that removal happens for turn-loop reasons; a
##   group meaning *living* would additionally need re-add-on-revive, while this
##   filter is correct by construction and has no lifecycle to desync. It is
##   also what makes a headless fixture (no GameRoot to pull anyone) behave.
## - **Contest membership** — [param contestants], re-read on every evaluation
##   (#517). Null means everyone counts.
##
## [param contestants] is deliberately REQUIRED even though null is legal: a
## condition that forgot to pass its rule would silently count scenery and never
## end the run, and an optional parameter is exactly how that omission hides.
## Pass [member VictoryCondition.contestants]; pass null on purpose or not at all.
func living_camps(contestants: ContestantRule) -> Array[Faction]:
	var seen: Array[StringName] = []
	var result: Array[Faction] = []
	for ent in entities:
		if not is_instance_valid(ent) or ent.is_dead:
			continue
		if contestants != null and not contestants.includes(ent):
			continue
		var f := ent.faction
		if f == null or f.id == &"":
			continue
		if seen.has(f.id):
			continue
		seen.append(f.id)
		result.append(f)
	return result
