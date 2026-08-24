@tool
class_name SpellStatRow
extends HBoxContainer

## One "label — value" line in the [SpellTooltip], e.g. [code]Damage    24[/code].
##
## Deliberately NOT [StatValueRow] (`ui/tooltip_fan/`): that one binds a required
## [StatDef] and is driven by the fan's reveal clock, while a spell row is mostly
## free text about a spell's *behaviour* ("Target · Enemy-occupied node") carrying
## a per-row accent the composer picks. If a spell row ever collapses to a
## StatDef-only contract, [StatValueRow] is the merge target — don't grow a second
## StatDef renderer in here.
##
## Every field is an [code]@export[/code] with a push-setter, so a row can be
## authored and tuned entirely in the inspector; [method bind] is the same thing
## for code. Colours come from the theme's Tier* variations (name = TierInert,
## the at-threshold reading that never blooms; value = TierValue) and any accent
## is raised through [Emissive] — never a hand-picked HDR float, per
## `.claude/rules/hdr-color.md`, and by NAMED TIER from a dropdown rather than a
## number, so a row cannot quietly start blooming.

## Left-hand label. Ignored when [member stat_id] names a registered stat.
@export_placeholder("Damage") var row_label: String = "":
	set(v):
		row_label = v
		if _name_label != null and stat_id.is_empty():
			_name_label.text = v

## Right-hand value. Free text — a row prints "3 hops" as readily as "24".
@export_placeholder("0") var value: String = "":
	set(v):
		value = v
		if _value_label != null:
			_value_label.text = v

## Optional stat identity. When set, the row takes BOTH its label text and its
## accent from the registered [StatDef] — so a mana row spells the stat's own
## name and wears its palette colour without the composer restating either.
@export var stat_id: StringName = &"":
	set(v):
		stat_id = v
		_apply_stat_def()

## Accent for the value, raised to [member accent_tier] on the way to the label.
## Alpha 0 (the default) means "no accent" — the value keeps the theme's
## TierValue reading. Overwritten when [member stat_id] resolves.
@export var accent_color: Color = Color(1.0, 1.0, 1.0, 0.0):
	set(v):
		accent_color = v
		_apply_accent()

## How hard the accent burns. LABEL is a whisper that sits at the bloom
## threshold; VALUE and above actually glow, so they are a claim on the palette
## — see `.claude/rules/hdr-color.md` and the gold register in
## `.claude/rules/ui-palette.md` before reaching past LABEL.
@export_enum("Inert", "Label", "Value", "Alert") var accent_tier: int = TIER_LABEL:
	set(v):
		accent_tier = v
		_apply_accent()

## Marks the row as *the* thing to read — used for values the caster's stats
## moved off the spell's printed base. Costs font size, not glow: brightness is
## [member accent_tier]'s job and stays a deliberate choice.
@export var emphasis: bool = false:
	set(v):
		emphasis = v
		_apply_accent()

## Font size bump applied on top of the scene-authored value size when
## [member emphasis] is on.
@export_range(0, 8, 1) var emphasis_size_bump: int = 2:
	set(v):
		emphasis_size_bump = v
		_apply_accent()

## `accent_tier` dropdown index → the [Emissive] stop it names.
const TIER_STOPS: Array[float] = [
	Emissive.INERT, Emissive.LABEL, Emissive.VALUE, Emissive.ALERT
]
const TIER_LABEL: int = 1
const TIER_VALUE: int = 2

@onready var _name_label: Label = %NameLabel
@onready var _value_label: Label = %ValueLabel

# The scene-authored value font size, captured before emphasis can overwrite it.
var _base_value_size: int = 0


## Scene-authored export values land before the [code]@onready[/code] refs are
## live, so the setters above skip their push (that is what their null guards
## are for — not dropping the value). Re-apply once the labels exist. Same
## ordering trap [PanelHeader] documents.
func _ready() -> void:
	_base_value_size = _value_label.get_theme_font_size(&"font_size")
	_value_label.text = value
	if stat_id.is_empty():
		_name_label.text = row_label
		_apply_accent()
	else:
		_apply_stat_def()


## Code-side equivalent of authoring the exports. Pass an [param accent] with
## alpha 0 to leave the value on the theme reading.
func bind(
	label: String,
	value_text: String,
	accent: Color = Color(1.0, 1.0, 1.0, 0.0),
	emphasise: bool = false,
	tier: int = TIER_LABEL
) -> void:
	row_label = label
	value = value_text
	accent_color = accent
	accent_tier = tier
	emphasis = emphasise


func _apply_stat_def() -> void:
	if stat_id.is_empty():
		if _name_label != null:
			_name_label.text = row_label
		return
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def == null:
		return
	if _name_label != null:
		_name_label.text = def.display_name
	accent_color = def.tint_color


func _apply_accent() -> void:
	if _value_label == null:
		return
	# Never *remove* the size override — the scene authors one, and dropping it
	# would silently fall back to the theme default. Re-assert the captured
	# base instead.
	var bump := emphasis_size_bump if emphasis else 0
	_value_label.add_theme_font_size_override(&"font_size", _base_value_size + bump)
	if accent_color.a <= 0.0:
		_value_label.remove_theme_color_override(&"font_color")
		return
	var stops: float = TIER_STOPS[clampi(accent_tier, 0, TIER_STOPS.size() - 1)]
	_value_label.add_theme_color_override(&"font_color", Emissive.at(accent_color, stops))
