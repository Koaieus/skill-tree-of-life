@tool
class_name CorePresence
extends SkillNodeVisual
## The core node's presence (#128, #1108): a container with ONE look slot plus
## the [CoreSigilBloom] glow. What sits in `Slot` is the owner's
## [member CoreClass.core_look] — `core_gimbal.tscn` for an entity,
## `core_gear.tscn` for a Dormant Core — so this script never names a look, a
## ring or a style (docs/domain/skillnode-emblem.md).
##
## Slot contract: the look is a [SkillNodeVisual] leaf. CorePresence is itself
## a child of the composite's identity fan-out and re-pushes everything it
## knows (radius, both tints, `allocated`, `owner_level`, `node_seed`) into the
## look, plus `revealed` when the look declares one — on every change and at
## the moment a new look is instanced, so a look never renders a stale frame.
##
## Travel hooks, duck-typed over the bloom AND the look:
##   `on_core_travel_start(local_offset: Vector2, duration: float) -> void`
##   `on_core_travel_arrived() -> void`
## The look glides; the bloom extinguishes and reignites (#128). The same
## scene is instanced standalone as the core-move drag ghost, whose caller
## sets the look once with [method set_look].

## Whether the node is out of the fog for the local viewer (half of a look's
## animation/visibility gate, #802). Forwarded to the look when it has one.
var revealed: bool = true:
	set(value):
		revealed = value
		var look := get_look()
		if look != null and &"revealed" in look:
			look.revealed = value

var _look_scene: PackedScene = null


## Wears `scene` in the slot. The same resource again is a no-op; otherwise the
## old look leaves the slot at once (and is freed), and the new one is
## instanced with the identity already pushed before it enters the tree.
## `null` empties the slot.
func set_look(scene: PackedScene) -> void:
	if scene == _look_scene:
		return
	_look_scene = scene
	var slot := get_node(^"Slot")
	for old in slot.get_children():
		slot.remove_child(old)
		old.queue_free()
	if scene == null:
		return
	var look := scene.instantiate()
	_push_identity(look)
	slot.add_child(look)


## The look currently in the slot, or null.
func get_look() -> Node:
	var slot := get_node_or_null(^"Slot")
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0)


func set_revealed(value: bool) -> void:
	revealed = value


func configure(new_radius: float) -> void:
	super(new_radius)
	var look := get_look()
	if look is SkillNodeVisual:
		look.configure(new_radius)


func _on_identity_changed() -> void:
	var look := get_look()
	if look != null:
		_push_identity(look)


func _push_identity(look: Node) -> void:
	if look is SkillNodeVisual:
		look.configure(radius)
		look.entity_tint = entity_tint
		look.archetype_tint = archetype_tint
		look.allocated = allocated
		look.owner_level = owner_level
		look.node_seed = node_seed
	if &"revealed" in look:
		look.revealed = revealed


## Slides the presence in from `local_offset` (this node's old position,
## relative to this node) — see the hook contract above. A degenerate offset
## is the caller's job to skip.
func glide_from(local_offset: Vector2, duration: float = 0.25) -> void:
	for target in _hook_targets():
		if target.has_method(&"on_core_travel_start"):
			target.on_core_travel_start(local_offset, duration)
	var timer := create_tween()
	timer.tween_interval(duration)
	timer.tween_callback(_notify_arrived)


func _notify_arrived() -> void:
	for target in _hook_targets():
		if target.has_method(&"on_core_travel_arrived"):
			target.on_core_travel_arrived()


func _hook_targets() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child.name != &"Slot":
			out.append(child)
	var look := get_look()
	if look != null:
		out.append(look)
	return out
