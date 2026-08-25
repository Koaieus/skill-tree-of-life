class_name FrontmatterLayout
extends RefCounted

## Where every menu node sits, and where the camera has to be for one of them to
## read as "the hero" (#567 / #568). Pure and static — no scene of its own, no
## [Node], no frame, so the whole geometry is unit-testable
## (`test/unit/ui/test_frontmatter_layout.gd`).
##
## [b]The split is the design.[/b] #567's constraint 1 is "no detaching, ever",
## which the architecture discharges as [i]one persistent graph, nodes never
## move, the [Camera2D] moves[/i]. A single `solve(tree, focus)` would make that
## invariant unfalsifiable, so it is two functions with a deliberate asymmetry:
##
## [codeblock]
##   solve(tree)                -> {id: world position}   focus is NOT a parameter
##   camera_for(tree, focus_id) -> Transform2D            the ONLY thing focus moves
## [/codeblock]
##
## [method solve] taking no focus is not a convenience — it is the machine-
## checkable form of "nodes never move", and the test asserts its output is
## identical across a run of [method camera_for] calls. That, and not the
## recursion it used to be implemented with, was always the invariant.
##
## [b]Geometry is AUTHORED, not derived (#589 D1).[/b] [method solve] reads the
## fan harness scenes in `ui/frontmatter/layout/` — one inherited scene per menu,
## each a [MarginContainer] + [HBoxContainer] + [VBoxContainer] of invisible
## [MenuSlot] spacers tuned in a full-screen editor preview. The old solver
## instead derived a sibling pitch from peek-stack collision constraints, and the
## root fan came out at 201 units: 52% looser than every other fan in the game,
## a number nobody chose, applied uniformly to `OPTIONS -> EXIT` which needed
## none of it. `_group_gap()` and `_collapsed_extent()` existed only to compute
## it and are gone; a container authors the pitch now, and keeping both would be
## two sources for one coordinate set.
##
## [b]There is exactly one size (#589 D4).[/b] The old design-canvas constant —
## 1440x900, kept deliberately apart from the project's 1440x960 viewport — is
## deleted. The harness is authored at the project viewport, so
## [method viewport_size] is the only size in this file and
## [method screen_to_world] is the genuine inverse of the real viewport
## transform rather than of a design-space fiction. `project.godot`'s
## `stretch/mode = "canvas_items"` + `stretch/aspect = "keep"` is what makes ONE
## authored geometry correct at every window size.
##
## [b]And the LOOK is authored in the same place (#589 D5 / #591).[/b] The same
## pass that measures a fan lifts each seat's caption, joke slab, archetype and
## radius off it into a [MenuSlot.Look] — see [method look_of]. [MenuGraph] keeps
## topology and routing and carries no display string at all.


## What the player actually sees, in world units at [constant TREE_ZOOM].
##
## The one place this file reads the project. Fallbacks match `project.godot`.
static func viewport_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1440)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 960))
	)


## Whether the menu you are LOOKING at is on screen when [param tree] is focused
## on [param focus_id] — the hero and the fan it opens.
##
## [b]Deliberately not "every node".[/b] Two things are off screen BY DESIGN.
## Focusing a child moves the camera onto it, sliding that child's own siblings
## off toward the edge — a skill tree scrolling past where you came from. And the
## hero's parent is a whole column step LEFT of a hero slot that sits at 13% of
## the width, so the back edge trails off the left margin, which is the framing
## the design canvas draws.
##
## What must never happen is an option you are being asked to choose between
## having no pixels on screen, which is exactly what shipped: the root's four
## options spanned +/-495 in a 960-unit viewport and two of them were undrawable.
##
## Now that a fan's pitch is authored rather than derived, this stops being a
## design tool and becomes a pure regression net — overflow is visible in the
## editor preview, and this is what stops it reaching a player anyway.
##
## [param margin] is the clearance a node needs beyond its own ink — a
## [MenuNodeView] draws a disk of `radius` and hangs its caption below it, so the
## default covers both rather than testing bare centres.
static func fits_viewport(
	tree: MenuGraph, focus_id: StringName, margin: Vector2 = Vector2(140.0, 100.0)
) -> bool:
	if tree == null or not tree.has(focus_id):
		return true
	var xform := camera_for(tree, focus_id)
	var view := viewport_size()
	var positions := solve(tree)
	var must_show: Array[StringName] = [focus_id]
	must_show.append_array(tree.children_of(focus_id))
	for id in must_show:
		# `(W - position) * zoom + centre`, exactly as [method camera_at]
		# documents it. Written multiplicatively rather than as a second hand-
		# rolled inverse of the same transform: dividing happens to agree at
		# [constant TREE_ZOOM] 1.0 and would silently disagree the moment #578's
		# tab tunes the zoom.
		var on_screen := (positions[id] as Vector2 - xform.origin) * zoom_of(xform) + view * 0.5
		if (
			on_screen.x < margin.x
			or on_screen.y < margin.y
			or on_screen.x > view.x - margin.x
			or on_screen.y > view.y - margin.y
		):
			return false
	return true


# --- the authored harness ---------------------------------------------------

## Every fan in the game, in the order they are read. The FIRST one is the root
## fan, and [method hero_slot] and [method column_step] answer off it — the base
## harness owns both of those, so every fan agrees by construction.
const FAN_SCENES: Array[String] = [
	"res://ui/frontmatter/layout/root_menu.tscn",
	"res://ui/frontmatter/layout/single_player_menu.tscn",
	"res://ui/frontmatter/layout/multiplayer_menu.tscn",
]

## `hero_id -> ` a [MenuFanHarness.Measured], whatever [method
## MenuFanHarness.measure] reported for that fan.
##
## Cached because [method solve] is called several times per navigation and the
## answer is a property of authored scenes, not of the caller. Emptied — never
## hand-patched — by anything that changes what the scenes would say, which is
## the whole of [method reset_geometry] and the per-fan override setters.
static var _fans: Dictionary = {}

## Insertion order of [member _fans]; `[0]` is the root fan.
static var _fan_order: Array[StringName] = []

## `menu_id -> MenuSlot.Look`, gathered off the same scenes in the same pass
## (#591). Every menu id has exactly one entry, including the root — which has
## no seat in anybody's fan, so `root_menu.tscn`'s `%HeroSlot` authors it.
static var _looks: Dictionary = {}

## `hero_id -> {separation: float, margins: Vector4}` — #578's live tab tuning a
## fan without editing its scene (#594). Gameplay never writes these.
static var _fan_overrides: Dictionary = {}


## The authored fans, read once and cached.
static func fans() -> Dictionary:
	if _fans.is_empty():
		_read_harnesses()
	return _fans


## Every fan's hero id, root fan first. #578's tab picks from this.
static func fan_ids() -> Array[StringName]:
	fans()
	return _fan_order.duplicate()


## The separation and margins a fan's SCENE authors, ignoring any live override.
## `{separation: float, margins: Vector4}`, or `{}` for an unknown fan.
static func authored_fan_theme(hero_id: StringName) -> Dictionary:
	for path in FAN_SCENES:
		var harness := _instance(path)
		if harness == null:
			continue
		var mine := harness.hero_id == hero_id
		var theme := harness.authored_theme() if mine else {}
		harness.free()
		if mine:
			return theme
	return {}


## Retunes one fan's [VBoxContainer] separation live. Sole caller is #578's tab.
static func set_fan_separation(hero_id: StringName, separation: float) -> void:
	_set_override(hero_id, &"separation", separation)


## Retunes one fan's harness margins live, as `(left, top, right, bottom)`.
static func set_fan_margins(hero_id: StringName, margins: Vector4) -> void:
	_set_override(hero_id, &"margins", margins)


static func _set_override(hero_id: StringName, key: StringName, value: Variant) -> void:
	var fan: Dictionary = _fan_overrides.get(hero_id, {})
	fan[key] = value
	_fan_overrides[hero_id] = fan
	_fans = {}
	_looks = {}


## Instances every fan scene, measures it, frees it (#589 D3).
##
## [b]Nothing here ever enters the [SceneTree].[/b] The harness is a [Control]
## tree in SCREEN space while the menu lives under a [Camera2D] in WORLD space; a
## live harness would re-lay-out on window resize under a camera that had already
## baked its numbers, which is a second layout system racing the first. See
## [method MenuFanHarness.measure] for how a container sort is driven without a
## frame.
static func _read_harnesses() -> void:
	_fans = {}
	_fan_order = []
	_looks = {}
	var view := viewport_size()
	for path in FAN_SCENES:
		var harness := _instance(path)
		if harness == null:
			continue
		var hero_id := harness.hero_id
		assert(hero_id != &"", "'%s' does not name the menu id it fans out from" % path)
		assert(not _fans.has(hero_id), "two fan scenes both fan out from '%s'" % hero_id)
		var measured := harness.measure(view, _fan_overrides.get(hero_id, {}))
		for slot_id: StringName in measured.looks:
			assert(not _looks.has(slot_id), "'%s' is authored in two scenes" % slot_id)
			_looks[slot_id] = measured.looks[slot_id]
		_fans[hero_id] = measured
		_fan_order.append(hero_id)
		harness.free()


static func _instance(path: String) -> MenuFanHarness:
	var packed := load(path) as PackedScene
	assert(packed != null, "missing fan harness scene '%s'" % path)
	if packed == null:
		return null
	var harness := packed.instantiate() as MenuFanHarness
	assert(harness != null, "'%s' is not a MenuFanHarness" % path)
	return harness


## How [param id] is drawn — its caption, its joke slab, its archetype and its
## radius — or `null` for an id nothing authors (#591 / #589 D5).
##
## This is the whole of the look. [MenuGraph] deliberately carries none of it:
## the tree is topology and routing, and every display string lives in the fan
## scene where an author can see it at full-screen scale.
static func look_of(id: StringName) -> MenuSlot.Look:
	fans()
	return _looks.get(id) as MenuSlot.Look


## Where the DECORATIVE slots sit, in world units — `{menu_id: Vector2}`.
##
## The seam for the owner's pre-authored bonus nodes (#589): a fan scene may
## carry seats that stand for nothing in [MenuGraph], reserving their row like
## any other slot and taking their look off the same exports, and the 1:1
## cross-check skips them. Nothing ships one yet; [method look_of] answers for
## them too, so drawing them is the follow-up's whole job.
static func decor_slots(tree: MenuGraph) -> Dictionary:
	var placed: Dictionary = {}
	var homes := solve(tree)
	var authored := fans()
	for hero_id: StringName in authored:
		if not homes.has(hero_id):
			continue
		var fan: MenuFanHarness.Measured = authored[hero_id]
		var offset: Vector2 = homes[hero_id] - fan.hero
		for slot_id: StringName in fan.decor:
			placed[slot_id] = fan.decor[slot_id] + offset
	return placed


## The authored fans and [param tree] describe the same menu, 1:1 (#589 D5).
##
## Every id but the root is named by exactly one slot, every slot and every fan
## names an id the tree knows, and a slot sits in the fan of its own parent —
## and since #591, every id including the root has exactly one authored look.
## `assert`, not a graceful fallback: an id with no slot has no position, and a
## menu item you cannot place is a bug to fix at build rather than to route
## around at runtime — the same call [method MenuGraph.add] makes.
##
## A [member MenuSlot.decorative] seat is scenery rather than a menu item, so it
## is checked the other way round: it must NOT name an id the tree knows, or the
## opt-out would be a way to smuggle a real item past the 1:1.
static func _assert_authored_matches(tree: MenuGraph, authored: Dictionary) -> void:
	var seated: Dictionary = {}
	for hero_id: StringName in authored:
		assert(tree.has(hero_id), "fan scene fans out from unknown menu id '%s'" % hero_id)
		var fan: MenuFanHarness.Measured = authored[hero_id]
		for slot_id: StringName in fan.slots:
			assert(tree.has(slot_id), "a slot names unknown menu id '%s'" % slot_id)
			assert(not seated.has(slot_id), "'%s' is authored in two slots" % slot_id)
			assert(
				tree.parent_of(slot_id) == hero_id,
				"'%s' sits in '%s'’s fan but its parent is '%s'"
					% [slot_id, hero_id, tree.parent_of(slot_id)]
			)
			seated[slot_id] = true
		for decor_id: StringName in fan.decor:
			assert(
				not tree.has(decor_id),
				"decorative slot '%s' names a real menu id — drop the flag" % decor_id
			)
	for id in tree.ids():
		if id != tree.root:
			assert(seated.has(id), "menu id '%s' has no authored slot" % id)
		assert(_looks.has(id), "menu id '%s' has no authored look" % id)


# --- tunables ---------------------------------------------------------------

## The hover peek-ahead column (#571): a hovered node's own children, shown small
## and dim at their collapsed positions, 284px right of the node being hovered.
##
## Plain pixels, and plain constants. A collapsed stack is genuinely uniform and
## has no per-menu character, so it is the one part of the geometry that stayed
## computed rather than authored (#590).
const PREVIEW_COLUMN := 284.0

## Vertical pitch inside that collapsed stack.
const PREVIEW_GAP := 46.0

## Scale the peek-ahead nodes are drawn at.
##
## [b]The last `static var` of the six.[/b] It is process-global mutable state so
## #578's live tab can retune it and rebuild in place: gameplay READS it, the tab
## is the sole writer, and [method reset_geometry] puts it back. A test that
## writes it must restore it, or a leaked value silently re-poses every menu
## built afterwards in the same process.
static var PREVIEW_SCALE := 0.42


## Restores everything a sandbox session or a test can retune: the peek-ahead
## scale, and every live per-fan override, which drops the harness cache so the
## next [method solve] re-reads the authored scenes.
static func reset_geometry() -> void:
	PREVIEW_SCALE = 0.42
	_fan_overrides = {}
	_fans = {}
	_looks = {}


## The splash (#574) is the root node, alone and close: (50%, 44%) of the
## viewport at 3.2x. "Press any button" is really allocating the first node of
## the run, so it is the same camera on the same tree, just parked.
##
## [b]These stay consts, and #593 looked at collapsing them.[/b] They are a
## SECOND camera onto a fan that already authors one — same hero, different slot
## and different zoom — and a fan has one of each. The per-fan knob is "how
## close is this menu"; the splash is "how close is the attract state", which is
## a different question about the same node.
const SPLASH_SLOT_RATIO := Vector2(0.5, 0.44)
## Raised from 2.55 by owner call (2026-08-26): [i]"before allocating, possibly
## zoom it in just a bit more — it's the SPLASH."[/i] The root menu itself parks
## at 1.35, so this is 2.4x that rather than 1.9x — enough that the attract state
## reads as one node filling the screen instead of a slightly-closer menu.
const SPLASH_ZOOM := 3.2

## The zoom the tree is navigated at, for every fan that does not author one of
## its own. 1.0 means one world unit per screen pixel.
const TREE_ZOOM := 1.0


# --- the layout -------------------------------------------------------------

## Every node's world position, computed once at build time.
##
## [b]Focus is not a parameter, and must never become one.[/b] That absence is
## the invariant: two calls with the same tree return the same dictionary
## whatever the camera has been doing in between.
##
## The root is the origin, and each fan is dropped onto it in turn: a fan's own
## `%HeroSlot` centre is where its hero already is, so the whole fan translates
## by the difference. [method MenuGraph.ids] is a pre-order walk, which is what
## makes one pass enough — a hero is always placed before its fan is applied.
static func solve(tree: MenuGraph) -> Dictionary:
	var positions: Dictionary = {}
	if tree == null or tree.root == &"":
		return positions
	var authored := fans()
	_assert_authored_matches(tree, authored)
	positions[tree.root] = Vector2.ZERO
	for id in tree.ids():
		if not authored.has(id) or not positions.has(id):
			continue
		var fan: MenuFanHarness.Measured = authored[id]
		var offset: Vector2 = positions[id] - fan.hero
		var slots: Dictionary = fan.slots
		for slot_id: StringName in slots:
			positions[slot_id] = (slots[slot_id] as Vector2) + offset
	return positions


## Where the focused node docks on screen, in viewport pixels — the base
## harness's `%HeroSlot` centre, so it is authored in the same place as
## everything else rather than being a ratio constant beside them.
##
## Consumed by [method camera_for] only, never by [method solve]: the hero slot
## is a camera concern, and authoring positions cannot move it.
static func hero_slot() -> Vector2:
	var authored := fans()
	if _fan_order.is_empty():
		return viewport_size() * 0.5
	return (authored[_fan_order[0]] as MenuFanHarness.Measured).hero


## The horizontal distance between a node and its children — the world column
## pitch, since nodes never move. The base harness owns it (`%HeroSlot`'s width),
## so it is the same in every fan; this reads it off the root fan.
static func column_step() -> float:
	var authored := fans()
	if _fan_order.is_empty():
		return 0.0
	var fan: MenuFanHarness.Measured = authored[_fan_order[0]]
	var slots: Dictionary = fan.slots
	for slot_id: StringName in slots:
		return (slots[slot_id] as Vector2).x - fan.hero.x
	return 0.0


## Where the camera must be for [param focus_id] to sit in the hero slot.
##
## The returned transform IS the camera's world transform: [member
## Transform2D.origin] is the camera position and its scale is
## `Vector2.ONE / zoom`. #570 applies it as
## `camera.position = t.origin; camera.zoom = FrontmatterLayout.zoom_of(t)`,
## and [method screen_to_world] is the inverse a test asserts through.
##
## An unknown id parks the camera on the root rather than at the world origin —
## a focus token that does not exist is a caller bug, and landing on the root is
## the recoverable answer.
static func camera_for(tree: MenuGraph, focus_id: StringName) -> Transform2D:
	return camera_at(_focus_position(tree, focus_id), hero_slot(), zoom_for(tree, focus_id))


## How close the camera sits while [param focus_id] is the hero (#593).
##
## A node with a fan is looked at through that fan's own authored
## [member MenuFanHarness.camera_zoom] — the root reads closer than everything
## else because `root_menu.tscn` says so, not because any code asks which id
## this is. A leaf fans out nothing, so it is seen at [constant TREE_ZOOM].
##
## An unknown id answers with the root's, matching [method _focus_position]'s
## own fallback: parking somewhere recoverable means parking there completely.
static func zoom_for(tree: MenuGraph, focus_id: StringName) -> float:
	if tree == null:
		return TREE_ZOOM
	var authored := fans()
	var id := focus_id if tree.has(focus_id) else tree.root
	if not authored.has(id):
		return TREE_ZOOM
	return (authored[id] as MenuFanHarness.Measured).zoom


## The parked splash camera: the root node, big, near the middle of the screen.
static func splash_camera(tree: MenuGraph) -> Transform2D:
	var root: StringName = tree.root if tree != null else &""
	return camera_at(_focus_position(tree, root), slot(SPLASH_SLOT_RATIO), SPLASH_ZOOM)


## The world position a camera should centre its slot on, falling back to the
## root and then to the origin.
static func _focus_position(tree: MenuGraph, focus_id: StringName) -> Vector2:
	if tree == null:
		return Vector2.ZERO
	var positions := solve(tree)
	if positions.has(focus_id):
		return positions[focus_id]
	return positions.get(tree.root, Vector2.ZERO)


## The camera transform putting [param world_pos] at [param screen_slot] — a
## point in viewport pixels — at [param zoom]. A [Camera2D] anchored on its
## centre shows world point `W` at screen `(W - position) * zoom + viewport/2`,
## so the position that lands `world_pos` on a given slot is the slot's offset
## from the centre, divided by the zoom, subtracted from the target.
static func camera_at(world_pos: Vector2, screen_slot: Vector2, zoom: float) -> Transform2D:
	var slot_offset := screen_slot - viewport_size() * 0.5
	return Transform2D(0.0, Vector2.ONE / zoom, 0.0, world_pos - slot_offset / zoom)


## World point a viewport point maps to under [param camera_xform] — the inverse
## of [method camera_at], and how a test says "the focused node really does land
## on the hero slot" without rendering a frame.
static func screen_to_world(camera_xform: Transform2D, screen_point: Vector2) -> Vector2:
	return camera_xform * (screen_point - viewport_size() * 0.5)


## The zoom a [method camera_for] transform encodes, as a [Camera2D] wants it.
static func zoom_of(camera_xform: Transform2D) -> Vector2:
	return Vector2.ONE / camera_xform.get_scale()


## A viewport-relative point in pixels, e.g. `slot(SPLASH_SLOT_RATIO)`.
static func slot(ratio: Vector2) -> Vector2:
	return ratio * viewport_size()


## Collapsed peek-ahead slots for [param id]'s children (#571): where they sit
## while their parent is merely hovered, before selecting it grows them out to
## their real [method solve] positions. World units, stacked tight about the
## hovered node and drawn at [member PREVIEW_SCALE].
##
## Returns `{child_id: world position}` so the caller pairs them by id rather
## than by index — the sprout animation has to know which collapsed slot became
## which real position.
static func preview_slots(tree: MenuGraph, id: StringName) -> Dictionary:
	var slots: Dictionary = {}
	if tree == null:
		return slots
	var children := tree.children_of(id)
	if children.is_empty():
		return slots
	var origin: Vector2 = solve(tree).get(id, Vector2.ZERO)
	for i in children.size():
		var offset := (float(i) - float(children.size() - 1) * 0.5) * PREVIEW_GAP
		slots[children[i]] = origin + Vector2(PREVIEW_COLUMN, offset)
	return slots
