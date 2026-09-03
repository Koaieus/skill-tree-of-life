extends GutTest

## The combinator (#746): 0..N bonus [VictoryCondition]s OR-ed on top of the
## shipped floor ([LastCampStandingCondition]). The mechanism only — no bonus
## conditions are authored yet (that's the second drone, per the owner's
## "combinator now, conditions later" scoping on #746).
##
## The N=0 case is the heart of the acceptance: with nothing layered on,
## [CombinedVictoryCondition] must be indistinguishable from the shipped floor
## itself, so it is asserted against a [method Resource.duplicate] of the
## actual shipped `.tres` — "behaves as the shipped floor", not "as a thing
## built to resemble it".

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _FLOOR_ASSET := preload("res://session/victory/last_camp_standing.tres")

## A throwaway condition returning a canned outcome (or null, to mean "does not
## fire"). Never shipped content — see `session/victory/last_camp_standing.tres`
## for what that looks like; this exists purely to drive the combinator's OR
## logic without authoring a real bonus condition.
class _StubCondition:
	extends VictoryCondition
	var canned_outcome: RunOutcome = null
	var call_count: int = 0

	func evaluate(_ctx: VictoryContext) -> RunOutcome:
		call_count += 1
		return canned_outcome


func _ent(faction: Faction, dead: bool = false) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.is_dead = dead
	return autofree(e) as Entity


func _ctx(entities: Array) -> VictoryContext:
	var ctx := VictoryContext.new()
	for e in entities:
		ctx.entities.append(e as Entity)
	return ctx


func _stub(outcome: RunOutcome = null) -> _StubCondition:
	var s := _StubCondition.new()
	s.canned_outcome = outcome
	return s


func _outcome(winner: Faction) -> RunOutcome:
	var o := RunOutcome.new()
	o.winning_camp = winner
	return o


## N=0: an empty ladder must degrade to EXACTLY the shipped floor's answer —
## compared against a duplicate of the actual `.tres` asset, both on a
## deciding context (one camp standing) and a continuing one (two camps
## standing).
func test_zero_bonus_conditions_matches_the_shipped_floor_exactly() -> void:
	var combined := CombinedVictoryCondition.new()
	var floor_dup := _FLOOR_ASSET.duplicate() as VictoryCondition

	var deciding_ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true)])
	var combined_outcome := combined.evaluate(deciding_ctx)
	var floor_outcome := floor_dup.evaluate(deciding_ctx)
	assert_not_null(combined_outcome)
	assert_eq(combined_outcome.winning_camp.id, floor_outcome.winning_camp.id)

	var continuing_ctx := _ctx([_ent(_PLAYER), _ent(_NPC)])
	assert_eq(combined.evaluate(continuing_ctx), floor_dup.evaluate(continuing_ctx),
			"both must read the run as still contested")


## N=1, not firing: the one bonus returns null every time, so the run's fate
## is still decided by the floor alone — same code path as N=0, not a
## branch that only exists for the empty-array case.
func test_one_non_firing_bonus_falls_through_to_the_floor() -> void:
	var combined := CombinedVictoryCondition.new()
	combined.bonus_conditions = [_stub()]

	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true)])
	var outcome := combined.evaluate(ctx)

	assert_not_null(outcome, "the floor must still be free to end the run")
	assert_eq(outcome.winning_camp.id, &"player")


## N=1, firing: a bonus condition ends the run even while the floor itself
## would still call it contested (two camps standing) — the whole point of a
## bonus being "add-able on top" rather than a second vote on the same
## question.
func test_a_firing_bonus_wins_the_run_before_the_floor_would_have() -> void:
	var bonus_winner := _outcome(_NPC)
	var combined := CombinedVictoryCondition.new()
	combined.bonus_conditions = [_stub(bonus_winner)]

	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC)])
	var outcome := combined.evaluate(ctx)

	assert_eq(outcome, bonus_winner,
			"a bonus must be able to end the run while two camps are still standing")


## N>=2, precedence: bonus conditions are checked in authored array order and
## the FIRST to fire wins — including over a second bonus that would also have
## fired. The second stub's zero call count proves the short-circuit, not just
## the returned value.
func test_bonus_conditions_fire_in_authored_order_first_match_wins() -> void:
	var first_outcome := _outcome(_PLAYER)
	var second := _stub(_outcome(_NPC))
	var combined := CombinedVictoryCondition.new()
	combined.bonus_conditions = [_stub(first_outcome), second]

	var outcome := combined.evaluate(_ctx([_ent(_PLAYER), _ent(_NPC)]))

	assert_eq(outcome, first_outcome, "the first authored bonus to fire must win")
	assert_eq(second.call_count, 0,
			"a later bonus must not even be consulted once an earlier one fires")


## N>=2, none firing: same fall-through as N=0 and N=1 — no special case for
## how many bonuses were checked before the floor gets asked.
func test_multiple_non_firing_bonuses_still_fall_through_to_the_floor() -> void:
	var combined := CombinedVictoryCondition.new()
	combined.bonus_conditions = [_stub(), _stub(), _stub()]

	var deciding_ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true)])
	var continuing_ctx := _ctx([_ent(_PLAYER), _ent(_NPC)])

	assert_not_null(combined.evaluate(deciding_ctx), "the floor still decides")
	assert_null(combined.evaluate(continuing_ctx), "the floor still calls it contested")


## The floor cannot be unset: nothing on [CombinedVictoryCondition] exposes a
## slot to swap or null it out.
func test_the_floor_is_not_an_exported_field() -> void:
	var props: Array = CombinedVictoryCondition.new().get_property_list().map(
			func(p: Dictionary) -> String: return p.get("name", ""))
	assert_false(props.has("floor"), "the floor must not be swappable content")
	assert_true(props.has("bonus_conditions"), "only the bonus ladder is authored")
