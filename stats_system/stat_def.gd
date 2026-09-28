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

## Ids of the stats this one folds under (ADR 0029): a child's read is
## `compute(child.base_value, [ancestors' bins farthest-first…, own bins])` —
## a parent's bins join, its `base_value` never does. Declaration only;
## [code]StatRegistry[/code] flattens the ancestor graph and rejects unknown
## ids and cycles, [StatBoard] wires the per-board links.
@export var parent_ids: Array[StringName] = []

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

## True for a stat where a LOWER value is the improvement (e.g.
## `min_damage_taken`, `dealloc_damage`) — most stats want more, so this
## defaults false. See [method is_improvement]. Pure addition (#729), same
## idiom as [member display_as_percent]; no `NEUTRAL` — no def today wants an
## unjudged delta.
@export var lower_is_better: bool = false


## Short axis/inline label ("Strength" → "STR"). **Authored**, because
## truncation is not abbreviation: it only produces the right answer when the
## short form happens to be the first three letters, which is a coincidence of
## the attributes and not a rule ("Spell Damage" → "SPE", "Constitution" →
## "CON" only by luck). Leave empty to accept the truncation fallback.
@export var abbrev: String = ""


## True iff `delta` moves this stat toward "better" — a DELTA predicate, not
## a judgement of an absolute value (#729). `0.0` is never an improvement
## either way. The one accessor for "is this change good": no call site
## re-derives `sign XOR lower_is_better` by hand.
func is_improvement(delta: float) -> bool:
	if lower_is_better:
		return delta < 0.0
	return delta > 0.0


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


## Single shared formatter (#622) for "a raw float, rendered per a stat's
## declared [enum ValueType]" — the one thing neither [StatValueRow] nor
## [method StatModifier._format_value] consulted before, in opposite-failing
## directions: an INT stat showed decimals (`+39.97 STR`, e.g. from aura
## distance-falloff scaling — see [method EffectContext.grant_at]), a
## FLOAT stat got wrongly `roundi()`'d. Unsigned, no thousands/percent
## handling — callers own sign prefixing and [member display_as_percent].
##
## INT always rounds to a whole number, regardless of an upstream fractional
## artifact. FLOAT goes through [method NumFmt.num] — the same rule
## [StatModifier]'s MULTIPLY/SET use, which are deliberately NOT type-aware. BOOL (#805, the first ValueType with a live consumer —
## `deflection`) renders "True"/"False" rather than a magnitude: a BOOL stat
## is presence, not an amount, so there is no quantity to round or trim.
## Callers wanting the "bare trait line, no sign, no number" grammar a BOOL
## MODIFIER earns ([method StatModifier._format_value]) skip this path
## entirely rather than reading through it — this is the direct-value path
## (e.g. [StatValueRow] binding a stat's own computed value).
static func format_number(value_type: ValueType, v: float) -> String:
	if value_type == ValueType.INT:
		return str(roundi(v))
	if value_type == ValueType.BOOL:
		return "True" if v != 0.0 else "False"
	return NumFmt.num(v)
