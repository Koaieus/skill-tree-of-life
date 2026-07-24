class_name SpellLootPicker
extends Control

## Modal pick-1-from-M spell draft (#204) — sibling of [LootPicker], same modal
## discipline: pauses the tree while open (see LootPicker's class doc for why
## pausing, not just a mouse-filter, is what makes the block airtight). Cards
## are [SpellPickerButton]s (`ui/spell_picker_bar/`) — instantiated for the
## card visual, never edited (#204 owns nothing under ui/spell_picker_bar/).
## Driven by `Events.spell_loot_requested`; HudRoot filters to the player and
## queues this behind the dust [LootPicker] (both modals pause the tree, so a
## kill's two picks are serialized — dust first, then this).
##
## The card grid is built at `present()` time (candidate count varies per
## draft), not baked into the scene. Confirm enables only at exactly N
## selected; once N are picked the remaining cards disable so you can't
## overshoot — identical selection discipline to LootPicker.

const _CARD_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

## Fired after the draft closes (confirmed or auto-hidden) so HudRoot's pending
## queue can present the next request. Mirrors [signal LootPicker.closed].
signal closed()

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _card_row: HBoxContainer = %CardRow
@onready var _confirm_button: Button = %ConfirmButton

var _request: SpellLootRequest = null
var _cards: Array[SpellPickerButton] = []
var _pick_count: int = 0


func _ready() -> void:
	hide()
	_confirm_button.pressed.connect(_on_confirm)


## Show the chooser for a request. HudRoot has already set `request.handled` so
## the emitter won't auto-resolve behind us.
func present(request: SpellLootRequest) -> void:
	_request = request
	_pick_count = request.pick_count
	_title.text = "SPELL DRAFT"
	_subtitle.text = "Choose %d of %d" % [_pick_count, request.candidates.size()]

	for c in _cards:
		c.queue_free()
	_cards.clear()

	for s in request.candidates:
		var card := _make_card(s)
		_card_row.add_child(card)
		_cards.append(card)

	_update_state()
	show()
	get_tree().paused = true  # modal: freeze the board until a pick is confirmed


func _make_card(spell: SpellDef) -> SpellPickerButton:
	var card := _CARD_SCENE.instantiate() as SpellPickerButton
	card.spell = spell
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
		c.set_castable(not (at_cap and not c.button_pressed))
	_confirm_button.disabled = selected != _pick_count
	_subtitle.text = "Choose %d of %d  (%d selected)" % [
			_pick_count, _request.candidates.size() if _request != null else 0, selected]


func _on_confirm() -> void:
	if _request == null or _selected_count() != _pick_count:
		return
	var chosen: Array[SpellDef] = []
	for c in _cards:
		if c.button_pressed:
			chosen.append(c.spell)
	var request := _request
	_request = null
	hide()
	get_tree().paused = false  # release the board before granting
	request.resolve(chosen)
	closed.emit()
