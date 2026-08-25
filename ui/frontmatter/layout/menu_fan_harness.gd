@tool
class_name MenuFanHarness
extends MarginContainer

## One menu's geometry, AUTHORED (#589 D1/D2). The base scene is
## `menu_harness.tscn`; every fan in the game is an inherited scene of it that
## adds its own slots and tunes its own separation and margins in a full-screen
## editor preview.
##
## [codeblock]
##   MenuFanHarness (MarginContainer, the project viewport)
##     %Row          (HBoxContainer)
##       %HeroSlot   (Control)   — where the focused node docks
##       %OptionsVBox(VBoxContainer)
##         MenuSlot x N          — one per child of [member hero_id]
## [/codeblock]
##
## [b]It replaced a recursion, not an offset table.[/b] The old solver derived a
## sibling pitch from peek-stack collision constraints, which is why the root fan
## ended up 52% looser than every fan below it at a number nobody authored. A
## container authors that pitch directly, so `_group_gap()` and
## `_collapsed_extent()` have no reason to exist and are gone.
##
## [b]It is never ALIVE while the menu is (#589 D3).[/b] This is a [Control] tree
## in SCREEN space; the menu is [Node2D] views under a [Camera2D] in WORLD space.
## A live harness would re-lay-out on window resize under a camera that already
## baked its numbers — a second layout system racing the first. So
## [FrontmatterLayout] instances it, calls [method measure], and frees it.
## [method measure] drives the container sort by hand rather than waiting for a
## frame, which is what lets the whole geometry stay a pure static function with
## no `await`. It does parent itself for the length of that one synchronous call
## — [method _sort] explains why it has no choice — but it is never in the tree
## across a frame, and that is what D3 is about.
##
## And never a [RemoteTransform2D] between the two: it pushes GLOBAL transform
## and would double-apply the camera.


## The [MenuGraph] id this fan hangs off — the node that docks in `%HeroSlot`
## while these options are the choice on offer.
@export var hero_id: StringName = &""


func hero_slot() -> Control:
	return get_node("%HeroSlot") as Control


func options_box() -> BoxContainer:
	return get_node("%OptionsVBox") as BoxContainer


## Every authored seat, in top-to-bottom order.
func option_slots() -> Array[MenuSlot]:
	var slots: Array[MenuSlot] = []
	for child in options_box().get_children():
		if child is MenuSlot:
			slots.append(child as MenuSlot)
	return slots


## The separation and margins this scene AUTHORS, before any live override.
##
## #578's tab resets to these rather than to a second copy of the same numbers
## (#594): the scene is the one source, so a value retuned in the editor cannot
## desync from the value the panel snaps back to.
func authored_theme() -> Dictionary:
	return {
		&"separation": float(options_box().get_theme_constant(&"separation")),
		&"margins": Vector4(
			float(get_theme_constant(&"margin_left")),
			float(get_theme_constant(&"margin_top")),
			float(get_theme_constant(&"margin_right")),
			float(get_theme_constant(&"margin_bottom")),
		),
	}


## Lays this fan out at [param view] and reports where everything landed, in
## harness-local pixels: `{hero: Vector2, slots: {menu_id: Vector2}}`.
##
## [param overrides] may carry `separation: float` and `margins: Vector4` —
## #578's live tab tuning the selected fan without editing the scene. Absent
## keys leave the authored values alone.
func measure(view: Vector2, overrides: Dictionary = {}) -> Dictionary:
	if overrides.has(&"separation"):
		options_box().add_theme_constant_override(
			&"separation", int(roundf(float(overrides[&"separation"])))
		)
	if overrides.has(&"margins"):
		var m: Vector4 = overrides[&"margins"]
		add_theme_constant_override(&"margin_left", int(roundf(m.x)))
		add_theme_constant_override(&"margin_top", int(roundf(m.y)))
		add_theme_constant_override(&"margin_right", int(roundf(m.z)))
		add_theme_constant_override(&"margin_bottom", int(roundf(m.w)))

	var host := (Engine.get_main_loop() as SceneTree)
	assert(host != null, "a fan harness can only be measured under a SceneTree")
	if host == null:
		return {&"hero": Vector2.ZERO, &"slots": {}}
	host.root.add_child(self)
	position = Vector2.ZERO
	size = view
	_sort(self)

	var slots: Dictionary = {}
	for slot in option_slots():
		slots[slot.menu_id] = _centre_of(slot)
	var measured := {&"hero": _centre_of(hero_slot()), &"slots": slots}
	get_parent().remove_child(self)
	return measured


## Drives one full container sort, top-down, inside a single call.
##
## [b]Why by hand.[/b] [method Container.queue_sort] defers through the message
## queue and only flushes inside a frame, so the obvious version would force
## every caller of [method FrontmatterLayout.solve] to `await` — including the
## unit tests, which exist precisely because a [Transform2D] is assertable and a
## tween's third frame is not. `NOTIFICATION_SORT_CHILDREN` is the same code path
## the queue would eventually run; sending it in parent-before-child order gives
## the identical result synchronously, because each container needs only its own
## size (already set by its parent's sort) to place its children.
##
## [b]The one thing it cannot skip is the [SceneTree].[/b]
## [method Container.fit_child_in_rect] early-returns on a child that is not
## `is_visible_in_tree()`, and a node outside the tree never is — a harness
## measured detached silently reports every rect as `0x0`. So [method measure]
## parents itself for the duration of the sort and unparents before returning:
## in the tree for the length of one function call, never for a frame, which is
## what #589 D3 is actually about.
static func _sort(control: Control) -> void:
	if control is Container:
		control.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in control.get_children():
		if child is Control:
			_sort(child as Control)


## [param control]'s centre in harness-local pixels. Walked by hand rather than
## via `get_global_rect()`: the harness is parented to the tree ROOT for the
## duration of [method measure], so a global rect would be offset by wherever
## root put it. Local accumulation is what makes the result independent of that.
func _centre_of(control: Control) -> Vector2:
	var at := control.size * 0.5
	var node: Node = control
	while node != null and node != self:
		at += (node as Control).position
		node = node.get_parent()
	return at
