class_name SpellTooltip
extends MarginContainer

## Floating tooltip shown on [SpellPickerButton] hover. Follows the
## [TooltipFan] pattern: subscribes to global [code]Events[/code]
## signals, auto-positions at the mouse cursor, and formats all
## [SpellDef] fields. Values that change based on the caster's stats
## (e.g. cast range scaled by [code]spell_range[/code]) are highlighted in
## gold.
##
## Reusable outside the HUD: instantiate the scene, call [method show_for] with
## the spell and an optional caster entity, then [method hide_tooltip] on exit.

## Gold accent for a caster-scaled value lives on
## [constant SpellTooltipSection.DYNAMIC_COLOR] — the section rows are the only
## place one still renders (#764 collapsed the old per-row [SpellStatRow]
## grid into the four derived sections). Gold reads as "this is yours" — a
## pure positive, the only register `.claude/rules/ui-palette.md` allows it
## in.

@onready var _header: PanelHeader = %Header
@onready var _mana_label: Label = %ManaLabel
@onready var _tagline_label: Label = %TaglineLabel
@onready var _cast_section: SpellTooltipSection = %CastSection
@onready var _on_arrival_section: SpellTooltipSection = %OnArrivalSection
@onready var _then_section: SpellTooltipSection = %ThenSection
@onready var _crits_section: SpellTooltipSection = %CritsSection

var _spell: SpellDef = null
var _caster: Entity = null


func _ready() -> void:
	hide()
	# Pin the width before anything is ever measured — see [method _fit].
	size = Vector2(maxf(custom_minimum_size.x, 1.0), 0.0)
	_tint_mana_label()
	Events.spell_hovered.connect(_on_spell_hovered)
	Events.spell_unhovered.connect(_on_spell_unhovered)


## Now drawn above [PauseMenu] (#765), so a tooltip left showing when Esc hits
## must hide rather than freeze mid-air on top of the dimmed menu: `_process`
## (which drives [method _fit]/[method _reposition]) stops the instant the
## tree pauses, same as [SpellPickerButton]'s `mouse_exited` (the hover
## source), so nothing would otherwise clear it. `NOTIFICATION_PAUSED` still
## reaches a PAUSABLE node's `_notification` even though its process
## callbacks are suspended.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		hide_tooltip()


func _process(_delta: float) -> void:
	if visible:
		_fit()
		_reposition()


func _on_spell_hovered(spell: SpellDef, caster: Entity) -> void:
	show_for(spell, caster)


func _on_spell_unhovered() -> void:
	hide_tooltip()


## Populate and show the tooltip for [param spell], optionally accounting
## for [param caster]'s stats that modify spell behaviour.
func show_for(spell: SpellDef, caster: Entity = null) -> void:
	_spell = spell
	_caster = caster
	# Fade in from transparent rather than showing straight away: the layout
	# system needs a couple of frames to settle the autowrap heights (see
	# [method _fit]) and a visible panel would flash viewport-tall meanwhile.
	# It must be *visible* while settling, though — a hidden Control skips
	# layout entirely, so its Labels never re-shape and the fit never converges.
	modulate.a = 0.0
	_populate()
	show()
	for _i in 2:
		_fit()
		await get_tree().process_frame
		if _spell != spell:
			return  # unhovered, or moved to another spell, while we settled
	_fit()
	_reposition()
	modulate.a = 1.0


func hide_tooltip() -> void:
	_spell = null
	_caster = null
	hide()


func _populate() -> void:
	if _spell == null:
		return

	_header.bind(_spell.name, "Requires degree ≥ %d" % _spell.min_degree)
	_mana_label.text = "◈ %d" % _spell.mana_cost

	if _spell.tagline != "":
		_tagline_label.text = _spell.tagline
		_tagline_label.show()
	else:
		_tagline_label.hide()

	_populate_sections()


## The four marked sections (#764) — derived ONCE, in [SpellSections], and
## shared with the spell catalogue (#853): this tooltip hands the caster's
## board over so caster-moved numbers come back marked dynamic (gold); the
## catalogue passes none and gets base numbers. Nothing about a spell is
## derived in this file.
func _populate_sections() -> void:
	var sections := SpellSections.build(_spell, _caster_board())
	_cast_section.bind(sections.cast.lines, sections.cast.dynamic)
	_on_arrival_section.bind(sections.on_arrival.lines, sections.on_arrival.dynamic)
	_then_section.bind(sections.then.lines, sections.then.dynamic)
	_crits_section.bind(sections.crits.lines, sections.crits.dynamic)


## The mana chip wears the Mana stat's own palette colour — [StatDef.tint_color]
## is the single source of truth for it (`.claude/rules/ui-palette.md`), so the
## scene authors the size and this authors the hue, once.
func _tint_mana_label() -> void:
	var def: StatDef = StatRegistry.get_def(&"mana")
	if def == null:
		return
	_mana_label.add_theme_color_override(
		&"font_color", Emissive.at(def.tint_color, Emissive.LABEL)
	)


## The hovered caster's board, or null — what [SpellSections] asks each
## resource's describer with, so every dynamic number is the owner's own
## (the finder for reach, the effect for damage), never re-derived here.
func _caster_board() -> StatBoard:
	return _caster.stat_board if _caster != null else null


## Re-fit the free-floating panel to its content width-first. Two layout facts
## make this mandatory rather than cosmetic: a Control never *shrinks* back when
## its minimum size drops, and an autowrap [Label] measures its height by
## wrapping at its CURRENT width — so the very first layout (width 0) wraps the
## description one word per line and balloons the panel to thousands of pixels,
## a height it then keeps for every spell hovered afterwards. Pinning the width
## (authored as [member Control.custom_minimum_size].x on the scene root, so it
## stays tunable in the editor) and clamping the height to the recomputed
## minimum converges within a frame.
func _fit() -> void:
	var width := maxf(custom_minimum_size.x, 1.0)
	var min_h := get_combined_minimum_size().y
	if is_equal_approx(size.x, width) and size.y <= min_h + 0.5:
		return
	# set_size() clamps against the combined minimum, so a 0 height means
	# "exactly as tall as the content needs at this width".
	size = Vector2(width, 0.0)


func _reposition() -> void:
	var vp_size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var sz := size
	# Preferred: below-right of cursor.
	var pos := mouse + Vector2(16.0, 16.0)
	# Flip horizontal if off right edge.
	if pos.x + sz.x > vp_size.x:
		pos.x = mouse.x - sz.x - 8.0
	# Flip vertical if off bottom edge.
	if pos.y + sz.y > vp_size.y:
		pos.y = mouse.y - sz.y - 8.0
	# Clamp so the tooltip never goes off-screen in any direction.
	pos.x = clampf(pos.x, 4.0, vp_size.x - sz.x - 4.0)
	pos.y = clampf(pos.y, 4.0, vp_size.y - sz.y - 4.0)
	set_position(pos)
