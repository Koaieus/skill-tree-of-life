@tool
class_name FrontmatterPanel
extends Control

## One screen on the frontmatter's `%PanelLayer` — the lobby, the settings, the
## join prompt, the parked load screen, the exit confirm. A base scene: every
## concrete panel is an [i]inherited scene[/i] of `frontmatter_panel.tscn`
## that fills [member body] and authors itself as a static page (anchors and
## containers, `@tool`, no code-composed layout). It fills `%Remainder` of the
## columns scene and knows nothing of the hero column, the camera, or
## [FrontmatterPanels]; it asks to be dismissed ([signal dismissed]) and never
## dismisses itself. Nesting: this root → %OuterMargin → GlassPanel →
## %InnerMargin → %Column (%Title + %Body).
## See docs/domain/frontmatter-panels.md.

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
	_pose(eased)


## The dismissal, at its own clock position `t` (0..1) — back out to the right,
## the way it came in.
##
## [b]Its own method rather than [method set_progress] run backwards.[/b] A
## reversed entry clock inherits the entry's curve, which decelerates INTO its
## endpoint — played backwards that is a panel which lingers at full opacity and
## then vanishes at the last instant. An exit wants the opposite shape: leave
## immediately, decelerate on the way out, so the stage is clear well before the
## clock says so. Same two properties, one eased value, opposite ends.
func set_exit_progress(t: float) -> void:
	var eased := FrontmatterCamera.ease_travel(clampf(t, 0.0, 1.0))
	_pose(1.0 - eased)


## Both clocks land here, so "where a panel is at reveal `x`" is written once.
func _pose(revealed: float) -> void:
	position.x = (1.0 - revealed) * slide_offset
	modulate.a = revealed
