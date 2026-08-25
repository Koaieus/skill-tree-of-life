@tool
class_name BackAffordance
extends Node2D

## The hero's incoming edge, made pressable — the frontmatter's back button
## (#567 / #572).
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

## Emitted when the player asks to go up one level. The shell decides what that
## means; see [method FrontmatterRoot.back].
signal back_requested

## How far along the incoming edge, from the hero back toward its parent, the
## label sits — as a fraction of the viewport's width.
##
## [b]Derived, not picked.[/b] The hero slot is at x = 190 and a parent sits one
## column step (306px, [method FrontmatterLayout.column_step]) to its left — so
## at x = -116, which is the off-screen-left the owner's note describes. The
## stretch of that edge a player can actually see therefore runs from the
## screen's left edge to the hero, and its midpoint is half the hero slot's x.
## Anchoring there puts the label in the middle of the visible run at every
## depth, because under a camera every depth presents the same picture.
const BACK_ANCHOR_RATIO := (190.0 * 0.5) / 1440.0

## Tier the label rests at. [constant Emissive.INERT] sits exactly at the bloom
## threshold and never blooms, which is the whole of "ghostly, low-contrast" —
## per `.claude/rules/hdr-color.md` quiet is a tier you drop to, never an alpha
## you fade to, so alpha here is reserved for [method set_progress].
@export_range(0.0, 3.0, 0.05) var rest_stops: float = Emissive.INERT:
	set(value):
		rest_stops = value
		_push_color()

## Tier the label takes while the pointer is on it. One step up, so the
## affordance answers without lighting up like a menu item.
@export_range(0.0, 3.0, 0.05) var hover_stops: float = Emissive.LABEL:
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


## Re-sites the affordance for a new focus: present and anchored on the incoming
## edge at any depth > 0, absent at the root.
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
	var homes := FrontmatterLayout.solve(tree)
	position = anchor_for(homes[focus] as Vector2, homes[tree.parent_of(focus)] as Vector2)
	set_progress(1.0 if instant else 0.0)


## Whether there is anything to go back to. False at the root and for an id the
## tree does not know.
static func is_available(tree_: MenuGraph, focus: StringName) -> bool:
	if tree_ == null or not tree_.has(focus):
		return false
	return tree_.parent_of(focus) != &""


## Where on the incoming edge the label sits: [constant BACK_ANCHOR_RATIO] of
## the design width along the segment from [param hero] toward [param parent].
##
## Clamped to the segment's own midpoint, so a tree whose column step ever grew
## shorter than the hero slot's x cannot push the label past the parent and out
## the far end of the edge it is supposed to be sitting on.
static func anchor_for(hero: Vector2, parent: Vector2) -> Vector2:
	var span := parent - hero
	var length := span.length()
	if length <= 0.0:
		return hero
	var along: float = minf(BACK_ANCHOR_RATIO * FrontmatterLayout.viewport_size().x, length * 0.5)
	return hero + span / length * along


## Applies the reveal at clock position `t` (0..1): cubic ease-out driving scale
## and fade, the same shape the tooltip-fan rows use.
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
