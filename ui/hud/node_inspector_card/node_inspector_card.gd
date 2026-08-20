@tool
class_name NodeInspectorCard
extends MarginContainer
## Right column, 2nd card (#118 cutover — pinned-node inspector). Surfaces a
## right-clicked ("pinned") node's identity, owner, and combat HP; hidden
## whenever nothing is pinned. This is the HudRoot home for the one context
## the old [ContextPanel] covered that has no equivalent elsewhere in the new
## HUD — attack-plan targeting and core-move hints are already covered by
## [CommandTray]'s own bodies (see command_tray.gd's doc comment), so this
## card is deliberately scoped to pinned-node display only, not a full
## ContextPanel port.

@onready var _panel: GlassPanel = %GlassPanel
@onready var _name: Label = %NodeName
@onready var _owner: Label = %OwnerValue
@onready var _hp: Label = %HpValue

var _input_ctl: PlayerInputController
var _bound_node: SkillNode = null


func _ready() -> void:
	visible = false


func bind(input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl
	if _input_ctl != null and not _input_ctl.node_pinned.is_connected(_on_node_pinned):
		_input_ctl.node_pinned.connect(_on_node_pinned)


func _on_node_pinned(node: SkillNode) -> void:
	_bind_node(node)
	_render()
	visible = node != null


func _bind_node(node: SkillNode) -> void:
	if node == _bound_node:
		return
	_disconnect_node()
	_bound_node = node
	if _bound_node != null:
		_bound_node.damaged.connect(_on_node_changed)
		_bound_node.owner_changed.connect(_on_node_changed)


func _disconnect_node() -> void:
	if _bound_node == null:
		return
	if _bound_node.damaged.is_connected(_on_node_changed):
		_bound_node.damaged.disconnect(_on_node_changed)
	if _bound_node.owner_changed.is_connected(_on_node_changed):
		_bound_node.owner_changed.disconnect(_on_node_changed)
	_bound_node = null


func _on_node_changed(_a: Variant = null, _b: Variant = null) -> void:
	_render()


func _render() -> void:
	var node := _bound_node
	if node == null:
		_name.text = "—"
		_owner.text = "—"
		_hp.text = "—"
		return
	_name.text = node.name
	# #485 audit: read as DRAWN, not as mutated — `owned_by` is already post-cascade
	# the instant a forced-dealloc lands, so a direct read here would show the
	# card snapping to "Unowned" before the node's own reveal does.
	var shown_owner := node.shown_owner
	_owner.text = shown_owner.display_name if shown_owner != null else "Unowned"
	_hp.text = "%d / %d" % [roundi(node.get_current_hp()), roundi(node.get_max_hp())]
