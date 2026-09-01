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
## children would.
##
## [b]This scene IS the region, not a positioner for one (#603 D5/D6).[/b] It
## used to compute its own left edge off [method FrontmatterLayout.hero_slot]
## plus a gutter, onto an anchored `%Region` child — arithmetic expressing the
## two-column split a SECOND time, in code, beside `frontmatter_columns.tscn`'s
## own container layout. Since #603 this scene is parented straight into that
## scene's `%Remainder` column (`frontmatter_root.tscn`, under `%PanelLayer`),
## so this root [Control]'s own `anchors_preset = 15` already fills exactly the
## rect the old `%Region` computed by hand, and there is nothing left to chase
## per frame the way the tooltip chases an arbitrary hovered node.
##
## [b]A panel knows nothing about column 1 either (#611 D1).[/b] Owner,
## verbatim: [i]"if i were to place a child in the 2nd column... it should
## naturally occupy that space. any authored panel doesn't even know about the
## 1st column, they just author themselves, standalone."[/i] Nothing in this
## scene reads a hero-column width or a gutter; a panel dropped into
## `%Remainder` grows to take the space it is given, full stop.
##
## [b]The nesting is inside-out from what it draws (#611 D2).[/b] Owner,
## verbatim: [i]"margins should be applied to top right and bottom, possibly
## left too -> then the panel (with glass background) is centered in there...
## and inside that panel is more margins -> headers + actual content."[/i] So:
## [codeblock]
##   FrontmatterPanel        (this scene's own root, already fills %Remainder)
##     %OuterMargin           top / right / bottom (and left)
##       GlassPanel            fills the outer margin's inset rect
##         %InnerMargin          the legibility padding around content
##           %Column               %Title  +  %Body
## [/codeblock]
## The glass used to sit edge-to-edge against the viewport (#606's
## `_CONTENT_MAX_WIDTH` compensated by narrowing the CONTENT instead); now the
## OUTER margin insets the glass itself, visibly, from the viewport's own
## edges.
##
## [b]`_CONTENT_MAX_WIDTH` is retired (#611 D3).[/b] It was a compensation, not
## a legibility bound — #609 fixed the row-layout cause it was compensating
## for (a settings row's own [HBoxContainer] no longer stretches to strand its
## label from its control), so the column sizes off its content and its
## column instead of a hand-picked pixel width.
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

## How far right of its home the panel starts its slide-in, in pixels (#567's
## bridge animation). Authored on the base scene, so every inherited panel
## enters the same way; #578's live tab tunes it.
@export_range(0.0, 400.0, 1.0) var slide_offset: float = 72.0

## Where an inherited scene puts its content. Pre-packaged by this scene, so an
## inherited scene may rely on it existing.
@onready var body: VBoxContainer = %Body

@onready var _title_label: Label = %Title


func _ready() -> void:
	_apply_title()


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


## Emit [signal dismissed]. Exposed so an inherited scene can route its own
## "cancel" affordance through the same exit as [BackAffordance] rather than
## re-emitting the signal itself.
func dismiss() -> void:
	dismissed.emit()


## The reveal, at clock position `t` (0..1): a slide in from the right plus a
## fade. The repo's animated-unit contract — no [Tween] here, one external
## caller owns the clock — and that caller is [FrontmatterRoot], which drives
## this off the SAME `t` as the camera travel it overlaps (see
## [member FrontmatterRoot.panel_lead]).
##
## [b]Why the panel opens before the camera lands.[/b] Waiting for the pan to
## finish made a leaf feel like it took 850ms to answer a click; the slide is
## the bridge across that gap, so the panel is up and readable while the tree
## is still settling behind it.
##
## [b]It writes `position`, not an inner offset.[/b] Both this scene's parents
## (`FrontmatterPanels`, and `frontmatter_columns.tscn`'s `%Remainder`) are
## plain [Control]s rather than containers, so nothing re-lays this root out
## and the write survives; landing at exactly `0` every time keeps it from
## accumulating drift. Slide it from inside a container and a resize would
## snap it back mid-flight.
func set_progress(t: float) -> void:
	var eased := FrontmatterCamera.ease_sprout(clampf(t, 0.0, 1.0))
	position.x = (1.0 - eased) * slide_offset
	modulate.a = eased
