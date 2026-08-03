class_name SpellTooltip
extends PanelContainer

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

const DYNAMIC_COLOR: Color = Color(1.0, 0.85, 0.4)

@onready var _name_label: Label = %NameLabel
@onready var _min_degree_label: Label = %MinDegreeLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _stats_grid: VBoxContainer = %StatsGrid
@onready var _propagation_label: Label = %PropagationLabel

var _spell: SpellDef = null
var _caster: Entity = null


func _ready() -> void:
	hide()
	Events.spell_hovered.connect(_on_spell_hovered)
	Events.spell_unhovered.connect(_on_spell_unhovered)


func _process(_delta: float) -> void:
	if visible:
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
	_populate()
	show()
	_reposition()


func hide_tooltip() -> void:
	_spell = null
	_caster = null
	hide()


func _populate() -> void:
	if _spell == null:
		return

	_name_label.text = "%s — %d Mana" % [_spell.name, _spell.mana_cost]
	_min_degree_label.text = "Requires Degree ≥ %d" % _spell.min_degree
	_min_degree_label.modulate = Color(0.7, 0.7, 0.75)

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

	var seed := _seed_damage()
	_add_stat_row(&"Damage", _format_num(seed), not is_equal_approx(seed, _spell.power))

	if has_prop:
		var prop := _spell.propagation
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


func _add_stat_row(label: StringName, value: String, dynamic: bool) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	lbl.text = String(label)
	lbl.modulate = Color(0.7, 0.7, 0.75)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.mouse_filter = MOUSE_FILTER_IGNORE
	val.text = value
	val.modulate = DYNAMIC_COLOR if dynamic else Color.WHITE
	if dynamic:
		val.add_theme_color_override(&"font_color", DYNAMIC_COLOR)
		val.add_theme_font_size_override(&"font_size", 14)
	row.add_child(val)

	_stats_grid.add_child(row)


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


## Seed damage for the hovered caster — [code]spell_damage × power[/code], the
## same expression [SpellResolver] seeds with (D-32). The raw
## [member SpellDef.power] coefficient is meaningless on its own, so the row
## shows the computed number and goes gold whenever the caster moved it.
func _seed_damage() -> float:
	if _caster == null or _caster.stat_board == null:
		return _spell.power
	var s := _caster.stat_board.get_stat(&"spell_damage")
	return _spell.power * (float(s.get_value()) if s != null else 1.0)


func _spell_range_multiplier() -> float:
	if _caster == null or _caster.stat_board == null:
		return 1.0
	var s := _caster.stat_board.get_stat(&"spell_range")
	if s == null:
		return 1.0
	return 1.0 + float(s.value) / 100.0


func _resolve_range_finder() -> RangeFinder:
	if _spell.targeting == null:
		return null
	return _spell.targeting.get(&"range_finder") as RangeFinder


func _targeting_description(t: Targeting) -> String:
	if t is SingleHostileNodeTargeting:
		return "Enemy-occupied node"
	if t is SingleAlliedNodeTargeting:
		return "Own node"
	return "Single node"


func _format_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.1f" % v


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
