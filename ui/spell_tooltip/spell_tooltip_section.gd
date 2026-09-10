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

const _LINE := preload("res://ui/spell_tooltip/spell_tooltip_line.tscn")

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
## get [constant SpellTooltipLine.DYNAMIC_COLOR] — the "caster's stats moved
## this" gold accent, e.g. a Cast section's scaled range line. Each row is a
## [SpellTooltipLine] instance, never a bare code-built [code]Label[/code] —
## `.claude/rules/scene-composition.md`.
func bind(lines: PackedStringArray, dynamic_indices: Array[int] = []) -> void:
	for child in _rows.get_children():
		child.queue_free()
	for i in lines.size():
		var text := lines[i]
		if text.is_empty():
			continue
		var line: SpellTooltipLine = _LINE.instantiate()
		_rows.add_child(line)
		line.bind(text, dynamic_indices.has(i))
	visible = _rows.get_child_count() > 0


## Plain-text join of every rendered row — what a char-budget test measures,
## and what a "does this section mention X" assertion greps. Never includes
## the header.
func line_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for child in _rows.get_children():
		out.append((child as SpellTooltipLine).text)
	return out
