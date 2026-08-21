class_name VictoryContext
extends RefCounted

## Everything a [VictoryCondition] is allowed to read, gathered once per
## evaluation. Not a Resource: it is a throwaway snapshot of live runtime
## state, never authored or saved.
##
## This is the seam [code]GameSession[/code] will fill once it exists (#457).
## The issue's acceptance says `evaluate(game_session)`; GameSession is an
## owner-decision unit with live forks (autoload vs. carried node), and a
## parameter cannot be typed as a class that does not exist yet — so #460
## builds the *shape* GameSession will populate instead of pre-empting it.
## When #457 lands, GameSession constructs this; the conditions do not change.
##
## The fields are deliberately broader than last-camp-standing needs, because
## the pluggable siblings the owner named do need them: a territory threshold
## reads owned node counts off [member entities] + [member graph], and a
## survive-N-turns condition reads [member turn_count].

## Every [Entity] in the run, alive or dead — a condition decides for itself
## what "still in it" means. Freed entities are filtered out at build time.
var entities: Array[Entity] = []
## The level's [Graph], for territory/objective-node conditions.
var graph: Graph = null
## Turns served so far ([member TurnManager.turns_taken]).
var turn_count: int = 0
## Which camp the human at THIS keyboard belongs to — decides
## [member RunOutcome.local_result]. Today [VictorySystem] reads it off
## `GameRoot.player.faction`; with a real roster (#461) it comes from the
## local [Participant]. Null in a headless/AI-only run: every outcome is then
## reported as a DRAW from nobody's point of view.
var local_camp: Faction = null


## Camps with at least one living entity that [member Faction.counts_for_victory].
## Survival is measured in LIVING ENTITIES, not roster seats — a camp whose
## participants are all dead has lost, per the owner call. Identity is by
## [member Faction.id], matching [method Entity.attitude_to], so two copies of
## the same `.tres` are one camp.
func living_camps() -> Array[Faction]:
	var seen: Array[StringName] = []
	var result: Array[Faction] = []
	for ent in entities:
		if not is_instance_valid(ent) or ent.is_dead:
			continue
		var f := ent.faction
		if f == null or f.id == &"" or not f.counts_for_victory:
			continue
		if seen.has(f.id):
			continue
		seen.append(f.id)
		result.append(f)
	return result


## True when [param camp] is the local human's camp. Id-compared, not
## reference-compared — see [Faction]'s class doc.
func is_local_camp(camp: Faction) -> bool:
	if camp == null or local_camp == null:
		return false
	return camp.id != &"" and camp.id == local_camp.id
