class_name SpellTooltip
extends MarginContainer

## Floating tooltip shown on [SpellPickerButton] hover. Follows the
## [TooltipFan] pattern: subscribes to global [code]Events[/code]
## signals, auto-positions at the mouse cursor, and formats all
## [SpellDef] fields. Values that change based on the caster's stats
## (e.g. hops scaled by [code]spell_range[/code]) are highlighted in
## gold.
##
## Reusable: both the spell bar (runtime) and spell playground (editor
## plugin) can instantiate this scene, call [method show_for] with the
## spell and optional caster entity, then [method hide_tooltip] on exit.

## Accent worn by any value the caster's own stats moved off the spell's
## printed base. Gold reads as "this is yours" — a pure positive, which is the
## only register `.claude/rules/ui-palette.md` allows it in.
const DYNAMIC_COLOR: Color = Color(1.0, 0.85, 0.4)

const _ROW := preload("res://ui/spell_tooltip/spell_stat_row.tscn")

@onready var _header: PanelHeader = %Header
@onready var _mana_label: Label = %ManaLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _stats_grid: VBoxContainer = %StatsGrid
@onready var _propagation_label: Label = %PropagationLabel

var _spell: SpellDef = null
var _caster: Entity = null


func _ready() -> void:
	hide()
	# Pin the width before anything is ever measured — see [method _fit].
	size = Vector2(maxf(custom_minimum_size.x, 1.0), 0.0)
	_tint_mana_label()
	Events.spell_hovered.connect(_on_spell_hovered)
	Events.spell_unhovered.connect(_on_spell_unhovered)


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

	if _spell.description != "":
		_description_label.text = _spell.description
		_description_label.show()
	else:
		_description_label.hide()

	for child in _stats_grid.get_children():
		child.queue_free()

	var has_prop := _spell.propagation != null
	var base_hops := _spell.propagation.max_hops if has_prop else 0
	var eff_hops := _effective_hops()
	var hops_dynamic := has_prop and eff_hops != base_hops

	var impact := _impact_damage()
	_add_stat_row(&"Damage", _format_num(impact), not is_equal_approx(impact, _spell.power))

	if has_prop:
		var prop := _spell.propagation
		# A 0-hop propagation is impact-only — printing "Hops 0" is noise.
		if eff_hops > 0:
			var hops_text := str(eff_hops)
			if hops_dynamic:
				hops_text = "%d (base %d)" % [eff_hops, base_hops]
			_add_stat_row(&"Hops", hops_text, hops_dynamic)

		if prop.hop_damage != null:
			var hd := prop.hop_damage.get_description()
			if hd != "":
				_add_stat_row(&"Progression", hd, false)

		var prop_desc := prop.get_description()
		if prop_desc != "":
			_propagation_label.text = prop_desc
			_propagation_label.modulate = Color(0.7, 0.85, 1.0)
			_propagation_label.show()
		else:
			_propagation_label.hide()
	else:
		_propagation_label.hide()

	# Range info from the targeting's range_finder (if any).
	var rf := _resolve_range_finder()
	if rf != null:
		if rf is HopRangeFinder:
			var hrf := rf as HopRangeFinder
			var base_r: int = hrf.max_hops
			var eff_r: int = _effective_hops_from_finder(hrf)
			var r_dynamic: bool = eff_r != base_r
			_add_stat_row(&"Range", "%d hop%s" % [eff_r, "" if eff_r == 1 else "s"], r_dynamic)
		elif rf is EuclideanRangeFinder:
			var erf := rf as EuclideanRangeFinder
			var base_r: float = erf.max_distance
			var eff_r: float = _effective_distance_from_finder(erf)
			var r_dynamic: bool = not is_equal_approx(eff_r, base_r)
			_add_stat_row(&"Range", _format_num(eff_r), r_dynamic)

	# Target kind
	if _spell.targeting != null:
		var target_desc := _targeting_description(_spell.targeting)
		if target_desc != "":
			_add_stat_row(&"Target", target_desc, false)


## Append one [SpellStatRow]. `dynamic` marks a value the caster's stats moved
## off the spell's printed base — the row then wears [constant DYNAMIC_COLOR].
func _add_stat_row(label: StringName, value: String, dynamic: bool) -> void:
	var row: SpellStatRow = _ROW.instantiate()
	_stats_grid.add_child(row)
	row.bind(
		String(label),
		value,
		DYNAMIC_COLOR if dynamic else Color(1.0, 1.0, 1.0, 0.0),
		dynamic
	)


## The mana chip wears the Mana stat's own palette colour — [StatDef.tint_color]
## is the single source of truth for it (`.claude/rules/ui-palette.md`), so the
## scene authors the size and this authors the hue, once.
func _tint_mana_label() -> void:
	var def: StatDef = StatRegistry.get_def(&"mana")
	if def == null:
		return
	_mana_label.add_theme_color_override(
		&"font_color", Emissive.at(def.tint_color, Emissive.VALUE)
	)


## Effective max_hops from PropagationConfig, scaled by the caster's
## spell_range stat (same formula as HopRangeFinder._effective_max_hops).
func _effective_hops() -> int:
	if _caster == null or _caster.stat_board == null or _spell.propagation == null:
		return _spell.propagation.max_hops if _spell.propagation != null else 0
	return _scale_by_spell_range(_spell.propagation.max_hops)


func _effective_hops_from_finder(rf: HopRangeFinder) -> int:
	if _caster == null or _caster.stat_board == null:
		return rf.max_hops
	return _scale_by_spell_range(rf.max_hops)


func _effective_distance_from_finder(rf: EuclideanRangeFinder) -> float:
	if _caster == null or _caster.stat_board == null:
		return rf.max_distance
	var mult := _spell_range_multiplier()
	return rf.max_distance * mult


func _scale_by_spell_range(base: int) -> int:
	return int(round(float(base) * _spell_range_multiplier()))


## Impact damage for the hovered caster (D-32) — delegated to
## [method SpellResolver.impact_damage], which owns the expression. The raw
## [member SpellDef.power] coefficient is meaningless on its own, so the row
## shows the computed number and goes gold whenever the caster moved it.
func _impact_damage() -> float:
	var board: StatBoard = _caster.stat_board if _caster != null else null
	return SpellResolver.impact_damage(_spell, null, board)


## Reach multiplier for the hovered caster — delegated to
## [method SpellRangeRules.multiplier], which owns the rule. No cast-from node
## is picked while hovering, so this takes the board path and therefore misses
## node-local range addons; the finder itself reads them node-locally at cast.
func _spell_range_multiplier() -> float:
	var board: StatBoard = _caster.stat_board if _caster != null else null
	return SpellRangeRules.multiplier(null, null, board)


func _resolve_range_finder() -> RangeFinder:
	if _spell.targeting == null:
		return null
	return _spell.targeting.get(&"range_finder") as RangeFinder


func _targeting_description(t: Targeting) -> String:
	# #384: the two Single*NodeTargeting subclasses collapsed into one
	# NodeTargeting keyed by ownership_filter — describe by filter value,
	# not by subclass.
	if t is NodeTargeting:
		match (t as NodeTargeting).ownership_filter:
			SkillNode.Ownership.HOSTILE:
				return "Enemy-occupied node"
			SkillNode.Ownership.MINE:
				return "Own node"
			SkillNode.Ownership.ALLY:
				return "Ally node"
	return "Single node"


func _format_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.1f" % v


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
