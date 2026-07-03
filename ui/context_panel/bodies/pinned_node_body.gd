@tool
class_name PinnedNodeBody
extends ContextBodyBase

## Context body for a pinned node (right-click a node to pin it). Surfaces the
## node's identity, owner, and combat HP. Refreshes live off the node's own
## signals so depletion / heals tick the readout while it's pinned.

@onready var _name: Label = $NodeName
@onready var _owner: Label = $OwnerRow/Value
@onready var _hp: Label = $HpRow/Value

var _bound_node: SkillNode = null


func _exit_tree() -> void:
	_disconnect_node()


func rebuild() -> void:
	if not is_node_ready():
		return
	_bind_node(context_node)
	_render()


func _bind_node(node: SkillNode) -> void:
	if node == _bound_node:
		return
	_disconnect_node()
	_bound_node = node
	if _bound_node != null:
		_bound_node.damaged.connect(_on_node_damaged)
		_bound_node.owner_changed.connect(_on_node_changed)


func _disconnect_node() -> void:
	if _bound_node == null:
		return
	if _bound_node.damaged.is_connected(_on_node_damaged):
		_bound_node.damaged.disconnect(_on_node_damaged)
	if _bound_node.owner_changed.is_connected(_on_node_changed):
		_bound_node.owner_changed.disconnect(_on_node_changed)
	_bound_node = null


func _on_node_damaged(_amount: float, _source: Variant) -> void:
	_render()


func _on_node_changed() -> void:
	_render()


func _render() -> void:
	if not is_node_ready():
		return
	var node := _bound_node
	if node == null:
		_name.text = "—"
		_owner.text = "—"
		_hp.text = "—"
		return
	_name.text = node.name
	_owner.text = node.owned_by.display_name if node.owned_by != null else "Unowned"
	_hp.text = "%d / %d" % [roundi(node.get_current_hp()), roundi(node.get_max_hp())]
