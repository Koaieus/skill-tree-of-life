class_name SkillNodeTooltip
extends PanelContainer

## Floating tooltip shown on SkillNode hover.
##
## Subscribes to Events.skill_node_hovered / unhovered. While visible, tracks
## the hovered node's owner_changed signal so the owner line updates live when
## a node is allocated or deallocated without re-hovering.
##
## Modifier formatting follows the StatModifierDef pipeline conventions:
##   ADD_BASE  → "+5 Strength"        (scales with %, the usual node source)
##   INCREASE  → "+20% Dexterity"     (additive % to the multiplier bucket)
##   MULTIPLY  → "×1.5 Intelligence"  (independent multiplier)
##   ADD_BONUS → "+3 Health (flat)"   (post-multiply, won't scale with INCREASE)
##   SET       → "= 13 Perception"    (pipeline bypass)
## Each modifier line is tinted with the stat's tint_color from StatRegistry.

@onready var _owner_label: Label = %OwnerLabel
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


func _unbind() -> void:
	if _node != null and _node.owner_changed.is_connected(_on_owner_changed):
		_node.owner_changed.disconnect(_on_owner_changed)
	_node = null


func _on_owner_changed() -> void:
	_populate()


func _populate() -> void:
	if _node == null:
		return

	if _node.owned_by != null:
		_owner_label.text = _node.owned_by.display_name
		_owner_label.modulate = _node.owned_by.color
	else:
		_owner_label.text = "Unallocated"
		_owner_label.modulate = Color(0.55, 0.55, 0.55)

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


func _format_modifier(m: StatModifierDef, stat_name: String) -> String:
	var _sign := "+" if m.value >= 0.0 else ""
	match m.operation:
		StatModifierDef.Operation.ADD_BASE:
			return "%s%g %s" % [_sign, m.value, stat_name]
		StatModifierDef.Operation.INCREASE:
			return "%s%g%% %s" % [_sign, m.value, stat_name]
		StatModifierDef.Operation.MULTIPLY:
			return "×%g %s" % [m.value, stat_name]
		StatModifierDef.Operation.ADD_BONUS:
			return "%s%g %s (flat)" % [_sign, m.value, stat_name]
		StatModifierDef.Operation.SET:
			return "= %g %s" % [m.value, stat_name]
	return "%g %s" % [m.value, stat_name]


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
