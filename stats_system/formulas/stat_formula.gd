@tool
@abstract
class_name StatFormula
extends Resource

## Abstract base for pluggable stat formulas used by [StatModifier].
## A formula is stateless — it reads from the board it is given and returns
## a float. All binding/subscription state lives on [StatModifier].

## The qualifier phrase rendered after "per" by [method StatModifier.format]
## — "20 STR", "PER", "×10 INT", "level". ONE SHORT LINE, never
## prose: a formula-bound modifier is displayed as a single-Label glass slab
## ([ModSlabRow]) inside a hover tooltip, so "+1 Blade Size per 20 STR" is the
## entire budget. Deliberately NOT `@export_multiline` (#289).
##
## Subclasses that know their own shape generate this from their typed fields
## (see [RatioFormula], [LinearFormula]) and only fall back to the authored
## string. Author it here for [ExpressionFormula]s, whose expression text is
## arbitrary and must never be parsed back into English.
@export var per_phrase: String = ""

## Ids of all stats this formula reads. [StatModifier] subscribes to
## value_changed on each so the target stat can dirty itself automatically.
func get_input_ids() -> Array[StringName]:
	return []

## Compute and return the modifier value. Called from
## [method StatModifier.get_effective_value] every time the pipeline runs.
func compute(board: StatBoard) -> float:
	return 0.0


## The "per" qualifier for this formula. Base implementation returns the
## authored [member per_phrase]; shape-aware subclasses override to generate
## it, honouring an authored override when one is present.
func describe_per() -> String:
	return per_phrase


## Abbreviation for a source stat, matching the Attributes Panel's axis
## labels (`Strength` → `STR`). Lives here so generated phrases and the
## panel share one convention — see [method StatDef.abbrev].
static func _abbrev(stat_id: StringName) -> String:
	var def: StatDef = StatRegistry.get_def(stat_id)
	return def.abbrev() if def != null else String(stat_id)


## Render a float without trailing ".00" — whole values print as ints.
## Mirrors [method StatModifier._trim]; duplicated rather than reached for
## across the formula/modifier boundary, which points the other way.
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return ("%.2f" % v).trim_suffix("0")
