class_name ContestantRule
extends Resource

## Is this entity in the contest at all? (#517) — the predicate a
## [VictoryCondition] applies before it counts anyone. Replaces
## `Faction.counts_for_victory`, which could only author inertness per CAMP and
## so could never express a per-entity exception without minting a faction.
##
## **Owner call 2026-08-22:** "i feel like the game mode decides the victory
## conditions, and entities themselves just should be agnostic of all this...
## i think a predicate (customizable to any condition) would be a more useful
## construct than a single bool... i feel like victorycond would be the one to
## apply them anyway."
##
## That is why membership lives here and not on [Entity] or [Faction]: the rule
## belongs to whoever decides how the run ends. The per-entity handle it reads
## is a plain Godot group (see [ExcludeGroupRule]) — the engine's own version of
## a per-unit tag — so [Entity] gains no field and learns nothing about victory.
##
## **Pure**, same contract as [VictoryCondition]: no state, no signals, no
## subscriptions. A `.tres` is shared and `duplicate()`d freely, so per-run
## mutable state here would silently fork between two levels or a reloaded
## scene. [method includes] must be a function of its argument alone.
##
## **Pull, not push:** membership is computed at evaluation time, never stamped
## onto entities at spawn or run start. A stamping pass would have to run after
## `victory_system.condition` is assigned — later than `_setup_level`, so it
## would re-stamp anything a level deliberately un-stamped, and a boolean group
## cannot tell "not yet stamped" from "deliberately out". A materialised view
## computed from this same rule stays purely additive if save/replay/spectating
## ever wants one.
##
## The sanctioned answer for genuinely bespoke run-end logic is a
## [VictoryCondition] subclass, not a cleverer rule — do not grow this class to
## anticipate one.

## Override. The base rule is "everyone counts", which is also what a null rule
## means at every call site: no crash, and no silently never-ending run.
func includes(_ent: Entity) -> bool:
	return true
