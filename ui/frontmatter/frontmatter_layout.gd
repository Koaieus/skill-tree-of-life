class_name FrontmatterLayout
extends RefCounted

## Where every menu node sits, and where the camera has to be for one of them to
## read as "the hero" (#567 / #568). Pure and static — no scene, no [Node], no
## frame, so the whole geometry is unit-testable
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
## identical across a run of [method camera_for] calls.
##
## [b]Geometry is authored as fractions of a design viewport plus a zoom[/b],
## never as 1440x900 literals. The ratios come from the `Game Frontmatter`
## canvas, whose own motion notes call them "a starting point, not gospel" — so
## the design pixels are recorded in the comments as provenance and the code
## uses the ratio. World units are design-viewport units: at zoom 1 one world
## unit is one design pixel, which is what makes the ratios legible here and
## resolution-independent on screen (#578's live tab tunes them).


## The canvas the ratios below were measured on. Never used as a screen size —
## only to convert a design pixel into the fraction it is of the layout.
##
## [b]It is NOT the project's viewport, and the difference is deliberate.[/b]
## `project.godot` renders into 1440x960 with `stretch/mode = "canvas_items"` and
## `stretch/aspect = "keep"`, so the visible world at [constant TREE_ZOOM] is
## always exactly [method viewport_size] units whatever window the player has —
## that stretch is what makes ONE authored geometry correct at every resolution,
## and it is why nothing here ever asks how big the window is. The `Game
## Frontmatter` canvas was drawn at 1440x900; laying that out inside a 960-tall
## viewport simply leaves 30 units of slack above and below, which is the margin
## [method fits_viewport] measures against.
##
## Keep the two apart. #578's live tab bakes design pixels into its own
## `DEFAULTS`, so redefining this as "the screen" silently desyncs every knob's
## reset value from the number the panel shows.
const DESIGN_VIEWPORT := Vector2(1440.0, 900.0)


## What the player actually sees, in world units at [constant TREE_ZOOM].
##
## The one place this file reads the project, and it answers exactly one
## question: does a fan fit on screen. Layout is authored against [constant
## DESIGN_VIEWPORT]; whether the result CLEARS the window is a different question
## with a different number, and conflating them is what let the root fan overflow
## unnoticed. Fallbacks match `project.godot`.
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



## [b]The six geometry ratios below are `static var`, not `const`, so #578's live
## sandbox tab can retune them and rebuild the menu in place.[/b] They are read
## as `FrontmatterLayout.NAME` exactly as constants were, and nothing else about
## them changed — but they ARE now process-global mutable state, so:
##
## - Gameplay code must only ever READ them. The sandbox tab is the sole writer.
## - A test that writes one must restore it (or call [method reset_geometry] in
##   its teardown), because a leaked value silently re-poses every later test's
##   menu. The existing layout tests assert relationships rather than literals,
##   which is what makes them immune either way.

## Where the focused node sits on screen: design (190, 450), centre-left.
static var HERO_SLOT_RATIO := Vector2(190.0 / 1440.0, 450.0 / 900.0)

## Horizontal distance between a node and its children, as a fraction of the
## design width. The option column sits at design x = 496 while the hero is at
## 190, so a child is 306 design px to the right of its parent — and because
## nodes never move, that spacing is the world column pitch, not a per-focus
## offset.
static var COLUMN_STEP_RATIO := (496.0 - 190.0) / 1440.0

## Vertical pitch between adjacent siblings, as a fraction of the design height
## (design 132). Uniform within a sibling group and never smaller than this
## anywhere in the tree — see [method _group_gap].
static var SIBLING_GAP_RATIO := 132.0 / 900.0

## The hover peek-ahead column (#571): a hovered node's own children, shown
## small and dim at their collapsed positions. Design x = 780 against the option
## column's 496, so 284 design px right of the node being hovered.
static var PREVIEW_COLUMN_RATIO := (780.0 - 496.0) / 1440.0
## Vertical pitch inside that collapsed stack (design 46).
static var PREVIEW_GAP_RATIO := 46.0 / 900.0
## Scale the peek-ahead nodes are drawn at.
static var PREVIEW_SCALE := 0.42


## Restores all six tunable ratios to their authored values.
##
## Exists because they are `static var`: #578's tab writes them, and a test or a
## sandbox session that leaves one changed would re-pose every menu built
## afterwards in the same process. Call it in teardown rather than remembering
## six assignments.
static func reset_geometry() -> void:
	HERO_SLOT_RATIO = Vector2(190.0 / 1440.0, 450.0 / 900.0)
	COLUMN_STEP_RATIO = (496.0 - 190.0) / 1440.0
	SIBLING_GAP_RATIO = 132.0 / 900.0
	PREVIEW_COLUMN_RATIO = (780.0 - 496.0) / 1440.0
	PREVIEW_GAP_RATIO = 46.0 / 900.0
	PREVIEW_SCALE = 0.42

## The splash (#574) is the root node, alone and close: design (50%, 44%) at
## 2.55x. "Press any button" is really allocating the first node of the run, so
## it is the same camera on the same tree, just parked.
const SPLASH_SLOT_RATIO := Vector2(0.5, 0.44)
const SPLASH_ZOOM := 2.55

## The zoom the tree is navigated at. 1.0 means one world unit per design pixel.
const TREE_ZOOM := 1.0


## Every node's world position, computed once at build time.
##
## [b]Focus is not a parameter, and must never become one.[/b] That absence is
## the invariant: two calls with the same tree return the same dictionary
## whatever the camera has been doing in between.
##
## Layout is a tidy tree — depth sets x, and a sibling group is spread evenly
## about its parent's y at a pitch wide enough that adjacent siblings' collapsed
## stacks clear each other. See [method _group_gap] for why the clearance is
## measured collapsed rather than against the whole subtree, and
## `test_frontmatter_layout.gd` for the assertion that every fan fits on screen.
static func solve(tree: MenuGraph) -> Dictionary:
	var positions: Dictionary = {}
	if tree == null or tree.root == &"":
		return positions
	_place(tree, tree.root, Vector2.ZERO, positions)
	return positions


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
	return camera_at(_focus_position(tree, focus_id), HERO_SLOT_RATIO, TREE_ZOOM)


## The parked splash camera: the root node, big, near the middle of the screen.
static func splash_camera(tree: MenuGraph) -> Transform2D:
	var root: StringName = tree.root if tree != null else &""
	return camera_at(_focus_position(tree, root), SPLASH_SLOT_RATIO, SPLASH_ZOOM)


## The world position a camera should centre its slot on, falling back to the
## root and then to the origin.
static func _focus_position(tree: MenuGraph, focus_id: StringName) -> Vector2:
	if tree == null:
		return Vector2.ZERO
	var positions := solve(tree)
	if positions.has(focus_id):
		return positions[focus_id]
	return positions.get(tree.root, Vector2.ZERO)


## The camera transform putting [param world_pos] at [param slot_ratio] of the
## viewport, at [param zoom]. A [Camera2D] anchored on its centre shows world
## point `W` at screen `(W - position) * zoom + viewport/2`, so the position
## that lands `world_pos` on a given slot is the slot's offset from the centre,
## divided by the zoom, subtracted from the target.
static func camera_at(world_pos: Vector2, slot_ratio: Vector2, zoom: float) -> Transform2D:
	var slot_offset := (slot_ratio - Vector2(0.5, 0.5)) * DESIGN_VIEWPORT
	return Transform2D(0.0, Vector2.ONE / zoom, 0.0, world_pos - slot_offset / zoom)


## World point a design-viewport point maps to under [param camera_xform] —
## the inverse of [method camera_at], and how a test says "the focused node
## really does land on the hero slot" without rendering a frame.
static func screen_to_world(camera_xform: Transform2D, design_point: Vector2) -> Vector2:
	return camera_xform * (design_point - DESIGN_VIEWPORT * 0.5)


## The zoom a [method camera_for] transform encodes, as a [Camera2D] wants it.
static func zoom_of(camera_xform: Transform2D) -> Vector2:
	return Vector2.ONE / camera_xform.get_scale()


## A design-viewport point in world units, e.g. `slot(HERO_SLOT_RATIO)`.
static func slot(ratio: Vector2) -> Vector2:
	return ratio * DESIGN_VIEWPORT


## Collapsed peek-ahead slots for [param id]'s children (#571): where they sit
## while their parent is merely hovered, before selecting it grows them out to
## their real [method solve] positions. World units, stacked tight about the
## hovered node and drawn at [constant PREVIEW_SCALE].
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
	var gap := PREVIEW_GAP_RATIO * DESIGN_VIEWPORT.y
	var column := PREVIEW_COLUMN_RATIO * DESIGN_VIEWPORT.x
	for i in children.size():
		var offset := (float(i) - float(children.size() - 1) * 0.5) * gap
		slots[children[i]] = origin + Vector2(column, offset)
	return slots


## Recursive placement: this node at [param origin], then its children one
## column to the right, spread about the same y.
static func _place(
	tree: MenuGraph, id: StringName, origin: Vector2, positions: Dictionary
) -> void:
	positions[id] = origin
	var children := tree.children_of(id)
	if children.is_empty():
		return
	var gap := _group_gap(tree, children)
	var column := COLUMN_STEP_RATIO * DESIGN_VIEWPORT.x
	for i in children.size():
		var offset := (float(i) - float(children.size() - 1) * 0.5) * gap
		_place(tree, children[i], origin + Vector2(column, offset), positions)


## The pitch a sibling group is spread at: the design gap, widened just enough
## that adjacent siblings' COLLAPSED stacks still clear each other by that same
## gap. Uniform across the group, so "siblings are evenly spaced" stays true at
## every depth — only the number changes.
##
## [b]Clearance is measured against the collapsed stack, not the whole
## subtree.[/b] That is a consequence of #570's "grow, don't cut": a view sits at
## its [method solve] home only while its parent is on the focus path, and every
## other subtree in the tree is stacked on its own parent at
## [method preview_slots] — [constant PREVIEW_GAP_RATIO] pitch, [constant
## PREVIEW_SCALE] size. So when a fan is on screen, its siblings' descendants
## occupy a stack tens of units tall, never the hundreds their expanded homes
## would span.
##
## Reserving the expanded span was the original rule, and it is why the root fan
## did not fit: `SINGLE PLAYER` and `MULTIPLAYER` demanded `66 + 132 + 132 = 330`
## between them, that pitch was applied uniformly to all four root options, and
## the outer two landed at `±495` in a 960-unit viewport. The recursion also made
## the root fan two and a half times looser than every fan below it, which reads
## as an inconsistency rather than as breathing room.
##
## [b]At most one sibling in a group is ever expanded[/b] — they share a parent,
## so at most one can be an ancestor-or-self of the focus — and that one's fan
## sits a column to the right of the neighbour it would have to clear. The
## column pitch plus this gap is what separates them, which is why the expanded
## span does not belong in this sum at all.
static func _group_gap(tree: MenuGraph, children: Array[StringName]) -> float:
	var gap := SIBLING_GAP_RATIO * DESIGN_VIEWPORT.y
	for i in children.size() - 1:
		var needed := (
			_collapsed_extent(tree, children[i])
			+ _collapsed_extent(tree, children[i + 1])
			+ gap
		)
		gap = maxf(gap, needed)
	return gap


## Half the vertical span [param id]'s subtree occupies while [param id] is NOT
## on the focus path — the only state a sibling of an expanded fan can be in.
##
## Its children rest at [method preview_slots], and their own children rest
## stacked on them by the same rule, so this recurses at the peek-ahead pitch
## rather than at the sibling pitch. A leaf is a point.
static func _collapsed_extent(tree: MenuGraph, id: StringName) -> float:
	var children := tree.children_of(id)
	if children.is_empty():
		return 0.0
	var gap := PREVIEW_GAP_RATIO * DESIGN_VIEWPORT.y
	var reach := 0.0
	for i in children.size():
		var offset: float = absf((float(i) - float(children.size() - 1) * 0.5) * gap)
		reach = maxf(reach, offset + _collapsed_extent(tree, children[i]))
	return reach
