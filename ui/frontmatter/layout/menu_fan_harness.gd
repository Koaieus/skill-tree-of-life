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
## — [ControlMeasure.parent_for_measuring] explains why it has no choice — but
## it is never in the tree across a frame, and that is what D3 is about.
##
## And never a [RemoteTransform2D] between the two: it pushes GLOBAL transform
## and would double-apply the camera.


## What one fan authors, once [method measure] has laid it out and read every
## seat's look off it.
##
## A plain record with no [Node] in it, for the reason [MenuSlot.Look] is one:
## the whole Control tree is freed the moment the caller is done with it. It
## replaced an untyped [Dictionary] with the same keys (#589's crash was hard
## to read for exactly that reason — a failed parenting produced
## `Invalid access to property or key 'looks'` two calls from the real cause).
## A typed member access cannot silently miss like that.
##
## [b]No per-fan zoom.[/b] #593 authored one on `MenuFanHarness.camera_zoom`;
## owner call 2026-08-26 retired it — there are only two zooms in the whole
## menu, [constant FrontmatterLayout.TREE_ZOOM] and
## [constant FrontmatterLayout.SPLASH_ZOOM] — so nothing here carries a zoom to
## report and [method FrontmatterLayout.zoom_for] no longer reads this record.
class Measured extends RefCounted:
	## `%HeroSlot`'s centre, in harness-local pixels.
	var hero: Vector2 = Vector2.ZERO
	## `{menu_id: Vector2}` — the seats that stand for real menu items.
	var slots: Dictionary = {}
	## `{menu_id: Vector2}` — the seats that are scenery (#591).
	var decor: Dictionary = {}
	## `{menu_id: MenuSlot.Look}` — both kinds, plus the hero if it names one.
	var looks: Dictionary = {}


## The [MenuGraph] id this fan hangs off — the node that docks in `%HeroSlot`
## while these options are the choice on offer.
@export var hero_id: StringName = &""


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
		return Measured.new()
	ControlMeasure.parent_for_measuring(self, host)
	assert(
		get_parent() != null,
		"'%s' could not be parented for measurement — nothing in the tree "
			% name + "would take it, so every rect would read 0x0."
	)
	if get_parent() == null:
		return Measured.new()
	position = Vector2.ZERO
	size = view
	ControlMeasure.sort(self)

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
		var where := ControlMeasure.centre_of(slot, self)
		if slot.decorative:
			decor[slot.menu_id] = where
		else:
			slots[slot.menu_id] = where
		looks[slot.menu_id] = slot.look()
	var measured := Measured.new()
	measured.hero = ControlMeasure.centre_of(hero, self)
	measured.slots = slots
	measured.decor = decor
	measured.looks = looks
	get_parent().remove_child(self)
	return measured
