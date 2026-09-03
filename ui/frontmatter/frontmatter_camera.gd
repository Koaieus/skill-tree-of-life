class_name FrontmatterCamera
extends RefCounted

## Drives the frontmatter's [Camera2D] from one focused node to another (#570).
##
## [b]Navigating the menu moves the camera and nothing else.[/b] That is #567's
## constraint 1 — the owner's [i]"no detaching please, we want to stick to
## proper skill tree vibes"[/i] — turned into architecture: node positions come
## from [method FrontmatterLayout.solve] once at build time and are never
## recomputed, so "focus B" is a camera transform and never a node edit.
##
## [b]Back navigation is the same call with the parent's id.[/b] The motion
## notes list "back-navigation doesn't mirror forward navigation" as a gap to
## implement later; under a camera there is nothing to mirror, so the gap is
## retired structurally. There is no reverse tween in this file, and there
## should never be one.
##
## [b]It owns no [Tween].[/b] The repo's convention for a reusable animated unit
## is `set_progress(t)` with one external caller driving the clock
## (`ui/tooltip_fan/addon_item.gd`); here that caller is [FrontmatterRoot], which
## drives this and the node sprouts off the same `t` so the two are one motion
## rather than two that happen to overlap.
##
## [b]Why this is not itself a [Camera2D].[/b] It is the camera's driver, not the
## camera: `frontmatter_root.tscn` authors a plain `%Camera`, and #574's splash
## parks that same camera somewhere else entirely. Keeping the arithmetic in a
## [RefCounted] means the transform contract is assertable with no scene at all,
## which is what #570's acceptance asks for.

## The camera being driven, and the tree whose layout decides where it goes.
var camera: Camera2D = null
var tree: MenuGraph = null

## Where the camera sits when the current transition finishes.
var focus_id: StringName = &""

var _from: Transform2D = Transform2D.IDENTITY
var _to: Transform2D = Transform2D.IDENTITY
var _progress: float = 1.0


func _init(camera_2d: Camera2D = null, menu_tree: MenuGraph = null) -> void:
	camera = camera_2d
	tree = menu_tree


## Puts the camera on [param id] with no travel — the state a freshly built
## frontmatter starts in, and what `reduce_motion` collapses every transition to.
func snap_to(id: StringName) -> void:
	focus_id = id
	_from = FrontmatterLayout.camera_for(tree, id)
	_to = _from
	set_progress(1.0)


## Begins a move to [param id]. The caller then drives [method set_progress]
## from 0 to 1; nothing moves until it does.
##
## [param id] becomes the focus immediately, because focus is a fact about where
## the menu IS going, not about how far along it is — [method back] mid-flight
## must reverse from the new focus, not from the one being left behind.
func travel_to(id: StringName) -> void:
	focus_id = id
	_from = current_transform()
	_to = FrontmatterLayout.camera_for(tree, id)
	set_progress(0.0)


## Applies the transition at clock position `t` (0..1). Eased inside, so the
## caller may drive `t` linearly — one place decides the curve.
func set_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	apply(transform_at(_progress))


## The transform at clock position `t`, as a value — the pure half of
## [method set_progress], and what a test asserts at `t == 0` and `t == 1`
## rather than chasing intermediate tween frames.
func transform_at(t: float) -> Transform2D:
	return _from.interpolate_with(_to, ease_travel(clampf(t, 0.0, 1.0)))


## What the camera currently reads as. Falls back to the target when there is no
## camera to ask, so the arithmetic stays testable headless.
func current_transform() -> Transform2D:
	if camera == null:
		return _to
	return Transform2D(0.0, Vector2.ONE / camera.zoom, 0.0, camera.position)


## Writes a transform onto the camera, and pushes the zoom the edge shader reads.
##
## [b]The zoom push is not optional.[/b] `graph/edge_mesh.gdshader` authors its
## width in SCREEN pixels and divides by the `edge_camera_zoom` global uniform,
## whose only other writer in the repo is [GraphCamera] — so a menu that never
## pushes it renders every edge at whatever zoom the last level left behind, and
## a menu that pushes only at the endpoints of a transition pumps the width
## through the middle of every zoom. Pushed here, on every applied frame, for
## both reasons at once.
func apply(xform: Transform2D) -> void:
	var zoom := FrontmatterLayout.zoom_of(xform)
	MenuEdgeView.push_camera_zoom(zoom.x)
	if camera == null:
		return
	camera.position = xform.origin
	camera.zoom = zoom


## Travel easing. The design canvas authors `cubic-bezier(.4, 0, .2, 1)`; this
## is the repo-native cubic ease-out that stands in for it — same shape (leaves
## fast, arrives soft), and the motion notes are explicit that the numbers are
## "a starting point, not gospel". Tuning the exact curve is #578's live tab.
static func ease_travel(t: float) -> float:
	var inv := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv * inv


## Sprout easing — the canvas's `cubic-bezier(.2, .8, .3, 1)`, a snappier
## version of the same shape, so children arrive slightly ahead of the camera
## and the fan reads as opening rather than being dragged into place.
static func ease_sprout(t: float) -> float:
	var inv := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv * inv * inv


## Charge easing — the splash's leg 1 alone (#734), and deliberately NOT
## [method ease_travel].
##
## [b]It is eased at BOTH ends, and that is the whole point.[/b] `ease_travel` is
## a cubic ease-OUT: fastest at `t == 0`, which is exactly wrong for a beat the
## owner asked to be [i]"slow at the start for a graceful move"[/i]. A pure cubic
## ease-IN overcorrects the other way — it leaves ~70% of the zoom-out to the
## last third and the opening reads as a stall rather than as a start. Smoothstep
## is the honest reading: it leaves gently, gathers pace through the middle, and
## settles into the BOOM.
##
## [b]One function so the feel is a one-line swap.[/b] #567's testing contract
## sends easing feel to the owner's eye and #578's tab, so nothing asserts the
## curve — only that leg 1 starts at the parked pose and ends at the charged one,
## which every monotonic 0->1 easing satisfies.
static func ease_charge(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
