class_name LootPicker
extends Control

## Modal pick-N-from-M loot chooser (#173) — the one HUD surface that lets the
## player pick, not just read (tooltip / spell-select are display-only). Mounted
## in HudRoot; driven by `Events.loot_pick_requested`. HudRoot filters to the
## PLAYER'S relics and calls `present(request)`; NPC relics never reach here
## (SkillDustAddon auto-resolves them).
##
## MODAL by design (PauseMenu is the precedent): while open it PAUSES the tree
## and runs itself with `process_mode = ALWAYS` (scene root). Pausing is what
## makes the block airtight — a full-rect `mouse_filter = STOP` ColorRect only
## swallows MOUSE input, but PlayerInputController's `D`-key deallocate rides
## `_unhandled_input`, which a mouse filter can't stop. Pausing halts every
## default-`PAUSABLE` gameplay node's input too, so the player can't deallocate
## the relic or end the turn mid-pick and fire the pending grant against changed
## state. It's the player's own turn, so freezing the board is fine.
##
## The card grid is built at `present()` time (candidate count varies per relic),
## not baked into the scene. Confirm enables only at exactly N selected; once N
## are picked the remaining cards disable so you can't overshoot.

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _card_row: HBoxContainer = %CardRow
@onready var _confirm_button: Button = %ConfirmButton

var _request: LootPickRequest = null
var _cards: Array[Button] = []
var _pick_count: int = 0


func _ready() -> void:
	hide()
	_confirm_button.pressed.connect(_on_confirm)


## Show the chooser for a request. HudRoot has already set `request.handled` so
## the emitter won't auto-resolve behind us.
func present(request: LootPickRequest) -> void:
	_request = request
	_pick_count = request.pick_count
	_title.text = "CLAIM LOOT"
	_subtitle.text = "Choose %d of %d" % [_pick_count, request.candidates.size()]

	for c in _cards:
		c.queue_free()
	_cards.clear()

	for m in request.candidates:
		var card := _make_card(m)
		_card_row.add_child(card)
		_cards.append(card)

	_update_state()
	show()
	get_tree().paused = true  # modal: freeze the board until a pick is confirmed


func _make_card(m: StatModifier) -> Button:
	var def := StatRegistry.get_def(m.stat_id)
	var stat_name := def.display_name if def != null else String(m.stat_id)
	var tint := def.tint_color if def != null else Color.WHITE
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(150, 90)
	card.clip_text = true
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.text = "%s\n%s" % [m.contribution_text(), stat_name]
	card.add_theme_color_override("font_color", tint)
	card.add_theme_color_override("font_hover_color", tint)
	card.add_theme_color_override("font_pressed_color", tint)
	card.toggled.connect(_on_card_toggled)
	return card


func _on_card_toggled(_pressed: bool) -> void:
	_update_state()


func _selected_count() -> int:
	var n := 0
	for c in _cards:
		if c.button_pressed:
			n += 1
	return n


## Enable confirm only at exactly N; once N are picked, lock the rest so the
## player can't overshoot (they must deselect one to swap).
func _update_state() -> void:
	var selected := _selected_count()
	var at_cap := selected >= _pick_count
	for c in _cards:
		c.disabled = at_cap and not c.button_pressed
	_confirm_button.disabled = selected != _pick_count
	_subtitle.text = "Choose %d of %d  (%d selected)" % [
			_pick_count, _request.candidates.size() if _request != null else 0, selected]


func _on_confirm() -> void:
	if _request == null or _selected_count() != _pick_count:
		return
	var chosen: Array[StatModifier] = []
	for i in _cards.size():
		if _cards[i].button_pressed:
			chosen.append(_request.candidates[i])
	var request := _request
	_request = null
	hide()
	get_tree().paused = false  # release the board before granting
	request.resolve(chosen)
