@tool
class_name FrontmatterPanel
extends Control

## One screen on the frontmatter's `%PanelLayer` — the lobby, the settings, the
## join prompt, the parked load screen, the exit confirm (#573).
##
## [b]This is a base scene, and it earns its keep by packaging children.[/b]
## Per `.claude/rules/scene-composition.md`, every concrete panel is an
## [i]inherited scene[/i] of `frontmatter_panel.tscn` that fills [member body];
## none of them compose their own frame or title, so a structural change to the
## chrome propagates to all five for free. That is the opposite of what this
## replaces: the deleted `MenuScreen` built the same chrome in `_ready` with
## `X.new()` chains, which is why its subclasses had no scene files at all.
##
## [b]A panel never knows where the camera is.[/b] It lives under a
## [CanvasLayer], which is immune to the graph camera's pan and zoom by design
## — that is the whole reason #567 split the two layers, and the reason panel
## text stays crisp and stationary while the tree moves behind it. Nothing here
## may reach for [Camera2D], the graph layer, or [FrontmatterPanels] itself.
##
## [b]The chrome is a right-hand region, not a centred modal (#600).[/b] There
## is one baseline layout at every depth — hero column, then whatever fills the
## remainder — and a leaf panel fills that remainder the same way a fan of
## children would. [member _region]'s left edge sits at
## [method FrontmatterLayout.hero_slot]'s x plus [constant _REGION_GUTTER]; its
## right edge is the viewport edge. That boundary is a screen-space constant by
## construction — the hero docks at the same pixel at every depth and every fan
## zoom — so it is set once in [method _ready], never chased per frame the way
## the tooltip chases an arbitrary hovered node.
##
## [b]Authoring a panel is authoring a static page.[/b] Anchors and containers,
## `@tool` so the editor shows the truth, no code-composed layout — the owner's
## framing, 2026-08-26.
##
## A panel asks to be dismissed; it does not dismiss itself. [signal dismissed]
## goes up to [FrontmatterPanels], which re-emits it as
## [signal FrontmatterPanels.panel_dismissed] for the navigation state machine
## to act on — the panel has no idea what "back" means in graph terms. Since
## #600 there is exactly one back affordance ([BackAffordance], in the hero
## column) rather than one per panel; [method dismiss] survives as the route an
## inherited scene's own cancel affordance (the exit-confirm's "no") uses to
## reach the same exit.

## Emitted when this panel wants the frontmatter to return to the graph.
## [FrontmatterPanels] relays it, tagged with [member panel_id].
signal dismissed

## Which [MenuGraph] panel id this scene answers to — `MenuGraph.PANEL_LOBBY`
## and friends. [FrontmatterPanels] reads it off each child at `_ready` to build
## its registry, so a new panel is registered by [i]existing in the scene[/i]
## with this set, never by editing a table.
@export var panel_id: StringName = &"":
	set = _set_panel_id

## The all-caps heading. Authored per inherited scene; empty hides the label.
@export var title: String = "":
	set = _set_title

## Where an inherited scene puts its content. Pre-packaged by this scene, so an
## inherited scene may rely on it existing.
@onready var body: VBoxContainer = %Body

@onready var _title_label: Label = %Title
@onready var _region: Control = %Region
@onready var _column: VBoxContainer = %Column

## Clearance past the hero column's own edge, so panel content does not start
## flush against the back affordance sitting in that column.
const _REGION_GUTTER := 48.0

## Legibility bound, not a magic number: [member _region] spans the remainder
## of the viewport by design (#600), but a settings row's [HBoxContainer]
## stretching to fill all of that leaves its label and control ~1000px apart
## and unreadable (#606). Picked by screenshotting the 1440x960 design
## viewport and iterating — wide enough that the settings/join/lobby rows
## still breathe, narrow enough that every label sits next to its control.
const _CONTENT_MAX_WIDTH := 420.0


func _ready() -> void:
	_apply_title()
	_layout_region()
	_constrain_column_width()


func _set_panel_id(value: StringName) -> void:
	panel_id = value


func _set_title(value: String) -> void:
	title = value
	_apply_title()


func _apply_title() -> void:
	if not is_node_ready():
		return
	_title_label.text = title
	_title_label.visible = title != ""


## Docks [member _region]'s left edge past the hero column's right edge. Read
## off [FrontmatterLayout] rather than a literal, so a re-tuned hero slot moves
## every panel with it for free.
func _layout_region() -> void:
	if _region == null:
		return
	_region.offset_left = FrontmatterLayout.hero_slot().x + _REGION_GUTTER


## Bounds [member _column] to [constant _CONTENT_MAX_WIDTH] and pins it to the
## LEFT of [member _region] rather than letting the [MarginContainer] stretch
## it to the region's full width, or centring it in the leftover space (#606).
func _constrain_column_width() -> void:
	if _column == null:
		return
	_column.custom_minimum_size.x = _CONTENT_MAX_WIDTH
	_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## Emit [signal dismissed]. Exposed so an inherited scene can route its own
## "cancel" affordance through the same exit as [BackAffordance] rather than
## re-emitting the signal itself.
func dismiss() -> void:
	dismissed.emit()
