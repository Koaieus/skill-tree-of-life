@tool
class_name KeyChip
extends PanelContainer

## The tray's one keyboard-keycap glyph, shown in a button's top-right corner.
##
## Extracted from `attack_mode_button.tscn` (#718 follow-up) once THREE button
## types needed it — the mode tabs, the spell tiles and the melee temp-upgrade
## cards. Per `.claude/rules/scene-composition.md` this is exactly the
## "prefer a .tscn you instantiate" case: one authored look, three consumers,
## zero hand-tuned copies.
##
## [b]Sizing is a property, not a copy (owner call 2026-09-04: "ensure they are
## both legible enough yet not too big compared to the button they sit on").[/b]
## A 96px mode tab and a ~24px-tall upgrade card cannot carry the same 12px
## chip, so [member font_size] / [member h_padding] / [member v_padding] are
## exports the host scene overrides — see [constant COMPACT_FONT_SIZE].
##
## [b]The panel StyleBoxFlat is `resource_local_to_scene`.[/b] [method _repaint]
## writes `border_color` per instance, and an inline SubResource is SHARED
## across every `instantiate()` — without the flag the last chip painted would
## recolour every other chip on screen. See
## `.claude/rules/godot-scene-authoring.md`.

## The tab-sized default, legible on a 64–96px button.
const DEFAULT_FONT_SIZE: int = 12

## What a small tile (the ~24px-tall temp-upgrade card) wants instead.
const COMPACT_FONT_SIZE: int = 9

## The glyph(s) printed on the chip — "Tab", "Q", "3". Empty hides the chip
## entirely, so "this slot has no bound key" is a visible absence rather than
## an empty box.
@export var text: String = "":
	set(v):
		text = v
		_repaint()

## Border + glyph colour. Hosts hand in whatever identity colour they already
## carry (the tab's attribute tint, the card's accent).
@export_color_no_alpha var accent: Color = Color.WHITE:
	set(v):
		accent = v
		_repaint()

@export_range(6, 32, 1) var font_size: int = DEFAULT_FONT_SIZE:
	set(v):
		font_size = v
		_repaint()

@export_range(0, 12, 1) var h_padding: int = 5:
	set(v):
		h_padding = v
		_repaint()

@export_range(0, 12, 1) var v_padding: int = 1:
	set(v):
		v_padding = v
		_repaint()

@onready var _label: Label = %KeyLabel


func _ready() -> void:
	_repaint()


## Idempotent, and a no-op before `_ready` (`_label` is null) — every setter
## calls it and `_ready` calls it once more, the same shape
## `AttackModeButton._apply_tint` already uses.
func _repaint() -> void:
	if _label == null:
		return
	_label.text = text
	_label.modulate = accent
	_label.add_theme_font_size_override(&"font_size", font_size)
	visible = not text.is_empty()
	var sb := get_theme_stylebox(&"panel") as StyleBoxFlat
	if sb == null:
		return
	sb.border_color = accent
	sb.content_margin_left = float(h_padding)
	sb.content_margin_right = float(h_padding)
	sb.content_margin_top = float(v_padding)
	sb.content_margin_bottom = float(v_padding)
