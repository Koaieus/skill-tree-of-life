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
##
## [b]A core reads its build.[/b] Pinning an entity's core shows that entity's
## ring silhouette in [code]%RingWheel[/code] (a `read_only` [AspectWheel] fed
## by [RingSilhouette]: sector hues + depth, never exact cells or unspent
## points) — but only while [member vision_system] sees the core. A non-core
## node, a fogged core, or a card missing either system shows no wheel
## (fail-closed: it hides information). Both systems are injected by [HudRoot].

@onready var _name: Label = %NodeName
@onready var _owner: Label = %OwnerValue
@onready var _hp: Label = %HpValue
@onready var _ring_wheel: AspectWheel = %RingWheel

## The level's ring rules — the cell table the silhouette is built against.
var ring_system: RingSystem:
	set(v):
		ring_system = v
		_render_ring()

## The local seat's fog: the wheel shows only while it sees the pinned core.
var vision_system: VisionSystem:
	set(v):
		_vision_binds.release()
		vision_system = v
		if vision_system != null:
			_vision_binds.link(vision_system.visibility_changed, _render_ring)
		_render_ring()

var _input_ctl: PlayerInputController
var _bound_node: SkillNode = null
## Links on the pinned node's owner; relinked whenever the node changes hands.
var _owner_binds := BindScope.new()
var _vision_binds := BindScope.new()


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
		_bound_node.owner_changed.connect(_on_owner_changed)
	_relink_owner()


func _disconnect_node() -> void:
	if _bound_node == null:
		return
	if _bound_node.damaged.is_connected(_on_node_changed):
		_bound_node.damaged.disconnect(_on_node_changed)
	if _bound_node.owner_changed.is_connected(_on_owner_changed):
		_bound_node.owner_changed.disconnect(_on_owner_changed)
	_bound_node = null
	_owner_binds.release()


func _on_owner_changed(_a: Variant = null, _b: Variant = null) -> void:
	_relink_owner()
	_render()


## A core's build is its owner's: follow that entity's buys and its core moving.
func _relink_owner() -> void:
	_owner_binds.release()
	var entity := _bound_node.owned_by if _bound_node != null else null
	if entity != null:
		_owner_binds.link(entity.ring_changed, _render_ring)
		_owner_binds.link(entity.core_location_changed, _render_ring)


func _on_node_changed(_a: Variant = null, _b: Variant = null) -> void:
	_render()


func _render() -> void:
	_render_ring()
	var node := _bound_node
	if node == null:
		_name.text = "—"
		_owner.text = "—"
		_hp.text = "—"
		return
	# #587 — never show the raw scene-tree name: Godot's duplicate-name
	# uniquifier leaks as "DormantCore@2", and CamelCase reads as an
	# identifier rather than a name. A landmark's authored name wins when
	# there is one.
	var display := node.get_display_name()
	_name.text = display if not display.is_empty() else String(node.name).get_slice("@", 0).capitalize()
	# #504: `owned_by` IS the drawn value under design B — a forced-dealloc
	# lands at its own `arrival_time`, so the card flips to "Unowned" on the
	# same beat the node does.
	var current_owner := node.owned_by
	_owner.text = current_owner.display_name if current_owner != null else "Unowned"
	_hp.text = "%d / %d" % [roundi(node.get_current_hp()), roundi(node.get_max_hp())]


## Show the pinned core's silhouette iff it is a core the local seat can see.
func _render_ring() -> void:
	if _ring_wheel == null:
		return
	var node := _bound_node
	var table: RingTable = ring_system.table() if ring_system != null else null
	var shown := (node != null and table != null and vision_system != null
			and node.is_core() and vision_system.is_visible(node))
	_ring_wheel.visible = shown
	if shown:
		_ring_wheel.bind(RingSilhouette.entries(table, node.owned_by.ring_spent))
	else:
		_ring_wheel.bind([] as Array[AspectWheelEntry])
