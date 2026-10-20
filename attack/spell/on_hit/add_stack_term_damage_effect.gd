@tool
class_name AddStackTermDamageEffect
extends SpellOnHitEffect

## Adds each [StackTerm]'s value to [member CastSpell.damage] IN PLACE at a
## landing: `Σ maxf(0, term.extra(read, host))`, read against THIS cast's world
## ([member PropagationContext.world]) with the cast's read node and the landed
## node — the very call a status rider makes at land, so a damage term and a
## stack term sharing one SubResource agree on a shadow resolve. Emits nothing:
## author it BEFORE [DamageEffect], and the damage effect emits the boosted
## number, which the next hop's mint inherits (it compounds up a walk).

## The terms whose values add to the damage. Share them with the intake row's
## [member PlantUse.stack_terms] when the spell strips by the same amount.
@export var stack_terms: Array[StackTerm] = []


func _apply_spell(lctx: LandingContext) -> void:
	var state := lctx.payload
	if state == null or lctx.node == null or lctx.read_node == null:
		return
	var world := lctx.cast.world
	var read := world.combat_for(lctx.read_node)
	var host := world.combat_for(lctx.node)
	for term in stack_terms:
		if term != null:
			state.damage += maxf(0.0, term.extra(read, host))


## "+25% of target armor as damage." — each term's [method StackTerm.describe]
## against [param read_node]; a dormant term (below its gate) says nothing.
func get_description(_spell: SpellDef = null, _board: StatBoard = null, read_node: SkillNode = null) -> String:
	var lines: Array[String] = []
	for term in stack_terms:
		var line := term.describe(read_node) if term != null else ""
		if line != "":
			lines.append(line)
	if lines.is_empty():
		return ""
	var what := "%s as damage" % ", ".join(lines)
	if when == null:
		return what[0].to_upper() + what.substr(1) + "."
	var gate := when.get_description()
	return "%s%s %s." % [what[0].to_upper(), what.substr(1), gate] if gate != "" \
			else "%s%s, conditionally." % [what[0].to_upper(), what.substr(1)]
