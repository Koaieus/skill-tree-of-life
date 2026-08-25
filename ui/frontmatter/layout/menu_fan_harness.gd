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
##       %HeroSlot   (MenuSlot)  — where the focused node docks
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


## What one fan authors, once [method measure] has laid it out and read every
## seat's look off it.
##
## A plain record with no [Node] in it, for the reason [MenuSlot.Look] is one:
## the whole Control tree is freed the moment the caller is done with it. It
## replaced an untyped [Dictionary] with the same five keys (#589's crash was
## hard to read for exactly that reason — a failed parenting produced
## `Invalid access to property or key 'looks'` two calls from the real cause).
## A typed member access cannot silently miss like that.
class Measured extends RefCounted:
	## `%HeroSlot`'s centre, in harness-local pixels.
	var hero: Vector2 = Vector2.ZERO
	## What the camera parks at while this fan is the choice on offer (#593).
	var zoom: float = 0.0
	## `{menu_id: Vector2}` — the seats that stand for real menu items.
	var slots: Dictionary = {}
	## `{menu_id: Vector2}` — the seats that are scenery (#591).
	var decor: Dictionary = {}
	## `{menu_id: MenuSlot.Look}` — both kinds, plus the hero if it names one.
	var looks: Dictionary = {}


## The [MenuGraph] id this fan hangs off — the node that docks in `%HeroSlot`
## while these options are the choice on offer.
@export var hero_id: StringName = &""

## The zoom the camera parks at while this fan is the choice on offer (#593).
##
## Authored per fan rather than as a second global const beside
## [constant FrontmatterLayout.TREE_ZOOM], because "the root reads closer than
## everything else" is a property of the ROOT MENU and not a rule about menus.
## A fan that has nothing to say leaves it at 1.0 and the tree zoom stands.
@export_range(0.25, 4.0, 0.01) var camera_zoom: float = 1.0


## Where the focused node docks. A [MenuSlot] like any other, so that the one
## node with no seat in anybody's fan — the ROOT, which has no parent — still
## has somewhere to author its look (#591). Every other fan leaves its
## [member MenuSlot.menu_id] empty: `single_player` is already authored as a
## slot in `root_menu.tscn`, and a second copy here would be two sources for one
## caption.
func hero_slot() -> MenuSlot:
	return get_node("%HeroSlot") as MenuSlot


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


## Lays this fan out at [param view] and reports what it authors, as a
## [Measured] in harness-local pixels.
##
## The looks are COPIES: this whole Control tree is freed the moment the caller
## is done with it, so a [MenuNodeView] holding a slot reference would be
## holding a freed [Node].
##
## [param overrides] may carry `separation: float` and `margins: Vector4` —
## #578's live tab tuning the selected fan without editing the scene. Absent
## keys leave the authored values alone.
func measure(view: Vector2, overrides: Dictionary = {}) -> Measured:
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
		return _nothing_measured()
	_parent_for_measuring(host)
	assert(
		get_parent() != null,
		"'%s' could not be parented for measurement — nothing in the tree "
			% name + "would take it, so every rect would read 0x0."
	)
	if get_parent() == null:
		return _nothing_measured()
	position = Vector2.ZERO
	size = view
	_sort(self)

	var slots: Dictionary = {}
	var decor: Dictionary = {}
	var looks: Dictionary = {}
	var hero := hero_slot()
	if hero.menu_id != &"":
		assert(
			hero.menu_id == hero_id,
			"'%s' docks '%s' but its %%HeroSlot is authored as '%s'"
				% [name, hero_id, hero.menu_id]
		)
		looks[hero.menu_id] = hero.look()
	for slot in option_slots():
		assert(slot.menu_id != &"", "a slot in '%s' names no id" % name)
		assert(not looks.has(slot.menu_id), "'%s' is authored twice" % slot.menu_id)
		var where := _centre_of(slot)
		if slot.decorative:
			decor[slot.menu_id] = where
		else:
			slots[slot.menu_id] = where
		looks[slot.menu_id] = slot.look()
	var measured := Measured.new()
	measured.hero = _centre_of(hero)
	measured.zoom = camera_zoom
	measured.slots = slots
	measured.decor = decor
	measured.looks = looks
	get_parent().remove_child(self)
	return measured


## An empty measurement: no seats, no looks, hero at the origin — but this
## fan's own authored [member camera_zoom], which is knowable without measuring
## anything and is the one field a caller cannot sanely default. Zero would be
## a degenerate camera scale, and the asserts guarding both callers of this are
## stripped from a release build.
func _nothing_measured() -> Measured:
	var empty := Measured.new()
	empty.zoom = camera_zoom
	return empty


## Parents this harness somewhere it can actually be measured, for the length
## of one synchronous call.
##
## [b]Not `root`, on purpose.[/b] [method Node.add_child] FAILS — printing its
## own error rather than raising — on a parent that is busy setting up
## children, and `root` is exactly that while the [SceneTree] is adding a
## scene that was run DIRECTLY (F6 in the editor, or `run/main_scene`). The
## harness then never parents, [method _sort] measures every rect as `0x0`,
## and the first thing anyone sees is a null `get_parent()` here followed by a
## bogus "no authored look" assertion two calls away. That was a real crash on
## every direct run of `meta_root.tscn`.
##
## Every autoload is a fully-ready child of `root` before any scene is added,
## so none of them is ever mid-add — which makes one of them a host that works
## in both cases, and avoids the failed-`add_child` error that probing `root`
## first would print every time. Being a [Control] under a plain [Node] does
## not affect `is_visible_in_tree()`, which is the only thing the sort needs.
func _parent_for_measuring(host: SceneTree) -> void:
	for candidate in host.root.get_children():
		if candidate == host.current_scene:
			continue
		candidate.add_child(self)
		if is_visible_in_tree():
			return
		# Parented, but under something hidden (the fade overlay is an autoload
		# and rests invisible). `fit_child_in_rect` early-returns on anything
		# not `is_visible_in_tree()`, so this host is no better than none.
		candidate.remove_child(self)
	host.root.add_child(self)


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
