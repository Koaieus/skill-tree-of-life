@tool
class_name StatDef
extends Resource

## Per-stat blueprint. Each .tres file in stats_system/defs/ IS one stat's
## identity (id, display, type). The runtime instance is created from this.
## See docs/design/stat_system.md.

enum ValueType { INT, FLOAT, BOOL }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var value_type: ValueType = ValueType.INT
@export var default_value: float = 0.0
@export var tint_color: Color = Color.WHITE

## Noun phrase used when a modifier targeting this stat is described in words
## ("Max Action Points"). Empty falls back to display_name. Applies to every
## [enum StatModifier.Operation] — a pool's cap is what a modifier always
## targets, regardless of op. See [method StatModifier.format].
@export var modifier_name: String = ""

## When true, [method StatModifier.format] renders the value ×100 with a "%"
## suffix — for stats whose natural unit is a probability/percentage rather
## than an amount. Applies to ADD_BASE / ADD_BONUS / SET only: INCREASE and
## MULTIPLY values are already percent-points / raw multipliers, not
## quantities in the stat's own units, so scaling them here would be wrong
## (crit_chance INCREASE 18 must stay "+18%", not "+1800%").
@export var display_as_percent: bool = false


## Short axis/inline label ("Strength" → "STR"). **Authored**, because
## truncation is not abbreviation: it only produces the right answer when the
## short form happens to be the first three letters, which is a coincidence of
## the attributes and not a rule ("Spell Damage" → "SPE", "Constitution" →
## "CON" only by luck). Leave empty to accept the truncation fallback.
@export var abbrev: String = ""


## [member abbrev] if authored, else the first three letters of
## [member display_name] upper-cased (or of [member id] when there's no display
## name). Centralised here (#289) so generated formula prose ("+1 Blade Size
## per 20 STR") reads identically to the panel it sits next to.
func get_abbrev() -> String:
	if not abbrev.is_empty():
		return abbrev
	if display_name.is_empty():
		return String(id).substr(0, 3).to_upper()
	return display_name.substr(0, 3).to_upper()
