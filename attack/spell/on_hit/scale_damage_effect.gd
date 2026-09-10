@tool
class_name ScaleDamageEffect
extends OnHitEffect

## Scales [member CastSpell.damage] IN PLACE at a landing, optionally gated by
## a [LandingCondition]. Emits nothing itself — author it BEFORE [DamageEffect]
## in [member SpellDef.on_hit_effects] and the damage effect emits the scaled
## number. Effects already run in order over the one mutable [CastSpell]; this
## is that contract used, not a new one.
##
## [b]Effects run before departure, so a scaled arrival is what the next hop
## inherits.[/b] That is deliberate and it is the whole reason this can replace
## an in-step slam: [TrailBlazerStep] used to multiply at child-mint and zero
## the hop counter in the same breath, which meant the scale was decided one
## node early, from the previous node's point of view. Here the scale is
## decided where it lands. A spell that scales mid-walk therefore compounds —
## if you want a one-shot spike, gate it on a condition that also ends the walk
## (the Trailblazer's [JunctionCondition] pairs with a `from_entity_degree <= 2`
## clause on its filter, so nothing is eligible to leave a junction).
##
## [b]It scales the MERGED arrival, not each incoming branch.[/b] Effects run
## after the [IncidentReducer] has resolved everything that reached this node
## this wave, so two branches converging on one junction are summed (or
## max-ed, or first-won) FIRST and scaled once. The old in-step slam scaled
## per branch, before the merge. For [constant Mode.MULTIPLY] the two agree by
## distributivity and for max/first-wins they agree outright, which is why the
## Trailblazer's goldens do not move; for [constant Mode.SQUARE] under a
## summing reducer they genuinely differ, and scaling the merged arrival is
## the intended reading of "arrival transforms are on-hit effects".

enum Mode {
	MULTIPLY,            ## damage × [member factor]
	SQUARE,              ## damage² — steep quadratic spike
	MULTIPLY_BY_DEGREE,  ## damage × the landed node's ENTITY degree
}

## Null means "always" — an unconditional scale.
@export var when: LandingCondition = null
@export var mode: Mode = Mode.MULTIPLY
## Used only when [member mode] is [constant Mode.MULTIPLY].
@export var factor: float = 2.0


func apply(state: CastSpell, _outcome: AttackOutcome) -> void:
	if state == null or state.current_node == null:
		return
	if when != null and not when.evaluate(state, state.current_node, _outcome):
		return
	state.damage = _scaled(state)


## ENTITY degree for [constant Mode.MULTIPLY_BY_DEGREE], matching every other
## territory-shape rule in the propagation pipeline — and matching what
## `TrailBlazerStep._terminal_damage` was actually handed before #851 (its
## docstring said "graph degree", the value passed in was the entity degree it
## had just computed; the code was right and the prose was wrong).
func _scaled(state: CastSpell) -> float:
	match mode:
		Mode.MULTIPLY:
			return state.damage * factor
		Mode.SQUARE:
			return state.damage * state.damage
		Mode.MULTIPLY_BY_DEGREE:
			if state.graph == null:
				return state.damage
			return state.damage * float(state.current_node.get_entity_degree(state.graph))
	return state.damage


## Draft copy — #764 finalises the wording.
func get_description() -> String:
	var what := ""
	match mode:
		Mode.MULTIPLY: what = "×%s damage" % _fmt(factor)
		Mode.SQUARE: what = "squared damage"
		Mode.MULTIPLY_BY_DEGREE: what = "damage × the node's degree"
	if when == null:
		return what.capitalize() + "."
	var gate := when.get_description()
	if gate == "":
		return what.capitalize() + ", conditionally."
	return "%s %s." % [what.capitalize(), gate]


func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
