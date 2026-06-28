class_name SkillNodeTooltip
extends PanelContainer

## Floating tooltip shown on SkillNode hover.
##
## Subscribes to Events.skill_node_hovered / unhovered. While visible, tracks
## the hovered node's owner_changed signal so the owner line updates live when
## a node is allocated or deallocated without re-hovering, damaged so the node
## HP bar updates as hits land, and — for core nodes — the owning entity's
## health stat so the death-clock bar updates when the core itself takes core
## damage.
##
## HP rendering uses LabeledProgressBar (shared with StatsPanel). Node HP is
## tinted on a red→green hue ramp by ratio; core HP uses the health stat's
## authored tint.
##
## Modifier formatting follows the StatModifier pipeline conventions:
##   ADD_BASE  → "+5 Strength"        (scales with %, the usual node source)
##   INCREASE  → "+20% Dexterity"     (additive % to the multiplier bucket)
##   MULTIPLY  → "×1.5 Intelligence"  (independent multiplier)
##   ADD_BONUS → "+3 Health (flat)"   (post-multiply, won't scale with INCREASE)
##   SET       → "= 13 Perception"    (pipeline bypass)
## Each modifier line is tinted with the stat's tint_color from StatRegistry.

@onready var _owner_label: Label = %OwnerLabel
@onready var _hp_box: VBoxContainer = %HpBox
@onready var _modifiers_box: VBoxContainer = %ModifiersBox

var _node: SkillNode = null
var _core_health_stat: Stat = null


func _ready() -> void:
	hide()
	Events.skill_node_hovered.connect(_on_hovered)
	Events.skill_node_unhovered.connect(_on_unhovered)


func _process(_delta: float) -> void:
	if visible:
		_reposition()


func _on_hovered(node: SkillNode) -> void:
	_bind(node)
	_populate()
	show()
	_reposition()


func _on_unhovered() -> void:
	_unbind()
	hide()


func _bind(node: SkillNode) -> void:
	_unbind()
	_node = node
	_node.owner_changed.connect(_on_owner_changed)
	_node.damaged.connect(_on_damaged)
	# Core nodes also surface the owning entity's health — bind to it so the
	# core-HP bar tracks core damage between hovers.
	if _node.is_core() and _node.owned_by != null:
		var hp := _node.owned_by.stat_board.get_stat(&"health") if _node.owned_by.stat_board != null else null
		if hp != null:
			_core_health_stat = hp
			_core_health_stat.value_changed.connect(_on_core_health_changed)


func _unbind() -> void:
	if _node != null:
		if _node.owner_changed.is_connected(_on_owner_changed):
			_node.owner_changed.disconnect(_on_owner_changed)
		if _node.damaged.is_connected(_on_damaged):
			_node.damaged.disconnect(_on_damaged)
	_node = null
	if _core_health_stat != null:
		if _core_health_stat.value_changed.is_connected(_on_core_health_changed):
			_core_health_stat.value_changed.disconnect(_on_core_health_changed)
		_core_health_stat = null


func _on_owner_changed() -> void:
	_populate()


func _on_damaged(_amount: float, _source: Variant) -> void:
	_populate_hp()


func _on_core_health_changed() -> void:
	_populate_hp()


func _populate() -> void:
	if _node == null:
		return

	if _node.owned_by != null:
		var core_tag := " (core)" if _node.is_core() else ""
		_owner_label.text = _node.owned_by.display_name + core_tag
		_owner_label.modulate = _node.owned_by.color
	else:
		_owner_label.text = "Unallocated"
		_owner_label.modulate = Color(0.55, 0.55, 0.55)

	_populate_hp()

	for child in _modifiers_box.get_children():
		child.queue_free()

	var addon_sections := _node.get_addon_tooltip_sections()

	var has_procgen := _node.has_meta("procgen_footprint")
	if _node.modifiers.is_empty() and addon_sections.is_empty() and not has_procgen:
		var empty := Label.new()
		empty.mouse_filter = MOUSE_FILTER_IGNORE
		empty.text = "(no modifiers)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		empty.add_theme_font_size_override("font_size", 11)
		_modifiers_box.add_child(empty)
		return
	if _node.modifiers.is_empty() and addon_sections.is_empty():
		var empty := Label.new()
		empty.mouse_filter = MOUSE_FILTER_IGNORE
		empty.text = "(no modifiers)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		empty.add_theme_font_size_override("font_size", 11)
		_modifiers_box.add_child(empty)

	for m: StatModifier in _node.modifiers:
		_add_modifier_label(_modifiers_box, m)

	_populate_procgen_debug()

	# Addon-contributed sections (e.g. SkillDust loot payload) below the node's
	# own modifiers — each a heading + its modifier lines.
	for section in addon_sections:
		var title: String = section.get("title", "")
		var mods: Array = section.get("modifiers", [])
		if mods.is_empty():
			continue
		if not title.is_empty():
			var heading := Label.new()
			heading.mouse_filter = MOUSE_FILTER_IGNORE
			heading.text = title
			heading.modulate = Color(0.78, 0.78, 0.84)
			heading.add_theme_font_size_override("font_size", 11)
			_modifiers_box.add_child(heading)
		for m in mods:
			_add_modifier_label(_modifiers_box, m)


func _populate_procgen_debug() -> void:
	if _node == null or not _node.has_meta("procgen_footprint"):
		return
	var fp: Dictionary = _node.get_meta("procgen_footprint")
	var dim := Color(0.45, 0.45, 0.5)

	var heading := Label.new()
	heading.mouse_filter = MOUSE_FILTER_IGNORE
	heading.text = "[procgen]"
	heading.modulate = dim
	heading.add_theme_font_size_override("font_size", 10)
	_modifiers_box.add_child(heading)

	var lines: Array[String] = []
	var phase: String = fp.get("phase", "?")
	var budget: int = fp.get("budget", -1)
	if fp.has("slots"):
		var p: int = fp.get("primary_slots", 0)
		var o: int = fp.get("off_slots", 0)
		lines.append("budget %d · slots %d (%dP+%dO)" % [budget, fp["slots"], p, o])
		if fp.has("peak_primary_cost"):
			lines.append("peak %d · off_cap %d" % [fp["peak_primary_cost"], fp.get("off_cap", 0)])
	elif budget >= 0:
		lines.append("budget %d · phase %s" % [budget, phase])
	var role_tags: Array = fp.get("role_tags", [])
	if not role_tags.is_empty():
		lines.append("role: " + ", ".join(PackedStringArray(role_tags.map(func(t): return String(t)))))

	for line in lines:
		var lbl := Label.new()
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		lbl.text = line
		lbl.modulate = dim
		lbl.add_theme_font_size_override("font_size", 10)
		_modifiers_box.add_child(lbl)


## One tinted modifier line, formatted per the StatModifier pipeline conventions
## documented at the class top. Shared by the node's own modifiers and any
## addon-contributed sections.
func _add_modifier_label(parent: Node, m: StatModifier) -> void:
	var def := StatRegistry.get_def(m.stat_id)
	var stat_name := def.display_name if def != null else String(m.stat_id)
	var tint := def.tint_color if def != null else Color.WHITE
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.text = _format_modifier(m, stat_name)
	label.modulate = tint
	parent.add_child(label)


func _populate_hp() -> void:
	for child in _hp_box.get_children():
		child.queue_free()
	if _node == null or _node.owned_by == null:
		_hp_box.hide()
		return
	var max_hp := _node.get_max_hp()
	if max_hp <= 0.0:
		_hp_box.hide()
		return

	# Node HP bar — hue ramps red (low) → green (full) by ratio.
	var cur := _node.current_hp
	var ratio: float = clampf(cur / max_hp, 0.0, 1.0)
	var node_bar := LabeledProgressBar.create()
	_hp_box.add_child(node_bar)
	node_bar.set_values(
		"Node HP %s/%s" % [_val(cur), _val(max_hp)],
		cur,
		max_hp,
		Color.from_hsv(lerpf(0.0, 0.33, ratio), 0.9, 1.0),
	)

	# Core HP bar — only on core nodes; the death-clock pool that arm-loss
	# overflow drains into. Uses the health stat's authored tint.
	if _core_health_stat != null and _core_health_stat is PoolStat:
		var pool := _core_health_stat as PoolStat
		var def := pool.definition
		var tint: Color = def.tint_color if def != null else Color(0.9, 0.1, 0.1)
		var core_bar := LabeledProgressBar.create()
		_hp_box.add_child(core_bar)
		core_bar.set_values(
			"Core HP %s/%s" % [_val(pool.current), _val(pool.value)],
			float(pool.current),
			float(pool.value),
			tint,
		)

	_hp_box.show()


func _format_modifier(m: StatModifier, stat_name: String) -> String:
	var _sign := "+" if m.value >= 0.0 else ""
	var val := _val(m.value)
	match m.operation:
		StatModifier.Operation.ADD_BASE:
			return _sign + val + " " + stat_name
		StatModifier.Operation.INCREASE:
			return _sign + val + "% " + stat_name
		StatModifier.Operation.MULTIPLY:
			return "×" + val + " " + stat_name
		StatModifier.Operation.ADD_BONUS:
			return _sign + val + " " + stat_name + " (flat)"
		StatModifier.Operation.SET:
			return "= " + val + " " + stat_name
	return val + " " + stat_name


func _val(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.2f" % v


func _reposition() -> void:
	var vp_size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var sz := size
	var pos := mouse + Vector2(16.0, 16.0)
	if pos.x + sz.x > vp_size.x - 4.0:
		pos.x = mouse.x - sz.x - 8.0
	if pos.y + sz.y > vp_size.y - 4.0:
		pos.y = mouse.y - sz.y - 8.0
	set_position(pos)
