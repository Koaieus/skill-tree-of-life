extends Node

## Dev shortcut: press `c` while hovering a SkillNode to yank a debug dump of
## the node (id, archetype, primary_stat, position, owner, hp, modifiers,
## addons) to the system clipboard. Intended to make it easy to paste node
## state into chat / issues / notes.

const _CLIPBOARD_KEY: int = KEY_C

var _hovered: SkillNode = null


func _ready() -> void:
	Events.skill_node_hovered.connect(_on_hovered)
	Events.skill_node_unhovered.connect(_on_unhovered)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode != _CLIPBOARD_KEY:
		return
	if _hovered == null:
		return
	DisplayServer.clipboard_set(_format(_hovered))
	get_viewport().set_input_as_handled()


func _on_hovered(node: SkillNode) -> void:
	_hovered = node


func _on_unhovered() -> void:
	_hovered = null


static func _format(node: SkillNode) -> String:
	var lines: PackedStringArray = []
	lines.append("SkillNode")
	lines.append("  position: (%.1f, %.1f)" % [node.position.x, node.position.y])
	lines.append("  archetype: %s" % String(node.get_meta("base_type", &"")))
	lines.append("  primary_stat: %s" % String(node.get_meta("primary_stat", &"")))
	var owner_name := "(unowned)"
	if node.owned_by != null and node.owned_by is Entity:
		owner_name = (node.owned_by as Entity).display_name
	lines.append("  owned_by: %s" % owner_name)
	lines.append("  hp: %.1f / %.1f" % [node.get_current_hp(), node.get_max_hp()])
	var role_tags: Array = node.get_meta("role_tags", [])
	if not role_tags.is_empty():
		lines.append("  role_tags: %s" % str(role_tags))
	if node.get_meta("keystone", null) != null:
		lines.append("  keystone: yes")
	lines.append("  modifiers (%d):" % node.modifiers.size())
	for m in node.modifiers:
		lines.append("    %s" % _format_modifier(m))
	var addons := _collect_addons(node)
	if not addons.is_empty():
		lines.append("  addons (%d):" % addons.size())
		for a in addons:
			lines.append("    %s" % a)
	return "\n".join(lines)


static func _format_modifier(m: StatModifier) -> String:
	if m == null:
		return "(null)"
	var def: StatDef = StatRegistry.get_def(m.stat_id) if StatRegistry != null else null
	var stat_name := def.display_name if def != null else String(m.stat_id)
	match m.operation:
		StatModifier.Operation.ADD_BASE:
			return "+%s %s" % [_fmt_num(m.value), stat_name]
		StatModifier.Operation.INCREASE:
			return "+%s%% %s" % [_fmt_num(m.value), stat_name]
		StatModifier.Operation.MULTIPLY:
			return "×%s %s" % [_fmt_num(m.value), stat_name]
		StatModifier.Operation.ADD_BONUS:
			return "+%s %s (flat)" % [_fmt_num(m.value), stat_name]
		StatModifier.Operation.SET:
			return "= %s %s" % [_fmt_num(m.value), stat_name]
	return "? %s %s" % [_fmt_num(m.value), stat_name]


static func _fmt_num(v: float) -> String:
	if v == floor(v):
		return "%d" % int(v)
	return "%.2f" % v


static func _collect_addons(node: SkillNode) -> PackedStringArray:
	var out: PackedStringArray = []
	var anchor := node.get_node_or_null("Visuals/AddonAnchor")
	if anchor == null:
		return out
	for child in anchor.get_children():
		if child is SkillNodeAddon:
			out.append(child.get_script().resource_path.get_file().get_basename())
	return out
