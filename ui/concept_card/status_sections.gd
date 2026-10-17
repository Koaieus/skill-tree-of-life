class_name StatusSections
extends RefCounted

## The ONE derivation of an aspect status's concept-card sections — Summary,
## Decay, Spread, Resisted by — as `{title, lines}` pairs, `lines` a
## [SpellSections.Lines] so [SpellTooltipSection] renders them unchanged.
##
## Mirrors [SpellSections]: every line is asked of the resource that owns it
## ([member StatusDef.description], [method StatusDecay.describe],
## [method StatusSpread.describe], the resistance [StatDef]'s name), never
## re-derived here. Nothing is ever marked dynamic: the card describes the
## concept, not a caster. A section with nothing to say is omitted — except
## Summary and Decay, which every status has.

const SUMMARY := "Summary"
const DECAY := "Decay"
const SPREAD := "Spread"
const RESISTED_BY := "Resisted by"

## Decay's line for a status with no [member StatusDef.decay] (greed, corruption).
const NEVER_FADES := "Never fades on its own."


## The sections for [param status], in reading order; `[]` for null.
static func build(status: StatusDef) -> Array:
	var out: Array = []
	if status == null:
		return out
	_push(out, SUMMARY, status.get_description())
	_push(out, DECAY, status.decay.describe() if status.decay != null else NEVER_FADES)
	if status.spread != null:
		_push(out, SPREAD, status.spread.describe())
	var resist_id := status.resistance_stat_id()
	if resist_id != &"":
		var def: StatDef = StatRegistry.get_def(resist_id)
		if def != null:
			_push(out, RESISTED_BY, def.display_name)
	return out


static func _push(out: Array, title: String, text: String) -> void:
	var lines := SpellSections.Lines.new()
	lines.add(text)
	if not lines.is_empty():
		out.append({title = title, lines = lines})
