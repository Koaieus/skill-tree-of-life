@tool
class_name AddonTile
extends PanelContainer

## One tile in the [member dev_addon_gallery] grid: a SkillNode wearing a single
## addon, with a name label. Scene-authored (was procedural node composition) so
## the layout is editor-tunable. Call [method configure] after the tile is in the
## tree.

const SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const LABEL_HEIGHT := 24.0

@onready var _visual_host: Control = %VisualHost
@onready var _label: Label = %NameLabel


## Build the tile's content for [param addon_script]. [param tile_size] sizes the
## tile; [param node_radius] sizes the previewed SkillNode.
func configure(addon_script: Script, tile_size: Vector2, node_radius: float) -> void:
	custom_minimum_size = tile_size
	_visual_host.custom_minimum_size = Vector2(tile_size.x, tile_size.y - LABEL_HEIGHT)
	for child in _visual_host.get_children():
		child.queue_free()
	var sn: SkillNode = SKILL_NODE_SCENE.instantiate()
	sn.radius = node_radius
	# Visual-only — center the gameplay object inside the Control tile.
	sn.position = _visual_host.custom_minimum_size * 0.5
	_visual_host.add_child(sn)
	var anchor: Node2D = sn.get_node_or_null("Visuals/AddonAnchor")
	if anchor != null and addon_script != null:
		var addon := Node2D.new()
		addon.set_script(addon_script)
		anchor.add_child(addon)
	_label.text = _pretty_name(addon_script)


func _pretty_name(script: Script) -> String:
	if script == null:
		return "—"
	return script.resource_path.get_file().get_basename().capitalize()
