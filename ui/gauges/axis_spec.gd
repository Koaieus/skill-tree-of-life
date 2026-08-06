@tool
class_name AxisSpec
extends Resource
## One radar axis: its short label + plot color. Replaces the parallel
## axis_labels/axis_colors arrays [AttributeRadar] used to carry (#241);
## plotted values stay separate (they're runtime state, not spec).
##
## For an axis that plots a stat, build it with [method for_stat] rather than
## passing a literal colour: [member StatDef.tint_color] is the single source of
## truth for attribute colour (see [code].claude/rules/ui-palette.md[/code]), and
## a hand-passed [Color] is a second palette that silently drifts from it.
## The two-arg constructor stays for axes that aren't stats.

## The stat this axis plots, when it plots one. Informational — [member label]
## and [member color] are resolved once by [method for_stat], never recomputed
## and written back (that would compound through editor serialization).
@export var stat_id: StringName = &""
@export var label: String = ""
@export var color: Color = Color.WHITE


func _init(p_label: String = "", p_color: Color = Color.WHITE) -> void:
	label = p_label
	color = p_color


## An axis plotting [param id], with its label and colour taken from the
## registered [StatDef]. Falls back to a truncated id in white when the stat is
## unknown — a radar with a wrong-coloured axis beats one that fails to draw.
static func for_stat(id: StringName) -> AxisSpec:
	var def: StatDef = StatRegistry.get_def(id)
	var spec := AxisSpec.new(
			def.get_abbrev() if def != null else String(id).substr(0, 3).to_upper(),
			def.tint_color if def != null else Color.WHITE)
	spec.stat_id = id
	return spec
