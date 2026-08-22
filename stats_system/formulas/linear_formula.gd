@tool
class_name LinearFormula
extends StatFormula

## Pass-through formula — reads one source stat's value. The modifier's `value`
## field carries any scaling coefficient (effective = modifier.value * source.value),
## so "+2 vision_range per PER" is modifier.value=2 + LinearFormula(perception),
## and "+1% range per DEX" is modifier.value=1 + LinearFormula(dexterity).
##
## Use ExpressionFormula when you need more than one source or nonlinear math
## (e.g. `floor(strength / 10.0)`).
##
## [member source_stat_id] accepts a bare `<stat_id>` (reads the computed
## value / cap — every shipped formula uses this) or a `<stat_id>__<accessor>`
## token to read a stat's extra state via [method Stat.read_accessor]: e.g.
## `&"health__current"` reads the pool's `current`. See #333.

@export var source_stat_id: StringName = &""


func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_LINEAR
	d["source_stat_id"] = source_stat_id
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	source_stat_id = StringName(d.get("source_stat_id", &""))


func get_input_ids() -> Array[StringName]:
	return [StatFormula.base_of(source_stat_id)]


func compute(board: StatBoard) -> float:
	var s := board.get_stat(StatFormula.base_of(source_stat_id))
	if s == null:
		return 0.0
	return float(s.read_accessor(StatFormula.accessor_of(source_stat_id)))


## "PER" — a passthrough has no divisor, so the phrase is just the source.
## An authored [member per_phrase] wins when set.
func describe_per() -> String:
	if not per_phrase.is_empty():
		return per_phrase
	return _abbrev(StatFormula.base_of(source_stat_id))
