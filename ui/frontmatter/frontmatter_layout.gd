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


## The canvas these ratios were measured on. Never used as a screen size — only
## to convert a design pixel into the fraction it is of the layout.
const DESIGN_VIEWPORT := Vector2(1440.0, 900.0)

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
## about its parent's y at a pitch wide enough that no two subtrees can overlap.
## The alternative (every group at exactly [constant SIBLING_GAP_RATIO]) reads
## fine one branch at a time but interleaves cousins in the same column, which
## under a camera that shows a whole column at once is a collision, not a
## detail.
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
## that the two fattest adjacent subtrees still clear each other by that same
## gap. Uniform across the group, so "siblings are evenly spaced" stays true at
## every depth — only the number changes.
static func _group_gap(tree: MenuGraph, children: Array[StringName]) -> float:
	var gap := SIBLING_GAP_RATIO * DESIGN_VIEWPORT.y
	for i in children.size() - 1:
		var needed := _half_extent(tree, children[i]) + _half_extent(tree, children[i + 1]) + gap
		gap = maxf(gap, needed)
	return gap


## Half the vertical span of [param id]'s whole subtree, in world units. A leaf
## is a point (0); an internal node reaches as far as its outermost child's own
## reach. Bottom-up, so a deep branch pushes its ancestors' siblings apart
## rather than growing into them.
static func _half_extent(tree: MenuGraph, id: StringName) -> float:
	var children := tree.children_of(id)
	if children.is_empty():
		return 0.0
	var gap := _group_gap(tree, children)
	var reach := 0.0
	for i in children.size():
		var offset: float = absf((float(i) - float(children.size() - 1) * 0.5) * gap)
		reach = maxf(reach, offset + _half_extent(tree, children[i]))
	return reach
