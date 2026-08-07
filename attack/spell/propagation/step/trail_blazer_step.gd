@tool
class_name TrailBlazerStep
extends PropagationStep

## Single-path "string walker" for The Trail Blazer, a true "Line Killer".
##
## The initial hit lands as normal. From there the walk jumps to every hostile
## neighbour and reads its [b]entity degree[/b] — how many of its edges run to
## nodes owned by the [b]same[/b] entity ([method SkillNode.get_entity_degree]):
##
## - [b]degree 2[/b] — a link in the chain. Take damage, ramp, keep walking
##   (never back into [member CastSpell.visited]).
## - [b]degree > 2[/b] — a junction. Slam: apply [member terminal_mode] and stop.
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
## `test/unit/spell/test_line_killer_step.gd`) and the end-to-end ones missed it
## because on a fully-owned string the two degrees coincide.
##
## The per-hop ramp comes from [member PropagationConfig.hop_damage] (typically
## [FlatAddProgression] with [code]increment = 2[/code]), running until the walk
## reaches a junction — the *slam* node — where [member terminal_mode] applies
## and the walk stops.
##
## On a pure string the filter + visit cap leave exactly one candidate per hop
## (the unvisited next node); when multiple candidates survive, all of them get
## minted in parallel — no random pick.
##
## Example — seed A, string B-C-D-E, junction F (degree 3), with the stock
## `FlatAddProgression(2)` on the propagation config, `terminal_mode =
## MULTIPLY_CONSTANT` (×2) and a seed of 1 (`spell_damage × power`):
##   A=1  B=3  C=5  D=7  E=9  →  F = (9 + 2) × 2 = 22 (slam, then stops).

enum TerminalMode {
	SQUARE,               ## slam = accumulated² — steep quadratic spike.
	MULTIPLY_BY_DEGREE,   ## slam = accumulated × the junction's graph degree.
	MULTIPLY_CONSTANT,    ## slam = accumulated × terminal_multiplier.
}

## How the junction (degree > 2) slam damage is derived from the running total.
@export var terminal_mode: TerminalMode = TerminalMode.MULTIPLY_CONSTANT
## Multiplier used only when [member terminal_mode] is MULTIPLY_CONSTANT.
@export var terminal_multiplier: float = 2.0


func step(
		_current_node: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]:
	if candidates.is_empty() or ctx.graph == null:
		return []

	# The per-hop progression runs inside `_propagate_to` (config.hop_damage —
	# typically FlatAddProgression(2) for the stock Trailblazer). The base
	# `next.damage` already carries the progressed total; the historical
	# `accumulated = payload.damage + per_hop_increment` line is now just
	# `next.damage` straight out of `_propagate_to`. We only override damage
	# when the candidate is a junction (the slam case).
	var result: Array[CastSpell] = []
	for candidate in candidates:
		# ENTITY degree, never graph degree. The walk is about the DEFENDER's
		# constellation shape, so a junction means "three of THEIR nodes meet
		# here" — an enemy node brushing past the string is not a junction and
		# must not stop the walk. See docs/domain/degree.md.
		var degree := candidate.get_entity_degree(ctx.graph)
		var next := _propagate_to(candidate, payload, config)
		if degree > 2:
			# Junction reached — slam and terminate the walk.
			next.damage = _terminal_damage(next.damage, degree)
			next.hops_remaining = 0
		result.append(next)
	return result


func _terminal_damage(accumulated: float, degree: int) -> float:
	match terminal_mode:
		TerminalMode.SQUARE:
			return accumulated * accumulated
		TerminalMode.MULTIPLY_BY_DEGREE:
			return accumulated * float(degree)
		TerminalMode.MULTIPLY_CONSTANT:
			return accumulated * terminal_multiplier
	return accumulated


func get_description() -> String:
	var slam := ""
	match terminal_mode:
		TerminalMode.SQUARE:
			slam = "squares the total"
		TerminalMode.MULTIPLY_BY_DEGREE:
			slam = "multiplies by the junction's degree"
		TerminalMode.MULTIPLY_CONSTANT:
			slam = "×%s" % _fmt(terminal_multiplier)
	return "Walks a single path, then %s at the first junction." % slam


func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
