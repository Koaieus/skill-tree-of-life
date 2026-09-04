@tool
class_name RunEndOverlay
extends CanvasLayer

## The one surface a finished run ends on (#526) — win, loss and draw alike.
## Replaces the `GameOverStub` it grew out of (a dim rect and a 64pt "GAME
## OVER", raised only on defeat), which left a draw with a banner and no way
## out of the level except GameRoot's unprompted auto-route.
##
## It draws a **reading**, never an outcome. [RunOutcome] is point-of-view-free
## since #517 — it names a winning camp and nothing else — and turning that into
## "victory" / "defeat" / "the run ended" is [HudRoot]'s call, because the point
## of view is a fact about this MACHINE. So seating decides the COPY here; it
## never decides whether the overlay appears. Every screen watching a finished
## run gets one, or a draw would still have no way out.
##
## The action row is deliberately LATE. The terminal banner owns the first
## couple of seconds ([Banner]'s open + hold + close runs ~2.2s), and a button
## materialising under it pulls the eye off the announcement it is meant to
## follow. `present()` raises the dim and the copy at once, the row after
## [member action_row_delay].
##
## **Not a [ModalBase], and must not become one.** A modal guarantees `closed`
## fires exactly once per `present()`, and HudRoot's `_modal_busy` stays latched
## until it does. A terminal surface never closes, so routing this through the
## modal queue would wedge that queue shut for the rest of the run. It stays a
## plain CanvasLayer at layer 100 — the bloom ceiling, see `ui/z_layers.gd`.

## The player asked to leave. The overlay does **not** route itself: [GameRoot]
## owns the route out and the `route_to_meta_on_run_end` veto over it, and
## HudRoot is what wires the two together.
signal main_menu_pressed

## How THIS screen reads the run's end — not a property of the outcome. Two
## screens watching the same [RunOutcome] legitimately read it differently.
enum Reading {
	## A seated hero's camp won.
	VICTORY,
	## A seated hero's camp did not win.
	DEFEAT,
	## A camp won, but this screen has no camp to have lost from — a couch,
	## where every rival is sitting on it.
	NEUTRAL,
	## Nobody won.
	DRAW,
	## Not an outcome at all: the wire under this run died and there is no
	## rejoin (#733 — no drop-in mid-game). Raised by
	## [method HudRoot.present_link_lost], never by a [RunOutcome]. The overlay
	## is still the right surface because it carries the only way out.
	LINK_LOST,
}

const _TITLES: Dictionary = {
	Reading.VICTORY: "VICTORY",
	Reading.DEFEAT: "DEFEAT",
	Reading.NEUTRAL: "RUN OVER",
	Reading.DRAW: "DRAW",
	Reading.LINK_LOST: "CONNECTION LOST",
}

## Crimson from `.claude/rules/ui-palette.md` (health). A defeat title tinted
## with the *winner's* camp colour would celebrate in the loser's face.
const _DEFEAT_TINT := Color(0.8878, 0.203, 0.2233)

## Seconds between the overlay appearing and its action row, long enough to
## clear the terminal banner. Exported so a fixture can shrink it — asserting
## "absent now, present after" should not cost a real 2.5s per test.
@export_range(0.0, 10.0, 0.1, "or_greater") var action_row_delay: float = 2.5

@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
## Structured as a row, holding exactly one action today. A second (`spectate`)
## is an append here — nothing needs one yet, so nothing builds one.
@onready var action_row: HBoxContainer = %ActionRow
@onready var main_menu_button: Button = %MainMenuButton

## The reading currently on screen. Only meaningful after [method present].
var reading: Reading = Reading.NEUTRAL


func _ready() -> void:
	main_menu_button.pressed.connect(_on_main_menu_pressed)


## Raise the overlay for a finished run. [param camp] is the winning camp, or
## null for a draw; it is what the subtitle names, whatever the reading —
## unless [param subtitle] is given, which a reading with no camp to name
## ([constant Reading.LINK_LOST]) uses to say what actually happened.
##
## Coroutine — it returns at the `await` and resumes to reveal the action row.
## Callers do not wait on it; the overlay itself is already up by then.
func present(run_reading: Reading, camp: Faction, subtitle: String = "") -> void:
	reading = run_reading
	title_label.text = _TITLES[run_reading]
	title_label.add_theme_color_override("font_color", _title_color(camp))
	subtitle_label.text = subtitle if not subtitle.is_empty() else _subtitle_for(camp)
	action_row.visible = false
	visible = true
	if action_row_delay > 0.0:
		await get_tree().create_timer(action_row_delay).timeout
		# The level can be torn down inside the delay (the fallback route, a
		# test fixture ending) — resuming on a freed node would error.
		if not is_inside_tree():
			return
	action_row.visible = true
	main_menu_button.grab_focus()


## Get out of the way without ending anything. Only reached where there is no
## route to take — see [method HudRoot._on_run_end_main_menu_pressed]. A run
## that really is leaving keeps its overlay up through the fade.
func dismiss() -> void:
	visible = false
	action_row.visible = false


func _title_color(camp: Faction) -> Color:
	if reading == Reading.DEFEAT:
		return Emissive.at(_DEFEAT_TINT, Emissive.ALERT)
	if camp == null:
		return Emissive.neutral(Emissive.VALUE)
	return Emissive.at(camp.color, Emissive.ALERT)


## The subtitle names the winner in all three winning readings — a couch needs
## it to know who won at all, and a seat still wants to know to whom.
func _subtitle_for(camp: Faction) -> String:
	if camp == null:
		return "the tree stands unclaimed"
	return "%s holds the tree" % camp.display_name


func _on_main_menu_pressed() -> void:
	main_menu_pressed.emit()
