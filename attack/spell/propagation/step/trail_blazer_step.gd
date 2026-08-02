@tool
class_name TrailBlazerStep
extends PropagationStep

## Single-path "string walker" for The Trail Blazer, a true "Line Killer". From the seed it
## fans to every degree-2 candidate, with the per-hop ramp provided by
## [member PropagationConfig.hop_damage] (typically [AddRamp] with
## [code]increment = 2[/code]), until it reaches a junction (graph degree > 2)
## — the *slam* node — where it applies [member terminal_mode] and stops.
##
## On a pure string the filter + visit cap leave exactly one candidate per hop
## (the unvisited next node); when multiple candidates survive, all of them get
## minted in parallel — no random pick.
##
## Example — seed A, string B-C-D-E, junction F (degree 3), with the stock
## `AddRamp(2)` on the propagation config and `terminal_mode =
## MULTIPLY_CONSTANT` (×2):
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

	# The per-hop ramp runs inside `_propagate_to` (config.hop_damage —
	# typically AddRamp(2) for the stock Trailblazer). The base `next.damage`
	# already carries the ramped total; the historical TrailBlazer
	# `accumulated = payload.damage + per_hop_increment` line is now just
	# `next.damage` straight out of `_propagate_to`. We only override damage
	# when the candidate is a junction (the slam case).
	var result: Array[CastSpell] = []
	for candidate in candidates:
		var degree := candidate.get_graph_degree(ctx.graph)
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
