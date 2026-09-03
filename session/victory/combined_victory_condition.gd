class_name CombinedVictoryCondition
extends VictoryCondition

## The combinator (#746). Layers 0..N bonus conditions on top of the shipped
## floor, OR-ed: the run ends the moment ANY bonus fires, otherwise exactly
## when the floor itself would end it.
##
## **Owner, 2026-09-03, verbatim:** "in practice the last camp standing rule is
## the implicit one, absent all other conditions it would always end like
## that. bonus conditions should be add-able on top... any bonus condition
## wins you the game." And on scope: "combinator now, conditions later with
## the next wave... the composability of 0..N bonus rules should follow from
## the mechanism, concrete units + UI is the second drone."
##
## **The floor cannot be unset — by design, not by omission.** It is
## [constant _FLOOR], a preload of the shipped [LastCampStandingCondition]
## asset, never an `@export` field: nothing authoring a
## [CombinedVictoryCondition] has a slot to swap or null it out. Preloading the
## asset (rather than `LastCampStandingCondition.new()`) matters beyond
## avoiding an allocation per [method evaluate] call (this runs on every
## death, see [VictorySystem]) — a fresh instance is a SECOND, parallel
## authority on what the floor is, correct only by accident today because
## nothing has yet authored a [member VictoryCondition.contestants] rule onto
## `last_camp_standing.tres`. The moment something does, a `.new()` floor would
## silently stop matching the shipped condition. Preloading the asset makes
## that impossible by construction.
##
## **Precedence is a decision, not a consequence:** a bonus that would fire on
## the same tick as the floor (the last hostile dies AND someone crosses a
## bonus threshold in the same resolution) wins over the floor, because a
## player who deliberately raced for a bonus condition should not have it
## silently overridden by the default ending. Bonus conditions are checked in
## authored array order and the first to fire wins, which is also the tie
## break between two bonuses landing on the same tick.
##
## **The inherited `contestants` export is inert on this class.**
## [VictoryCondition] declares [member VictoryCondition.contestants] and this
## class does not hide it, so a `CombinedVictoryCondition.tres` shows a
## `contestants` slot in the inspector — but [method evaluate] never reads
## `self.contestants`; it delegates entirely to [constant _FLOOR], which
## carries its own. Setting it here is silently ignored: exactly the
## second-parallel-authority failure [constant _FLOOR]'s own docstring
## argues against, just arriving from the base class instead of from a
## fresh `.new()`. To change who contests the run, edit
## `last_camp_standing.tres` (the floor) or the bonus condition in
## question — never this class's own `contestants`.
##
## **No `is_empty()` special case.** [method evaluate] walks
## [member bonus_conditions] and falls through to the floor whether that array
## holds 0, 1, or N entries — the same code path every time, which is what
## makes 0..N composability a property of the mechanism rather than something
## bolted on at either end.

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
