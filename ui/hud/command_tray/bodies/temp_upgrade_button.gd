@tool
class_name TempUpgradeButton
extends PanelContainer
## One melee temp-upgrade card (#465): the addon's own glyph + name, painted in
## that addon kind's identity colour, in one of three visually distinct states.
##
## Replaces the `Button.new()` placeholder `MeleeBody._build_upgrade_buttons()`
## used to emit — **owner call 2026-08-29:** *"does button.new in code →
## definitely need a scene"* (`.claude/rules/scene-composition.md`).
##
## [b]Deliberately NOT a [ManageCard].[/b] The two are close — both are a
## tinted, toggleable tray card — but a Manage verb is either armed or not,
## while an upgrade has a third answer: [i]you cannot afford this right now[/i].
## That state is the one most worth making legible here, and folding it into
## `ManageCard` would grow a component five other call sites don't need.
## Merging them is filed as a follow-up on #465, to be judged once both exist.
##
## [b]Nothing here is a new colour.[/b] The glyph is the addon scene's authored
## [member SkillNodeAddon.icon] and the accent is [ActionPalette]'s entry for the
## catalog `id` — the same two reads [TempUpgradeArmedMode] makes for the cursor
## badge, so the card the player presses and the badge that lands on their
## cursor a frame later are the same glyph in the same colour, for free.

signal pressed

## The three sentences this card can say. They are three, not two: the old code
## collapsed "out of blade budget", "not your turn" and "not selected" into
## `Button.disabled` and the theme's grey, which made them one thing.
enum State {
	## Affordable, not armed — clickable, at rest.
	AVAILABLE,
	## This is what your next graph click places.
	ARMED,
	## You cannot afford this right now. Reads as a COST problem rather than an
	## absence: the accent hue stays, drained, so the player can tell that
	## freeing a blade node would bring it back — not that the option is gone.
	UNAFFORDABLE,
}

@export var label_text: String = "":
	set(v):
		label_text = v
		if is_node_ready():
			_title.text = _titled()

## The keycap that arms this card, e.g. "Z" — passed IN by
## [method MeleeBody._build_upgrade_buttons] off
## [constant PlayerInputController.TEMP_UPGRADE_KEYCAPS] by catalog index, never
## hardcoded here. Empty means "no key bound to this catalog slot", and the card
## then prints its bare name rather than an empty pair of brackets.
##
## Rendered the same way the neighbouring Reform button prints its own — as a
## trailing " (K)" in the title — so the tray teaches one keycap grammar.
@export var keycap: String = "":
	set(v):
		keycap = v
		if is_node_ready():
			_title.text = _titled()
			_restyle()

## The addon's authored glyph. Read off the addon scene by the caller, never
## looked up from a parallel table here (#664's established read).
@export var icon_texture: Texture2D = null:
	set(v):
		icon_texture = v
		if is_node_ready():
			_icon.texture = v

## This addon kind's identity colour, from [ActionPalette]. One colour means
## one addon kind everywhere in the melee panel — the spend pips and the
## blade-pip outlines already use it.
@export var accent: Color = Color.WHITE:
	set(v):
		accent = v
		if is_node_ready():
			_restyle()

## Blade-budget cost, shown in the tooltip so "unaffordable" is explicable
## rather than merely visible.
@export var cost: int = 1:
	set(v):
		cost = v
		if is_node_ready():
			_restyle()

## Whether this card is the currently-armed upgrade. Tracked SEPARATELY from
## affordability so budget changes can never silently clear an arm — the arm is
## [PlayerInputController]'s to own, and this card only mirrors it.
@export var armed: bool = false:
	set(v):
		armed = v
		if is_node_ready():
			_restyle()

## Whether the plan has budget for this upgrade right now (which also folds in
## "it's not your turn" and "there is no plan" — all three mean the same thing
## to the player: not placeable this instant).
@export var affordable: bool = true:
	set(v):
		affordable = v
		if is_node_ready():
			_restyle()

## Derived, never assigned: the single enum a caller (or a test) reads to ask
## "what does this card say right now". [constant State.ARMED] wins over
## [constant State.UNAFFORDABLE] because the arm is what your next click does,
## and a card that is both should still read as selected while it explains why
## the click will not land.
var state: State:
	get:
		if armed:
			return State.ARMED
		return State.AVAILABLE if affordable else State.UNAFFORDABLE

## The card's printed name, with the keycap suffix when there is one.
func _titled() -> String:
	return label_text if keycap.is_empty() else "%s (%s)" % [label_text, keycap]


@onready var _button: Button = %Button
@onready var _title: Label = %Title
@onready var _icon: TextureRect = %Icon


func _ready() -> void:
	_button.pressed.connect(func() -> void: pressed.emit())
	_title.text = _titled()
	_icon.texture = icon_texture
	_restyle()


## Repaint for the current [member state]. Three visually separate treatments,
## none of them Godot's default `disabled` grey:
##
## - ARMED — filled with the accent, a full-weight accent border, and the title
##   lifted one [constant Emissive.VALUE] stop so the selected card is the only
##   thing in the row that actually blooms.
## - AVAILABLE — a whisper of accent fill, a half-strength border, off-white
##   title. Reads as "clickable, at rest".
## - UNAFFORDABLE — no fill at all and a dashed-thin border, everything faded
##   through alpha while KEEPING the accent hue. The colour identity survives,
##   the substance doesn't: a cost problem, not a missing option.
func _restyle() -> void:
	if _title == null:
		return
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 9
	sb.corner_radius_top_right = 9
	sb.corner_radius_bottom_right = 9
	sb.corner_radius_bottom_left = 9
	sb.content_margin_left = 11.0
	sb.content_margin_right = 11.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0

	match state:
		State.ARMED:
			sb.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
			sb.set_border_width_all(2)
			sb.border_color = accent
			_title.modulate = Emissive.at(accent, Emissive.VALUE)
			_icon.modulate = Emissive.at(accent, Emissive.LABEL)
			self_modulate = Color.WHITE
		State.AVAILABLE:
			sb.bg_color = Color(accent.r, accent.g, accent.b, 0.07)
			sb.set_border_width_all(1)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
			_title.modulate = Color(0.86, 0.90, 0.95)
			_icon.modulate = accent
			self_modulate = Color.WHITE
		State.UNAFFORDABLE:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(1)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.22)
			_title.modulate = Color(accent.r, accent.g, accent.b, 0.40)
			_icon.modulate = Color(accent.r, accent.g, accent.b, 0.28)
			self_modulate = Color.WHITE

	add_theme_stylebox_override(&"panel", sb)
	if _button != null:
		# The overlay Button is `flat` with no text of its own, so toggling
		# `disabled` here can never surface the engine's grey — it only stops
		# the click. Every pixel the player sees comes from _restyle().
		_button.disabled = state == State.UNAFFORDABLE
		_button.button_pressed = armed
	tooltip_text = "%s — costs %d blade node%s%s%s" % [
		label_text, cost, "" if cost == 1 else "s",
		"" if keycap.is_empty() else "\nPress %s to arm it." % keycap,
		"\nNot enough blade budget right now." if state == State.UNAFFORDABLE else "",
	]
