@tool
class_name SpellTooltipLine
extends Label

## One row inside a [SpellTooltipSection] — a single autowrapped sentence,
## e.g. "Hits enemy-occupied nodes." or "Within 3 hops". Its own scene (#764
## review) rather than a code-built [code]Label.new()[/code] per row:
## `.claude/rules/scene-composition.md` wants a `.tscn` you instantiate over a
## code-composed tree. A section row is one free-text sentence, no
## label/value split — the two-column [code]SpellStatRow[/code] it replaced
## didn't fit that shape.

## Accent worn when the composer marks this row dynamic — the caster's own
## stats moved the value it reports off the spell's printed base. Gold reads
## as "this is yours" — a pure positive, the only register
## `.claude/rules/ui-palette.md` allows it in.
const DYNAMIC_COLOR: Color = Color(1.0, 0.85, 0.4)

@export var dynamic: bool = false:
	set(v):
		dynamic = v
		_apply_accent()


func _ready() -> void:
	_apply_accent()


func bind(text_: String, dynamic_: bool = false) -> void:
	text = text_
	dynamic = dynamic_


func _apply_accent() -> void:
	if dynamic:
		add_theme_color_override(&"font_color", DYNAMIC_COLOR)
	else:
		remove_theme_color_override(&"font_color")
