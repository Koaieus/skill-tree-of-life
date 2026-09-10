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

	_populate_cast_section()
	_populate_on_arrival_section()
	_populate_then_section()
	_populate_crits_section()


## Section 1 (#764) — fully derived here: [Targeting]/[NodeTargeting] and
## [RangeFinder] live under `attack/targeting/` and `attack/range_finder/`,
## both mine to describe. Who it can hit, then how far.
func _populate_cast_section() -> void:
	var lines: PackedStringArray = []
	var dynamic: Array[int] = []

	if _spell.targeting != null:
		var who := _spell.targeting.get_description()
		if who != "":
			lines.append(who)

	var rf := _resolve_range_finder()
	if rf != null:
		var raw_desc := rf.get_description(null)
		var eff_desc := rf.get_description(_caster_board())
		if eff_desc != "":
			lines.append(eff_desc)
			if eff_desc != raw_desc:
				dynamic.append(lines.size() - 1)

	_cast_section.bind(lines, dynamic)


## Sections 2-4 (#764) — the composed resources they read
## ([OnHitEffect] / crit condition / [PropagationConfig].reducer) live under
## `attack/spell/on_hit/`, `attack/spell/crit/`, `attack/spell/propagation/`,
## none of them mine right now (#850-852 rewrite them onto the final
## `LandingCondition`/`ScaleDamageEffect` shape — see #849). So this reads
## whatever `get_description()` each ALREADY exposes via duck typing and
## renders nothing for the rest; [method SpellTooltipSection.bind] already
## collapses an empty section, so a spell with no describers yet just shows
## fewer sections rather than a blank line.
func _populate_on_arrival_section() -> void:
	var lines: PackedStringArray = []
	for effect in _spell.on_hit_effects:
		if effect != null and effect.has_method(&"get_description"):
			var d: String = effect.get_description()
			if d != "":
				lines.append(d)

	var prop := _spell.propagation
	if prop != null and prop.max_hops > 0 and prop.reducer != null \
			and prop.reducer.has_method(&"get_description"):
		var rd: String = prop.reducer.get_description()
		if rd != "":
			lines.append(rd)

	_on_arrival_section.bind(lines)


## [PropagationConfig] itself is mine to CALL (not to edit) — its
## [method PropagationConfig.get_description] already exists and composes
## filter/step/reducer/hops. A 0-hop or step-less config is single-target in
## every sense that matters here, so that's said plainly rather than via a
## "0 hops" reading of a describer built for the propagating case.
func _populate_then_section() -> void:
	var lines: PackedStringArray = []
	var prop := _spell.propagation
	var propagates := prop != null and prop.step != null and prop.max_hops > 0
	if not propagates:
		lines.append("Single target.")
	else:
		if prop.has_method(&"get_description"):
			var d: String = prop.get_description()
			if d != "":
				lines.append(d)
		if prop.hop_damage != null and prop.hop_damage.has_method(&"get_description"):
			var hd: String = prop.hop_damage.get_description()
			if hd != "":
				lines.append(hd)
	_then_section.bind(lines)


## Same duck-typing as [method _populate_on_arrival_section] — today's
## `CritCondition` subclasses have no `get_description()` yet (#851 adds it on
## `LandingCondition`), so this renders empty/hidden until that lands.
func _populate_crits_section() -> void:
	var lines: PackedStringArray = []
	for cond in _spell.crit_conditions:
		if cond != null and cond.has_method(&"get_description"):
			var d: String = cond.get_description()
			if d != "":
				lines.append(d)
	_crits_section.bind(lines)


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


## The hovered caster's board, or null. Every dynamic number on this tooltip is
## computed by *asking its owner* with this board — the finder for reach, the
## resolver for damage — never by re-deriving the expression here. A private
## copy of the hop-scaling formula is exactly what made the tooltip disagree
## with the game about propagation depth.
func _caster_board() -> StatBoard:
	return _caster.stat_board if _caster != null else null


func _resolve_range_finder() -> RangeFinder:
	if _spell.targeting == null:
		return null
	return _spell.targeting.get(&"range_finder") as RangeFinder


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
