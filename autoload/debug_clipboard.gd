extends Node

## Dev shortcut: press `c` while hovering a SkillNode to yank a debug dump of
## the node (id, archetype, primary_stat, position, owner, hp, modifiers,
## addons) to the system clipboard. Intended to make it easy to paste node
## state into chat / issues / notes.

const _CLIPBOARD_KEY: int = KEY_C
## Dumps the minimap's viewport-box geometry instead of a node (#453). Needs no
## hover — it describes the screen, not a thing under the cursor.
const _MINIMAP_KEY: int = KEY_V

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
	if key.keycode == _MINIMAP_KEY:
		var dump := _minimap_dump()
		if dump != "":
			DisplayServer.clipboard_set(dump)
			print(dump)
			get_viewport().set_input_as_handled()
		return
	if key.keycode != _CLIPBOARD_KEY:
		return
	if _hovered == null:
		return
	DisplayServer.clipboard_set(_format(_hovered))
	get_viewport().set_input_as_handled()


## Walks the tree rather than taking an injected reference: this is a debug
## autoload with no composition seam, and it runs once per key press.
func _minimap_dump() -> String:
	var panel := _find_first(get_tree().root, "MinimapPanel")
	if panel == null:
		return ""
	var layer = panel.viewport_rect_layer
	if layer == null:
		return ""
	return layer.debug_state(_find_first(get_tree().root, "GraphCamera"), panel)


static func _find_first(from: Node, type_name: String) -> Node:
	if from.is_class(type_name) or (from.get_script() != null
			and from.get_script().get_global_name() == type_name):
		return from
	for child in from.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _on_hovered(node: SkillNode) -> void:
	_hovered = node


func _on_unhovered() -> void:
	_hovered = null


static func _format(node: SkillNode) -> String:
	var lines: PackedStringArray = []
	lines.append("SkillNode")
	lines.append("  position: (%.1f, %.1f)" % [node.position.x, node.position.y])
	lines.append("  archetype: %s" % String(node.get_meta("archetype", &"")))
	lines.append("  primary_stat: %s" % String(node.get_meta("primary_stat", &"")))
	var owner_name := "(unowned)"
	if node.owned_by != null and node.owned_by is Entity:
		owner_name = (node.owned_by as Entity).display_name
	lines.append("  owned_by: %s" % owner_name)
	lines.append("  hp: %.1f / %.1f" % [node.get_current_hp(), node.get_max_hp()])
	var role_tags: Array = node.get_meta("role_tags", [])
	if not role_tags.is_empty():
		lines.append("  role_tags: %s" % str(role_tags))
	if node.keystone != null:
		lines.append("  keystone: %s" % node.keystone.display_name)
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
	return m.format()


static func _collect_addons(node: SkillNode) -> PackedStringArray:
	var out: PackedStringArray = []
	for addon in node.get_addons():
		out.append(addon.get_script().resource_path.get_file().get_basename())
	return out
