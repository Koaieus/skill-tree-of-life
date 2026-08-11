@tool
class_name TooltipFan
extends Node2D

## Tooltip V2 (#226) — the coordinator: owns N fan-tier members ([FanUnit]s,
## plus [GrantedModifiersRoot] which duck-types the same `play_in()`/
## `play_out() -> Tween` contract), anchors to the hovered node's on-screen
## position, and fires the members with a per-index start delay. Nothing else.
## See `.claude/rules/tooltip-fan.md` and docs/domain/tooltip-fan.md.
##
## Owns NO Tween and no fan-wide progress variable — the per-index delay is a
## `SceneTreeTimer` wait, not a tween. Members animate themselves (or, for
## FanUnit, sequence two components that animate themselves); this class only
## decides WHEN each one starts.
##
## ONE FAN SCENE, PER-UNIT GATING (#314). There used to be three
## occupancy-class variants (`unowned` / `owned` / `owned_core`) picked by a
## `_pick_variant` branch on `is_allocated()` / `is_core()`. That made
## allocating the node you were *currently hovering* invalidate the whole
## mounted scene, so the fan could only have responded by re-fanning from
## scratch. Now `fan.tscn` carries every unit and each one gates itself through
## [method FanPanel.has_content]: allocation makes Owner (and Core) eligible,
## they fan out on their own, and the panels already up are left alone.
##
## Screen-space anchoring: `global_position` tracks the hovered [SkillNode]'s
## `get_global_transform_with_canvas().origin` every frame — Control-space,
## camera-zoom-independent, exactly like `floater_toaster.gd`'s HUD-anchor
## case (no `affine_inverse()` needed there: this node has no camera transform
## of its own, it lives directly in the HUD's canvas).
##
## TWO-TIER GATE (#415): hover alone shows only the ROOTS — [GrantedModifiersRoot]'s
## mod-slab stack, the hover's primary readout. The [FanUnit] members (traces +
## panels) are bonus info and stay HIDDEN until the `ui_more_info` action
## (Shift) is held. The action state is polled every frame while hovering, so
## pressing or releasing Shift mid-hover fans the units in or out through the
## same [method _reconcile] path live updates use. `participating` still means
## "has content" (the driver's clock spread depends on it); the gate is applied
## HERE, at the play decisions, via [method _should_up]. The visual affordance
## for the gate is tracked in #416.
##
## Members are found by GROUP (`fan_unit`), never by NodePath — the mount
## contract's "bindings resolve by type/group, not authored NodePaths".
## Whether a fan shows 2 members or 6 changes nothing here but how many delays
## get computed.

@export var fan_scene: PackedScene = preload("res://ui/tooltip_fan/fan.tscn")

## Per-index delay before each member starts its IN sequence. The
## coordinator's only timing knob — see the class doc.
@export var stagger_delay: float = 0.05

const _GROUP := &"fan_unit"

## The "more info" input action (project.godot: Shift). Held while hovering
## a node, the [FanUnit] members fan out alongside the always-on Roots —
## the two-tier gate described in the class doc. Modeled as an InputMap
## action rather than a raw `KEY_SHIFT` poll so the binding is rebindable and
## intent is declared in one place.
const _MORE_INFO_ACTION := &"ui_more_info"

## The level's [Graph], injected by [method HudRoot.compose] via [method bind].
## Not an `@export` NodePath: the HUD is a CanvasLayer composed independently of
## the level content, so there is no authored path from here to the Graph — it
## resolves at compose time like every other GameRoot-owned dependency
## (`.claude/rules/scene-composition.md`). Panels receive it through
## [method FanPanel.bind] rather than walking the tree for it.
var graph: Graph = null

var _hovered_node: SkillNode = null
var _current_fan: Node = null

## Whether the [member _MORE_INFO_ACTION] gate is currently open. Written only
## by [method _poll_more_info] (frame-polled) and read by [method _should_up]
## at every play decision; captured fresh in [method _on_hovered] so a hover
## that lands on a Shift already in flight shows the full fan from frame one
## instead of a one-frame roots-only flash.
var _more_info_held := false

## The hovered node's owning entity's `health` pool, while hovering a CORE node
## that has one. Watched so the core-HP readout tracks core damage without a
## re-hover — the third of the three live bindings V1's tooltip carried, and the
## only one that isn't a signal on the node itself.
var _core_health_stat: Stat = null


## Injects the level [Graph]. Called by [method HudRoot.compose]; safe to leave
## unbound in a sandbox, where degree readouts simply render 0.
func bind(level_graph: Graph) -> void:
	graph = level_graph


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
		_feed_pin_radius(_current_fan, _hovered_node)
		_poll_more_info()


## Re-reads the [member _MORE_INFO_ACTION] gate every frame while hovering.
## On a change — Shift pressed or released with the pointer parked — re-runs
## [method _refresh_content] so [method _reconcile] fans the [FanUnit] members
## in or out exactly as if their content had changed, with the same stagger.
## A no-op when the gate state didn't move, which is the common frame.
func _poll_more_info() -> void:
	var held := Input.is_action_pressed(_MORE_INFO_ACTION)
	if held == _more_info_held:
		return
	_more_info_held = held
	_refresh_content()


func _on_hovered(node: SkillNode) -> void:
	if node == _hovered_node and _current_fan != null:
		return
	# Capture the OLD node before `_hovered_node` is reassigned — `_retire`
	# needs it to keep the outgoing fan tracking where it actually was, not
	# where the newly-hovered node happens to be.
	var previous_node := _hovered_node
	_unwatch_node()
	_hovered_node = node
	if _current_fan != null:
		_retire(_current_fan, previous_node)
		_current_fan = null
	if fan_scene == null:
		return
	global_position = node.get_global_transform_with_canvas().origin
	visible = true
	var instance := fan_scene.instantiate()
	add_child(instance)
	_current_fan = instance
	# BEFORE the first play_in: the fan's own `_process` would otherwise derive
	# its clock pins from `preview_pin_radius` for one frame — i.e. from the
	# editor fallback, at whatever the real zoom happens to be — and only
	# correct on the next frame. That's a visible pop at any zoom != 1.
	_feed_pin_radius(instance, node)
	# Capture the gate state NOW, not on the next `_process` poll: a hover that
	# lands on a Shift already in flight must show the full fan from the first
	# `_play_in_all`, or the units would arrive a frame late as a flicker.
	_more_info_held = Input.is_action_pressed(_MORE_INFO_ACTION)
	_bind_content(instance, node)
	_watch_node(node)
	_play_in_all(instance)


## Pushes `node`'s SCREEN-space radius into `fan_instance`'s [FanAnchorDriver],
## which is what makes the clock pins zoom-reactive. Shared by the active fan
## ([method _process]) and every retiring one ([method _anchor_retiring]) —
## each just supplies its own (fan, node) pair.
##
## The same `get_global_transform_with_canvas()` that makes the anchor
## zoom-independent also carries the zoom factor in its scale — so this class
## never needs to know a camera exists.
func _feed_pin_radius(fan_instance: Node, node: SkillNode) -> void:
	if not (fan_instance is FanAnchorDriver):
		return
	if node == null or not is_instance_valid(node):
		return
	var scale_x := node.get_global_transform_with_canvas().get_scale().x
	(fan_instance as FanAnchorDriver).node_radius = node.radius * scale_x


## Feeds the hovered [SkillNode] into every content-holding member and records,
## per unit, whether it has anything to show — BEFORE any `play_in()`, so
## [method FanPanel.has_content] is answered against real data rather than
## against a panel that hasn't seen the node yet.
##
## [member FanUnit.participating] is written HERE, in the same pass that binds,
## and nowhere else. Two consumers read it — this class (whether to play the
## unit in) and [FanAnchorDriver] (how many pins to share the clock face
## between) — and a unit that had been bound but not yet classified would hand
## the driver a stale count for a frame. Binding and classifying in one loop
## makes that unrepresentable.
##
## Two bind shapes, matched by type rather than duck-typed on `has_method`,
## because they genuinely differ: a [FanUnit] forwards `(node, graph)` to its
## panel, while [GrantedModifiersRoot] is not panel-shaped at all (no containing
## box, unbounded height) and takes the node alone. The root is also never
## gated — it renders an explicit empty row instead of vanishing.
func _bind_content(fan_instance: Node, node: SkillNode) -> void:
	for n in fan_instance.find_children("*", "", true, false):
		if n is FanUnit:
			var unit := n as FanUnit
			unit.bind(node, graph)
			unit.participating = unit.has_content()
		elif n is GrantedModifiersRoot:
			(n as GrantedModifiersRoot).bind(node)


func _on_unhovered() -> void:
	var previous_node := _hovered_node
	_unwatch_node()
	_hovered_node = null
	if _current_fan != null:
		_retire(_current_fan, previous_node)
		_current_fan = null


# --- live node state (#314) ---------------------------------------------------

## Subscribes to everything that can change what the mounted fan should show
## while the pointer stays put — the three bindings V1's `skill_node_tooltip.gd`
## carried, re-homed onto a fan that can now respond per panel:
##
## - `owner_changed`: allocation/deallocation. Flips Owner (and Core) between
##   eligible and not, and re-points the core-health watch.
## - `damaged`: node HP as hits land.
## - the owner's `health` pool: core HP as the death clock drains.
func _watch_node(node: SkillNode) -> void:
	node.owner_changed.connect(_on_owner_changed)
	node.damaged.connect(_on_node_damaged)
	_watch_core_health(node)


## Re-points [member _core_health_stat] at whatever pool the node's CURRENT
## owner exposes — nothing, for a non-core or unowned node. Called on hover and
## again on every `owner_changed`, since ownership is exactly what decides which
## entity's health (if any) is the relevant one.
func _watch_core_health(node: SkillNode) -> void:
	_unwatch_core_health()
	if node == null or not node.is_core() or node.owned_by == null:
		return
	if node.owned_by.stat_board == null:
		return
	var hp: Stat = node.owned_by.stat_board.get_stat(&"health")
	if hp == null:
		return
	_core_health_stat = hp
	_core_health_stat.value_changed.connect(_on_core_health_changed)


## Drops every live subscription. Called before a new hover binds its own, and
## on unhover — critically BEFORE [method _retire], because retiring does not
## free the fan synchronously ([method _await_retire] polls until every member
## settles). A still-subscribed fan mid-fade would re-bind and re-ignite itself
## on the next damage tick, which is the one leak this ordering prevents.
func _unwatch_node() -> void:
	if _hovered_node != null and is_instance_valid(_hovered_node):
		if _hovered_node.owner_changed.is_connected(_on_owner_changed):
			_hovered_node.owner_changed.disconnect(_on_owner_changed)
		if _hovered_node.damaged.is_connected(_on_node_damaged):
			_hovered_node.damaged.disconnect(_on_node_damaged)
	_unwatch_core_health()


func _unwatch_core_health() -> void:
	if _core_health_stat == null:
		return
	if _core_health_stat.value_changed.is_connected(_on_core_health_changed):
		_core_health_stat.value_changed.disconnect(_on_core_health_changed)
	_core_health_stat = null


func _on_owner_changed() -> void:
	_watch_core_health(_hovered_node)
	_refresh_content()


func _on_node_damaged(_amount: float, _source: Variant) -> void:
	_refresh_content()


func _on_core_health_changed() -> void:
	_refresh_content()


## Re-reads the hovered node into the mounted fan and brings the fan's shape
## back in line with it: panels re-render, newly-eligible units fan out, units
## that lost their content fan away, and [FanAnchorDriver] slides the surviving
## pins to their new slots on its own (it re-derives from the participating set
## every frame).
##
## Does nothing to a retiring fan — its members are on their way to HIDDEN by
## decision, and re-binding one would fight its own play_out.
func _refresh_content() -> void:
	if _hovered_node == null or not is_instance_valid(_hovered_node):
		return
	if _current_fan == null or not is_instance_valid(_current_fan):
		return
	if _current_fan.get_meta(&"retiring", false):
		return
	_bind_content(_current_fan, _hovered_node)
	_reconcile(_current_fan)


## Diffs each unit's freshly-written `participating` (AND the [member
## _more_info_held] gate, via [method _should_up]) against the state its
## machine is actually in, and plays only the difference. Idempotent: a unit
## whose eligibility didn't change is left strictly alone, which is what makes
## "the panels already open stay open" true rather than aspirational.
##
## OUT counts as "down" and IN/LOOP as "up", so a unit that regains content
## mid-fade turns around instead of completing a fade nobody wants any more.
## Newly-igniting units are staggered among THEMSELVES (not by their index in
## the whole fan), so two panels arriving together sweep rather than snap, while
## a lone one appears immediately.
##
## This is also the path a Shift press or release takes ([method
## _poll_more_info] → [method _refresh_content]): the gate flip flips
## `_should_up` for every participating unit at once, so a press fans the whole
## ring in with one sweep and a release retracts it in parallel.
func _reconcile(fan_instance: Node) -> void:
	var igniting := 0
	for member in _collect_members(fan_instance):
		if not (member is FanUnit):
			continue
		var unit := member as FanUnit
		var is_up: bool = unit.state == FanUnit.State.IN or unit.state == FanUnit.State.LOOP
		if _should_up(unit) and not is_up:
			_play_in_one(fan_instance, unit, igniting * stagger_delay)
			igniting += 1
		elif not _should_up(unit) and is_up:
			unit.play_out()


# --- entry ---------------------------------------------------------------------

## The single decision point for whether a [FanUnit] should be UP right now:
## it must have content AND the [member _more_info_held] gate must be open.
## Roots ([GrantedModifiersRoot]) is deliberately NOT a FanUnit and never goes
## through this check — the mod-slab stack is the hover's primary readout and
## shows unconditionally; only the bonus trace+panel units are gated.
##
## `participating` stays content-only (the driver shares the clock face out
## among it), so the gate lives here, at every play decision, rather than in
## the flag itself — keeping the two questions ("has content", "may show")
## separate in the same way #314 kept binding and classifying separate.
func _should_up(unit: FanUnit) -> bool:
	return unit.participating and _more_info_held


## Fires every participating member with an increasing per-index delay —
## "Fire N units, each with its own delay" from the settled clock-ownership
## decision. A member superseded before its delay elapses (this fan retired, or
## the whole thing freed) never calls play_in — checked via
## `fan_instance.is_queued_for_deletion()` rather than a generation counter,
## since each fan instance is its own scope (no shared fan-wide state to guard).
##
## The stagger indexes over the UP-EVER members only — participating AND gate
## open — so the sweep has no dead slots and no hidden ones: without the
## `ui_more_info` action this loop fans in just the Roots, and holding it mid-
## hover lets [method _reconcile] fire the units instead. Pre-#314 a suppressed
## member kept its index (and its clock pin) on the theory that absence should
## leave the fan balanced rather than reshuffled. #314 reverses that: pins now
## redistribute over the units actually present, because a held-open gap reads
## as "a panel failed to load", not as a deliberate omission. Stagger follows
## pins — the two have to agree, or the sweep would visibly skip positions the
## fan isn't using.
func _play_in_all(fan_instance: Node) -> void:
	var index := 0
	for member in _collect_members(fan_instance):
		if member is FanUnit and not _should_up(member as FanUnit):
			continue
		_play_in_one(fan_instance, member, index * stagger_delay)
		index += 1


func _play_in_one(fan_instance: Node, member: Node, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(fan_instance) or fan_instance.is_queued_for_deletion():
		return
	# `_retire()` marks a fan "retiring" the instant a new hover supersedes it —
	# synchronously, before any of ITS OWN members have necessarily reached
	# HIDDEN yet. Without this check, a still-pending delayed play_in() (queued
	# before the retire) would fire play_in() on a member `_retire()` already
	# decided to tear down, and nothing would ever call play_out() on it again —
	# `_all_settled` never turns true and the fan leaks forever instead of being
	# freed.
	if fan_instance.get_meta(&"retiring", false):
		return
	if not is_instance_valid(member):
		return
	# Re-check eligibility across the delay: a live update ([method
	# _refresh_content]) or a Shift release can revoke it while this call was
	# still waiting on its timer, and playing in a panel that has since emptied
	# (or been gated out) would show the very empty box `has_content` exists to
	# prevent.
	if member is FanUnit and not _should_up(member as FanUnit):
		return
	member.play_in()


# --- teardown ------------------------------------------------------------------

## Tears down every member of `fan_instance` (interrupt = kill + reverse — each
## member's own `play_out()` already does this, per #303's settled component
## contract), then frees it once every member has settled to HIDDEN.
## A member that never started (still HIDDEN — its coordinator-side delay
## hadn't fired yet) is skipped rather than animated for nothing.
func _retire(fan_instance: Node, node: SkillNode) -> void:
	fan_instance.set_meta(&"retiring", true)
	# Detach the retiring fan from THIS coordinator's transform. `fan_instance`
	# stays a child of this Node2D — if a new hover reassigns `global_position`
	# to a different node while this fan is still mid-play_out, it would
	# otherwise be dragged along to the new node's position instead of fading
	# out where it actually is. `top_level` makes it ignore the parent transform
	# from here on. A non-Node2D fan has no transform to detach and none to
	# re-derive: [method _anchor_retiring] no-ops on it too, so both halves stay
	# consistent rather than one tracking and one riding.
	if fan_instance is Node2D:
		# `top_level` reinterprets the CURRENT local `position` as a global one,
		# so re-assert the global spot across the flip. `_anchor_retiring`
		# overwrites it immediately whenever `node` is still alive; this is the
		# fallback that keeps a fan whose node vanished from teleporting.
		var v2d := fan_instance as Node2D
		var frozen := v2d.global_position
		v2d.top_level = true
		v2d.global_position = frozen
	_anchor_retiring(fan_instance, node)
	var members := _collect_members(fan_instance)
	if members.is_empty():
		fan_instance.queue_free()
		return
	_await_retire(fan_instance, node, members)


func _await_retire(fan_instance: Node, node: SkillNode, members: Array[Node]) -> void:
	# Fire every member's own play_out() in parallel (each is a coroutine that
	# runs to its first await then yields control back here) ...
	for member in members:
		_retire_one(member)
	# ... then poll until every member has actually settled. Polling rather
	# than awaiting a per-type signal keeps this uniform across FanUnit
	# (`state_changed`) and GrantedModifiersRoot (no signal — just `visible`).
	#
	# This loop is also where the retiring fan keeps tracking its OWN node, and
	# it's why there's no bookkeeping of "currently retiring" fans anywhere: the
	# coroutine already is a per-instance scope that lives exactly as long as
	# the OUT animation, so the anchor update belongs in it rather than in a
	# coordinator-wide `_process` pass. A ONE-TIME freeze in [method _retire]
	# would desync the trace the moment the camera panned or zoomed mid-play_out.
	while not _all_settled(members):
		_anchor_retiring(fan_instance, node)
		await get_tree().process_frame
	if is_instance_valid(fan_instance):
		fan_instance.queue_free()


## Re-derives a retiring fan's screen anchor and clock-pin radius from `node` —
## the node it was hovering when it got superseded, NOT `_hovered_node` (which
## has already moved on to whatever is hovered now, if anything). The active fan
## gets the same treatment in [method _process].
func _anchor_retiring(fan_instance: Node, node: SkillNode) -> void:
	if not (fan_instance is Node2D):
		return
	if node == null or not is_instance_valid(node):
		return
	(fan_instance as Node2D).global_position = node.get_global_transform_with_canvas().origin
	_feed_pin_radius(fan_instance, node)


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


## Collects every fan-tier member of `fan_instance` by GROUP membership, not
## type — a member may be a [FanUnit] (trace + panel) or [GrantedModifiersRoot]
## (no containing panel, per Decision 1); both duck-type
## `play_in()`/`play_out()`.
##
## Returned in the same ANGULAR order [FanAnchorDriver] hands out clock pins in
## — so the per-index stagger sweeps across the arc instead of popping in
## whatever order the scene tree happens to list the units. See
## [method FanAnchorDriver.units_in_fan_order].
##
## Unlike that method this does NOT filter on `participating`: teardown,
## settling and reconciliation all have to see every member, including the ones
## currently gated out. Callers that want only the live fan filter it themselves.
func _collect_members(fan_instance: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in fan_instance.find_children("*", "", true, false):
		if n.is_in_group(_GROUP) and n.has_method(&"play_in") and n.has_method(&"play_out"):
			out.append(n)
	out.sort_custom(func(a: Node, b: Node) -> bool:
		return FanAnchorDriver.fan_sort_angle(a) < FanAnchorDriver.fan_sort_angle(b))
	return out
