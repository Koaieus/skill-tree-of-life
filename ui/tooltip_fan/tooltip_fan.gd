@tool
class_name TooltipFan
extends Node2D

## Tooltip V2 (#226) — the coordinator: owns N fan-tier members ([FanUnit]s,
## plus [GrantedModifiersRoot] which duck-types the same `play_in()`/
## `play_out() -> Tween` contract), anchors to the hovered node's on-screen
## position, selects an occupancy-class variant, and fires the members with a
## per-index start delay. Nothing else. See
## `.claude/rules/tooltip-fan.md` and docs/domain/tooltip-fan.md.
##
## Owns NO Tween and no fan-wide progress variable — the per-index delay is a
## `SceneTreeTimer` wait, not a tween. Members animate themselves (or, for
## FanUnit, sequence two components that animate themselves); this class only
## decides WHEN each one starts.
##
## Screen-space anchoring: `global_position` tracks the hovered [SkillNode]'s
## `get_global_transform_with_canvas().origin` every frame — Control-space,
## camera-zoom-independent, exactly like `floater_toaster.gd`'s HUD-anchor
## case (no `affine_inverse()` needed there: this node has no camera transform
## of its own, it lives directly in the HUD's canvas).
##
## Members are found by GROUP (`fan_unit`), never by NodePath — the mount
## contract's "bindings resolve by type/group, not per-variant NodePaths".
## Whether a variant has 2 members or 6 changes nothing here but how many
## delays get computed.

@export var unowned_variant: PackedScene = preload("res://ui/tooltip_fan/variants/unowned.tscn")
@export var owned_variant: PackedScene = preload("res://ui/tooltip_fan/variants/owned.tscn")
@export var owned_core_variant: PackedScene = preload("res://ui/tooltip_fan/variants/owned_core.tscn")

## Per-index delay before each member starts its IN sequence. The
## coordinator's only timing knob — see the class doc.
@export var stagger_delay: float = 0.05

const _GROUP := &"fan_unit"

var _hovered_node: SkillNode = null
var _current_variant: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	visible = false
	Events.skill_node_hovered.connect(_on_hovered)
	Events.skill_node_unhovered.connect(_on_unhovered)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _hovered_node != null and is_instance_valid(_hovered_node):
		global_position = _hovered_node.get_global_transform_with_canvas().origin
		_feed_pin_radius(_current_variant, _hovered_node)


func _on_hovered(node: SkillNode) -> void:
	if node == _hovered_node and _current_variant != null:
		return
	# Capture the OLD node before `_hovered_node` is reassigned — `_retire`
	# needs it to keep the outgoing fan tracking where it actually was, not
	# where the newly-hovered node happens to be.
	var previous_node := _hovered_node
	_hovered_node = node
	if _current_variant != null:
		_retire(_current_variant, previous_node)
		_current_variant = null
	global_position = node.get_global_transform_with_canvas().origin
	var scene := _pick_variant(node)
	if scene == null:
		return
	visible = true
	var instance := scene.instantiate()
	add_child(instance)
	_current_variant = instance
	# BEFORE the first play_in: the variant's own `_process` would otherwise
	# derive its clock pins from `preview_pin_radius` for one frame — i.e. from
	# the editor fallback, at whatever the real zoom happens to be — and only
	# correct on the next frame. That's a visible pop at any zoom != 1.
	_feed_pin_radius(instance, node)
	_bind_content(instance, node)
	_play_in_all(instance)


## Pushes `node`'s SCREEN-space radius into `variant`'s [FanAnchorDriver],
## which is what makes the clock pins zoom-reactive. Shared by the active
## variant ([method _process]) and every retiring one ([method
## _anchor_retiring]) — each just supplies its own (variant, node) pair.
##
## The same `get_global_transform_with_canvas()` that makes the anchor
## zoom-independent also carries the zoom factor in its scale — so this class
## never needs to know a camera exists.
func _feed_pin_radius(variant: Node, node: SkillNode) -> void:
	if not (variant is FanAnchorDriver):
		return
	if node == null or not is_instance_valid(node):
		return
	var scale_x := node.get_global_transform_with_canvas().get_scale().x
	(variant as FanAnchorDriver).node_radius = node.radius * scale_x


## Feeds the hovered [SkillNode] into content-holding members that need real
## data rather than static placeholder text. Currently just
## [GrantedModifiersRoot] (found by type, not group — `fan_unit` mixes it with
## [FanUnit]s that don't have a `bind(SkillNode)` contract at all).
func _bind_content(variant: Node, node: SkillNode) -> void:
	for n in variant.find_children("*", "", true, false):
		if n is GrantedModifiersRoot:
			(n as GrantedModifiersRoot).bind(node)


func _on_unhovered() -> void:
	var previous_node := _hovered_node
	_hovered_node = null
	if _current_variant != null:
		_retire(_current_variant, previous_node)
		_current_variant = null


## Occupancy class selection (Decision 2, swarmable spec v2): unowned nodes
## are the common case (`owned_nodes(L) ≈ 2.2L` against a ~150-node graph),
## which is why they get the sparsest variant.
func _pick_variant(node: SkillNode) -> PackedScene:
	if not node.is_allocated():
		return unowned_variant
	if node.is_core():
		return owned_core_variant
	return owned_variant


## Fires every member of `variant` with an increasing per-index delay —
## "Fire N units, each with its own delay" from the settled clock-ownership
## decision. A member superseded before its delay elapses (this variant
## retired, or the whole fan freed) never calls play_in — checked via
## `variant.is_queued_for_deletion()` rather than a generation counter, since
## each variant instance is its own scope (no shared fan-wide state to guard).
func _play_in_all(variant: Node) -> void:
	var members := _collect_members(variant)
	for i in range(members.size()):
		_play_in_one(variant, members[i], i * stagger_delay)


func _play_in_one(variant: Node, member: Node, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(variant) or variant.is_queued_for_deletion():
		return
	# `_retire()` marks a variant "retiring" the instant a new hover supersedes
	# it — synchronously, before any of ITS OWN members have necessarily
	# reached HIDDEN yet. Without this check, a still-pending delayed
	# play_in() (queued before the retire) would fire play_in() on a member
	# `_retire()` already decided to tear down, and nothing would ever call
	# play_out() on it again — `_all_settled` never turns true and the
	# variant leaks forever instead of being freed.
	if variant.get_meta(&"retiring", false):
		return
	if not is_instance_valid(member):
		return
	member.play_in()


## Tears down every member of `variant` (interrupt = kill + reverse — each
## member's own `play_out()` already does this, per #303's settled component
## contract), then frees the variant once every member has settled to HIDDEN.
## A member that never started (still HIDDEN — its coordinator-side delay
## hadn't fired yet) is skipped rather than animated for nothing.
func _retire(variant: Node, node: SkillNode) -> void:
	variant.set_meta(&"retiring", true)
	# Detach the retiring variant from THIS coordinator's transform. `variant`
	# stays a child of this Node2D — if a new hover reassigns `global_position`
	# to a different node while this variant is still mid-play_out, it would
	# otherwise be dragged along to the new node's position instead of fading
	# out where it actually is. `top_level` makes it ignore the parent
	# transform from here on. A non-Node2D variant has no transform to detach
	# and none to re-derive: [method _anchor_retiring] no-ops on it too, so
	# both halves stay consistent rather than one tracking and one riding.
	if variant is Node2D:
		# `top_level` reinterprets the CURRENT local `position` as a global one,
		# so re-assert the global spot across the flip. `_anchor_retiring`
		# overwrites it immediately whenever `node` is still alive; this is the
		# fallback that keeps a variant whose node vanished from teleporting.
		var v2d := variant as Node2D
		var frozen := v2d.global_position
		v2d.top_level = true
		v2d.global_position = frozen
	_anchor_retiring(variant, node)
	var members := _collect_members(variant)
	if members.is_empty():
		variant.queue_free()
		return
	_await_retire(variant, node, members)


func _await_retire(variant: Node, node: SkillNode, members: Array[Node]) -> void:
	# Fire every member's own play_out() in parallel (each is a coroutine that
	# runs to its first await then yields control back here) ...
	for member in members:
		_retire_one(member)
	# ... then poll until every member has actually settled. Polling rather
	# than awaiting a per-type signal keeps this uniform across FanUnit
	# (`state_changed`) and GrantedModifiersRoot (no signal — just `visible`).
	#
	# This loop is also where the retiring variant keeps tracking its OWN node,
	# and it's why there's no bookkeeping of "currently retiring" variants
	# anywhere: the coroutine already is a per-variant scope that lives exactly
	# as long as the OUT animation, so the anchor update belongs in it rather
	# than in a coordinator-wide `_process` pass. A ONE-TIME freeze in
	# [method _retire] would desync the trace the moment the camera panned or
	# zoomed mid-play_out.
	while not _all_settled(members):
		_anchor_retiring(variant, node)
		await get_tree().process_frame
	if is_instance_valid(variant):
		variant.queue_free()


## Re-derives a retiring variant's screen anchor and clock-pin radius from
## `node` — the node it was hovering when it got superseded, NOT `_hovered_node`
## (which has already moved on to whatever is hovered now, if anything).
## The active variant gets the same treatment in [method _process].
func _anchor_retiring(variant: Node, node: SkillNode) -> void:
	if not (variant is Node2D):
		return
	if node == null or not is_instance_valid(node):
		return
	(variant as Node2D).global_position = node.get_global_transform_with_canvas().origin
	_feed_pin_radius(variant, node)


## Plays one member out, awaiting its own full OUT sequence — but is itself
## called WITHOUT await from [method _await_retire], so every member's OUT
## sequence runs concurrently rather than one-after-another.
func _retire_one(member: Node) -> void:
	if not is_instance_valid(member):
		return
	if member is FanUnit:
		var unit := member as FanUnit
		if unit.state != FanUnit.State.HIDDEN:
			await unit.play_out()
	else:
		var tw: Variant = member.play_out()
		if tw is Tween:
			await (tw as Tween).finished


func _all_settled(members: Array[Node]) -> bool:
	for m in members:
		if not is_instance_valid(m):
			continue
		if m is FanUnit:
			if (m as FanUnit).state != FanUnit.State.HIDDEN:
				return false
		elif m.visible:
			return false
	return true


## Collects every fan-tier member of `variant` by GROUP membership, not type —
## a member may be a [FanUnit] (trace + panel) or [GrantedModifiersRoot] (no
## containing panel, per Decision 1); both duck-type `play_in()`/`play_out()`.
##
## Returned in the same ANGULAR order [FanAnchorDriver] hands out clock pins in
## — so the per-index stagger sweeps across the arc instead of popping in
## whatever order the (inherited) scene tree happens to list the units. See
## [method FanAnchorDriver.units_in_fan_order].
func _collect_members(variant: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in variant.find_children("*", "", true, false):
		if n.is_in_group(_GROUP) and n.has_method(&"play_in") and n.has_method(&"play_out"):
			out.append(n)
	out.sort_custom(func(a: Node, b: Node) -> bool:
		return FanAnchorDriver.fan_sort_angle(a) < FanAnchorDriver.fan_sort_angle(b))
	return out
