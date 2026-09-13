@tool
class_name LandingContext
extends RefCounted

## One landing's fixed view, built by [SpellResolver] once per node a wave
## resolves onto (right after [IncidentReducer.reduce] returns) and reused for
## that landing's whole lifetime: arrival ([OnHitEffect]s, crit
## [LandingCondition]s) AND departure ([PropagationFilter], [PropagationSpread]).
##
## [b]Lifetime decides the home[/b] (#356, hub #849): per-CAST facts live on
## [member cast]; per-LANDING facts live here. [IncidentReducer] is the one
## stage that does NOT take a [LandingContext] — it MAKES the landing, so none
## exists yet when it runs; it takes [member cast] directly.
##
## [b]The fields are fixed at construction, but [member payload] is not
## immutable through them.[/b] [member payload] is the one mutable [CastSpell]
## that on-hit effects mutate IN ORDER — [ScaleDamageEffect] running before
## [DamageEffect] relies on exactly that, and this refactor does not change it.
## [member node], [member cast] and [member incidents] never change after
## construction.


## The per-cast ledger this landing belongs to — [member PropagationContext.outcome],
## [method PropagationContext.rng_for_crits], the world, all of it.
var cast: PropagationContext = null

## The landed node — [code]from[/code] for a departure stage
## ([PropagationFilter], [PropagationSpread]), [code]target[/code] for an
## arrival stage ([LandingCondition], [OnHitEffect]).
var node: SkillNode = null

## The reducer's resolved state for this landing. Mutable — see the class docstring.
var payload: CastSpell = null

## What arrived here this wave, before the reducer merged them — provenance
## only; nothing downstream re-derives the merge from this.
var incidents: Array[CastSpell] = []


## Forwarding accessor: a stage asks THIS, never [code]lctx.cast.ownership_bit_of[/code],
## so every question the world contract answers goes through one name regardless
## of which context object happens to hold it. See [method PropagationContext.ownership_bit_of].
func ownership_bit_of(n: SkillNode) -> int:
	return cast.ownership_bit_of(n)


## See [method PropagationContext.is_allocated_in_world].
func is_allocated_in_world(n: SkillNode) -> bool:
	return cast.is_allocated_in_world(n)


## See [method PropagationContext.local_value_of].
func local_value_of(n: SkillNode, stat_id: StringName) -> Variant:
	return cast.local_value_of(n, stat_id)


## See [method PropagationContext.visit_count].
func visit_count(n: SkillNode) -> int:
	return cast.visit_count(n)


## Test/fixture convenience: build a [LandingContext] from the pieces a unit
## test already has lying around, without wiring a whole cast. [param cast_]
## defaults to a fresh [PropagationContext] rather than null, so a condition or
## effect that reaches for [code]lctx.cast.outcome[/code] on a hand-built fixture
## gets a real (empty) object instead of crashing on a null dereference — and a
## [member PropagationContext.outcome] left unset (fresh or handed-in) is filled
## with a fresh [AttackOutcome] for the same reason: [OnHitEffect]s append to it
## unconditionally.
static func for_test(
		payload_: CastSpell = null,
		node_: SkillNode = null,
		cast_: PropagationContext = null,
		incidents_: Array[CastSpell] = []) -> LandingContext:
	var lctx := LandingContext.new()
	lctx.cast = cast_ if cast_ != null else PropagationContext.new()
	if lctx.cast.outcome == null:
		lctx.cast.outcome = AttackOutcome.new()
	lctx.node = node_
	lctx.payload = payload_
	lctx.incidents = incidents_
	return lctx
