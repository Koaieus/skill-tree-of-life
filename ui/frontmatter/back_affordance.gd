@tool
class_name BackAffordance
extends Control

## The hero's incoming edge, made pressable — the frontmatter's back button
## (#567 / #572 / #601).
##
## [b]There is no edge to add.[/b] Owner call, 2026-08-24, verbatim: [i]"the
## 'hero' node also still has its edge connected to the left of it going
## off-screen, it's lit and all given the hero is active ('allocated')"[/i].
## Under #567's camera architecture that edge is already real — it joins the
## focused node to its actual parent, which happens to be off-screen left, and
## [method FrontmatterRoot._sync_allocation] already lights it because both ends
## are on the focus path. Nothing here draws an edge, and nothing here should
## ever start to: an affordance that minted its own stub would be a second thing
## claiming to be that edge.
##
## So this unit is the LABEL and the HIT AREA, sat on a line something else
## renders. Pressing it emits [signal back_requested]; the shell answers with
## [method FrontmatterRoot.back]. It does not call `back()` itself — this scene
## has no business holding the navigator it steers, and a signal is what lets
## #578's live tab mount it with nothing behind it.
##
## [b]At the root there is no parent, so there is no affordance.[/b] Not a
## disabled button: absent. `back()` at the root is already a no-op, and a
## visible control that does nothing is the worse of the two lies.
##
## [b]It is a [Control] in screen space, not a [Node2D] under the camera
## (#601).[/b] Owner call, 2026-08-26: [i]"Back button is a UI element, should
## be a Control root."[/i] This does not contradict sitting on the hero's
## incoming edge — it still sits there visually, because
## [method FrontmatterLayout.camera_for] docks the hero at
## [method FrontmatterLayout.hero_slot] in VIEWPORT PIXELS at every depth and
## every fan zoom. The visible run of that edge is therefore a fixed rectangle
## of the screen, not a segment of world space, and [method anchor_for]
## collapses to a screen-space point rather than a graph-space one. A
## screen-space [Control] also renders at 1.00x by definition, so the
## supersampling [MenuNodeView]'s caption needs for graph-space text
## (`_CAPTION_SUPERSAMPLE`) does not apply here and is deliberately not ported.

## Emitted when the player asks to go up one level. The shell decides what that
## means; see [method FrontmatterRoot.back].
signal back_requested

## Tier the label rests at. Owner call, 2026-08-26: [i]"raise to LABEL."[/i] —
## [constant Emissive.INERT]'s ghostly, low-contrast rest read too quiet once
## the affordance sits on its own glass backing rather than bare over the
## graph. Per `.claude/rules/hdr-color.md` a tier is what you rest at, never an
## alpha; alpha here is reserved for [method set_progress].
@export_range(0.0, 3.0, 0.05) var rest_stops: float = Emissive.LABEL:
	set(value):
		rest_stops = value
		_push_color()

## Tier the label takes while the pointer is on it. One step up from rest.
@export_range(0.0, 3.0, 0.05) var hover_stops: float = Emissive.VALUE:
	set(value):
		hover_stops = value
		_push_color()

## Scale the label starts at when [method set_progress]'s `t` is 0. Matches the
## fan components' reveal shape (`ui/tooltip_fan/mod_slab_row.gd`).
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

var tree: MenuGraph = null

## The node the affordance currently points away from, `&""` for none.
var focus_id: StringName = &""

var _hovered: bool = false

@onready var _hit: Button = %Hit


func _ready() -> void:
	_hit.pressed.connect(_on_pressed)
	_hit.mouse_entered.connect(_on_hover.bind(true))
	_hit.mouse_exited.connect(_on_hover.bind(false))
	_push_color()


func bind(menu_tree: MenuGraph) -> void:
	tree = menu_tree


## Re-sites the affordance for a new focus: present at any depth > 0, absent at
## the root. The screen position never actually changes between calls — see
## [method anchor_for] — but it is still applied here rather than once in
## [method _ready], since a live sandbox tab retunes [method
## FrontmatterLayout.hero_slot] and expects a rebuild to pick that up.
##
## [param instant] (the default) lands it in one frame; a caller that wants it to
## fade in passes `false` and drives [method set_progress]. This unit owns no
## [Tween] — one caller owns the clock, per the repo's animated-unit convention.
func apply(focus: StringName, instant: bool = true) -> void:
	focus_id = focus
	var available := is_available(tree, focus)
	visible = available
	if not available:
		set_progress(0.0)
		return
	position = anchor_for()
	set_progress(1.0 if instant else 0.0)


## Whether there is anything to go back to. False at the root and for an id the
## tree does not know.
static func is_available(tree_: MenuGraph, focus: StringName) -> bool:
	if tree_ == null or not tree_.has(focus):
		return false
	return tree_.parent_of(focus) != &""


## Where the affordance sits, in viewport pixels: half the hero slot's x, and
## the hero slot's own y.
##
## [b]A screen-space constant, not a segment computation (#601).[/b] The old
## graph-space form walked [method FrontmatterLayout.solve] for the focused
## node's and its parent's world positions and interpolated
## [code]BACK_ANCHOR_RATIO[/code] of the viewport width along that segment —
## work that only existed because the camera moved the node under a [Node2D]
## affordance. A [Control] never moves: [method
## FrontmatterLayout.camera_for] docks the focus at [method
## FrontmatterLayout.hero_slot] on screen at every depth and every zoom, so the
## visible run of the incoming edge is always the same screen rectangle and its
## midpoint is always the same screen point. `BACK_ANCHOR_RATIO` — half the
## hero slot's x over the design width — collapsed to exactly that arithmetic,
## so it is gone rather than kept as a name for one multiply. The old clamp
## guarded a shrinking [method FrontmatterLayout.column_step] pushing the label
## past the parent in world space; with no segment there is nothing left to
## clamp.
static func anchor_for() -> Vector2:
	var hero := FrontmatterLayout.hero_slot()
	return Vector2(hero.x * 0.5, hero.y)


## Applies the reveal at clock position `t` (0..1): cubic ease-out driving scale
## and fade, the same shape the tooltip-fan rows use. Drives the whole node —
## the glass backing and the label fade and scale together, since both are
## children of the [Control] this transform and modulate apply to.
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


## The colour the label renders at right now — a named [Emissive] tier against
## the neutral off-white, never a hand-picked float.
func rest_color() -> Color:
	return Emissive.neutral(hover_stops if _hovered else rest_stops)


## The press path, exposed so a test drives the affordance rather than
## synthesising a click the headless renderer cannot deliver.
func press() -> void:
	_on_pressed()


func _on_pressed() -> void:
	back_requested.emit()


func _on_hover(entered: bool) -> void:
	_hovered = entered
	_push_color()


## [Button] paints its own per-state font colours, so overriding only
## `font_color` would leave the theme's hover/pressed colours to fight the tier
## this unit picked. All four states take the same value; the rest/hover
## difference is [member _hovered]'s, not the control's.
const _FONT_STATES := [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]


func _push_color() -> void:
	if _hit == null:
		return
	var color := rest_color()
	for state: StringName in _FONT_STATES:
		_hit.add_theme_color_override(state, color)


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
