@tool
class_name SpellTooltipSection
extends VBoxContainer

## One of [SpellTooltip]'s four marked sections (#764) — Cast / On arrival /
## Then / Crits, each an instance of this SAME scene: an all-caps header
## label over a stack of plain-text rows. A dumb rendering shell on purpose —
## it holds no [SpellDef] knowledge of its own; the composer (currently
## [SpellTooltip], later the #853 spell catalogue) derives the lines from
## whatever resources are composed on the def and hands them to
## [method bind]. That split is what makes the scene reusable outside the
## HUD: the derivation lives with whoever is asking the question, the
## rendering lives here once.
##
## A section with no lines COLLAPSES entirely (hidden, no reserved space) —
## the Crits section is empty on most spells today, and every section is
## empty for a caster-less/effect-less fixture in a test.

const _ROW_FONT_SIZE: int = 11

## Accent worn by a row the composer marks dynamic — the caster's own stats
## moved this value off the spell's printed base. Matches
## [constant SpellTooltip.DYNAMIC_COLOR]; kept as its own constant rather than
## a cross-scene reference, same reasoning [SpellStatRow] documents for its
## own palette pulls.
const DYNAMIC_COLOR: Color = Color(1.0, 0.85, 0.4)

@onready var _header_label: Label = %HeaderLabel
@onready var _rows: VBoxContainer = %Rows

## Scene-authored section title ("CAST", "ON ARRIVAL", "THEN", "CRITS") — set
## per-instance in [code]spell_tooltip.tscn[/code] so the four sections don't
## need four separate scenes.
@export_placeholder("SECTION") var header_text: String = "":
	set(v):
		header_text = v.to_upper()
		if _header_label:
			_header_label.text = header_text


func _ready() -> void:
	_header_label.text = header_text


## Populate this section's rows and show/hide it as a whole. [param lines] is
## plain player-facing text, one per row, in the order the composer wants
## them read. [param dynamic_indices] names which entries in [param lines]
## get [constant DYNAMIC_COLOR] — the same "caster's stats moved this" accent
## [SpellStatRow] uses, e.g. a Cast section's scaled range line.
func bind(lines: PackedStringArray, dynamic_indices: Array[int] = []) -> void:
	for child in _rows.get_children():
		child.queue_free()
	for i in lines.size():
		var text := lines[i]
		if text.is_empty():
			continue
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", _ROW_FONT_SIZE)
		label.theme_type_variation = &"TierInert"
		if dynamic_indices.has(i):
			label.add_theme_color_override(&"font_color", DYNAMIC_COLOR)
		_rows.add_child(label)
	visible = _rows.get_child_count() > 0


## Plain-text join of every rendered row — what a char-budget test measures,
## and what a "does this section mention X" assertion greps. Never includes
## the header.
func line_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for child in _rows.get_children():
		out.append((child as Label).text)
	return out
