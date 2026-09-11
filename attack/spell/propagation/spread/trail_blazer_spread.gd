@tool
class_name TrailBlazerSpread
extends PropagationSpread

## Single-path "string walker" for The Trail Blazer, a true "Line Killer".
##
## The initial hit lands as normal. From there the walk jumps to every hostile
## neighbour and reads its [b]entity degree[/b] — how many of its edges run to
## nodes owned by the [b]same[/b] entity ([method SkillNode.get_entity_degree]):
##
## - [b]degree 2[/b] — a link in the chain. Take damage, ramp, keep walking
##   (never back into [member CastSpell.visited]).
## - [b]degree > 2[/b] — a junction. The walk ends there, slammed.
##
## Neither half of that ending is this class's job any more (#851). The spread
## is pure selection: it picks every surviving candidate at full share and
## nothing else — the child itself is minted by [method PropagationConfig.mint]
## (#852).
##   - The [b]slam[/b] is a [ScaleDamageEffect] gated on [JunctionCondition],
##     authored before [DamageEffect] on the spell's `on_hit_effects`. It fires
##     where the spell LANDS, which is also why a cast seeded directly onto a
##     junction is now slammed (it never was before — the old code decided the
##     slam at child-mint, so hop 0 had no chance to qualify).
##   - The [b]stop[/b] is the filter: `from_entity_degree <= 2` on the spell's
##     [ExpressionFilter]. The walk ends at a junction because nothing is
##     eligible to leave one, not because a step zeroed a counter.
##
## So it runs down an entire trail for as long as that trail is a chain of
## degree-2 nodes. Launched at the tip of a trail, the first jump lands on a
## degree-2 node and the walk (and its ramp) triggers immediately.
##
## The read: a tool that punishes long-stretched constellations, and one that
## stays effective even on a caster with poor stats — the damage comes from the
## defender's own shape, not from the attacker's INT.
##
## [b]Entity degree is the whole point, not an implementation detail.[/b] The
## spell is about the defender's territory shape, so an unrelated enemy node
## sitting next to the string must not read as a junction and halt the walk.
## This walked GRAPH degree until 2026-08-07; the step-level tests missed it
## because their fixtures left every node unowned (see the header of
## `test/unit/spell/test_trail_blazer_spread.gd`) and the end-to-end ones missed it
## because on a fully-owned string the two degrees coincide. Both readers of
## that fact now live elsewhere — [JunctionCondition] and the filter clause —
## and `docs/domain/degree.md` is the rule.
##
## The per-hop ramp comes from [member PropagationConfig.hop_damage] (typically
## [FlatAddProgression] with [code]increment = 2[/code]).
##
## On a pure string the filter + visit cap leave exactly one candidate per hop
## (the unvisited next node); when multiple candidates survive, all of them are
## picked in parallel — no random pick.
##
## Example — seed A, string B-C-D-E, junction F (degree 3), with the stock
## `FlatAddProgression(2)` on the propagation config, a `ScaleDamageEffect`
## (MULTIPLY ×2, when = [JunctionCondition]) and a seed of 1
## (`spell_damage × power`):
##   A=1  B=3  C=5  D=7  E=9  →  F = (9 + 2) × 2 = 22 (slam, then stops).


func select(
		_current: SkillNode,
		eligible: Array[SkillNode],
		_payload: CastSpell,
		ctx: PropagationContext) -> Array[PropagationPick]:
	if eligible.is_empty() or ctx.graph == null:
		return []

	# The per-hop progression runs inside `PropagationConfig.mint`
	# (config.hop_damage — typically FlatAddProgression(2) for the stock
	# Trailblazer). Nothing else happens here: a junction candidate is picked
	# exactly like a chain candidate, and the arrival decides the rest.
	var out: Array[PropagationPick] = []
	for candidate in eligible:
		out.append(PropagationPick.to(candidate))
	return out


func get_description() -> String:
	return "Walks a single path along a chain of degree-2 nodes."
