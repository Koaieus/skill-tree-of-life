@tool
class_name ExpressionProgression
extends HopDamageProgression

## One-off escape hatch: author a float-returning GDScript [Expression] inline
## on the spell .tres. Mirrors [ExpressionFilter] and the [ExpressionFormula]
## pattern in the stats system.
##
## Available identifiers:
##   damage       — float, the parent's damage (already progressed by prior hops).
##   seed_damage  — float, the cast's seed damage (spell_damage × power).
##   hop_index    — int,   the parent's hop_index (0 at the seed).
##
## [b]It is [code]seed_damage[/code], not [code]seed[/code][/b] — Godot's
## [Expression] parser reads a bare [code]seed[/code] as the built-in
## [method @GlobalScope.seed] PRNG function and fails with "Expected '('".
## Same collision that named [member CastSpell.seed_node].
##
## With the seed in scope this covers any affine curve, which is why #274
## deleted the stock affine class outright: its [code](d + a) × m[/code] is
## [code]damage * m + a * m[/code] here, and the seed-relative affine it could
## never express is [code]damage * 1.5 + seed_damage * 2[/code].
## Whether an authored expression scales with the caster is the author's call;
## the four stock shapes state their answer in the class name.

@export_multiline var expression: String = "damage"

var _expr: Expression = null
var _last_text: String = ""


func apply(damage: float, seed: float, hop_index: int) -> float:
	if _expr == null or _last_text != expression:
		_expr = Expression.new()
		var err := _expr.parse(expression, ["damage", "seed_damage", "hop_index"])
		if err != OK:
			push_warning("ExpressionProgression parse error: %s" % _expr.get_error_text())
			_expr = null
			return damage
		_last_text = expression
	var result: Variant = _expr.execute([damage, seed, hop_index], null, false)
	if _expr.has_execute_failed():
		return damage
	return float(result)


func get_description() -> String:
	return "progression: %s" % expression
