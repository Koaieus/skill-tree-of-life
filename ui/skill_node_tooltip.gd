class_name SkillNodeTooltip
extends PanelContainer

## Floating tooltip shown on SkillNode hover.
##
## Subscribes to Events.skill_node_hovered / unhovered. While visible, tracks
## the hovered node's owner_changed signal so the owner line updates live when
## a node is allocated or deallocated without re-hovering, and damaged so the
## HP line updates as hits land.
##
## Modifier formatting follows the StatModifierDef pipeline conventions:
##   ADD_BASE  → "+5 Strength"        (scales with %, the usual node source)
##   INCREASE  → "+20% Dexterity"     (additive % to the multiplier bucket)
##   MULTIPLY  → "×1.5 Intelligence"  (independent multiplier)
##   ADD_BONUS → "+3 Health (flat)"   (post-multiply, won't scale with INCREASE)
##   SET       → "= 13 Perception"    (pipeline bypass)
## Each modifier line is tinted with the stat's tint_color from StatRegistry.

@onready var _owner_label: Label = %OwnerLabel
@onready var _hp_label: Label = %HpLabel
@onready var _modifiers_box: VBoxContainer = %ModifiersBox

var _node: SkillNode = null


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


func _unbind() -> void:
	if _node != null:
		if _node.owner_changed.is_connected(_on_owner_changed):
			_node.owner_changed.disconnect(_on_owner_changed)
		if _node.damaged.is_connected(_on_damaged):
			_node.damaged.disconnect(_on_damaged)
	_node = null


func _on_owner_changed() -> void:
	_populate()


func _on_damaged(_amount: float, _source: Variant) -> void:
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

	if _node.modifiers.is_empty():
		var empty := Label.new()
		empty.mouse_filter = MOUSE_FILTER_IGNORE
		empty.text = "(no modifiers)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		empty.add_theme_font_size_override("font_size", 11)
		_modifiers_box.add_child(empty)
		return

	for m: StatModifierDef in _node.modifiers:
		var def := StatRegistry.get_def(m.stat_id)
		var stat_name := def.display_name if def != null else String(m.stat_id)
		var tint := def.tint_color if def != null else Color.WHITE

		var label := Label.new()
		label.mouse_filter = MOUSE_FILTER_IGNORE
		label.text = _format_modifier(m, stat_name)
		label.modulate = tint
		_modifiers_box.add_child(label)


func _populate_hp() -> void:
	if _node == null or _node.owned_by == null:
		_hp_label.hide()
		return
	var max_hp := _node.get_max_hp()
	if max_hp <= 0.0:
		_hp_label.hide()
		return
	var cur := _node.current_hp
	var ratio: float = clampf(cur / max_hp, 0.0, 1.0)
	# Hue 0.0 = red, 0.33 = green; passes through orange/yellow at ~0.5.
	_hp_label.text = "HP %s/%s" % [_val(cur), _val(max_hp)]
	_hp_label.modulate = Color.from_hsv(lerpf(0.0, 0.33, ratio), 0.9, 1.0)
	_hp_label.show()


func _format_modifier(m: StatModifierDef, stat_name: String) -> String:
	var _sign := "+" if m.value >= 0.0 else ""
	var val := _val(m.value)
	match m.operation:
		StatModifierDef.Operation.ADD_BASE:
			return _sign + val + " " + stat_name
		StatModifierDef.Operation.INCREASE:
			return _sign + val + "% " + stat_name
		StatModifierDef.Operation.MULTIPLY:
			return "×" + val + " " + stat_name
		StatModifierDef.Operation.ADD_BONUS:
			return _sign + val + " " + stat_name + " (flat)"
		StatModifierDef.Operation.SET:
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
