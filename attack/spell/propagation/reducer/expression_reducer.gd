@tool
class_name ExpressionReducer
extends IncidentReducer

## Author a damage-resolution [Expression] inline. Available identifiers:
##   incident_count          — int, .size() of the incidents
##   damages                 — Array[float], one per incident
##   max_damage, min_damage  — float
##   sum_damage, avg_damage  — float
##
## Return a number to set the resolved damage; return a negative number to
## CANCEL (resolves to null). Examples:
##   sum_damage * 0.75                   — diminishing-returns sum
##   incident_count if incident_count >= 3 else -1   — only resolve when ≥3 incidents overlap

@export_multiline var expression: String = "sum_damage"

var _expr: Expression = null
var _last_text: String = ""


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	if _expr == null or _last_text != expression:
		_expr = Expression.new()
		var err := _expr.parse(expression, [
			"incident_count", "damages",
			"max_damage", "min_damage", "sum_damage", "avg_damage",
		])
		if err != OK:
			push_warning("ExpressionReducer parse error: %s" % _expr.get_error_text())
			_expr = null
			return _fallback(incidents, node)
		_last_text = expression
	var dmgs: Array = []
	var smin: float = incidents[0].damage
	var smax: float = incidents[0].damage
	var ssum: float = 0.0
	for inc in incidents:
		dmgs.append(inc.damage)
		ssum += inc.damage
		if inc.damage < smin: smin = inc.damage
		if inc.damage > smax: smax = inc.damage
	var avg: float = ssum / float(incidents.size())
	var result: Variant = _expr.execute([
		incidents.size(), dmgs, smax, smin, ssum, avg,
	], null, false)
	if _expr.has_execute_failed():
		return _fallback(incidents, node)
	var resolved: float = float(result)
	if resolved < 0.0:
		return null
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = resolved
	return merged


func get_description() -> String:
	return "Custom reduce: %s" % expression


func _fallback(incidents: Array[CastSpell], node: SkillNode) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = incidents[0].damage
	return merged
