@tool
class_name SpellLootPickerBody
extends ModalBodyBase

## [SpellLootPicker]'s swappable body (#486) — sibling of [LootPickerBody],
## same selection discipline (see that class's doc comment for the
## [ButtonGroup] / pick-1 vs pick-N reasoning), [SpellPickerButton] cards
## (`ui/spell_picker_bar/`) instead of plain [Button]s (instantiated for the
## card visual, never edited — #204 owns nothing under ui/spell_picker_bar/).

const _CARD_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

var _request: SpellLootRequest = null
var _cards: Array[SpellPickerButton] = []
var _pick_count: int = 0
var _group: ButtonGroup = null


func populate(request: Variant) -> void:
	_request = request as SpellLootRequest
	_pick_count = _request.pick_count
	_group = null
	if _pick_count == 1:
		_group = ButtonGroup.new()
		_group.allow_unpress = true

	for c in _cards:
		c.queue_free()
	_cards.clear()

	for s in _request.candidates:
		var card := _make_card(s)
		add_child(card)
		_cards.append(card)


func _make_card(spell: SpellDef) -> SpellPickerButton:
	var card := _CARD_SCENE.instantiate() as SpellPickerButton
	card.spell = spell
	if _group != null:
		card.button_group = _group
	card.toggled.connect(_on_card_toggled)
	return card


func _on_card_toggled(_pressed: bool) -> void:
	# Pick-1: the group itself enforces exclusivity, nothing to lock.
	if _group == null:
		var selected := _selected_count()
		var at_cap := selected >= _pick_count
		for c in _cards:
			c.set_castable(not (at_cap and not c.button_pressed))
	selection_changed.emit()


func _selected_count() -> int:
	var n := 0
	for c in _cards:
		if c.button_pressed:
			n += 1
	return n


func is_selection_valid() -> bool:
	return _selected_count() == _pick_count


func status_text() -> String:
	var total := _request.candidates.size() if _request != null else 0
	return "Choose %d of %d  (%d selected)" % [_pick_count, total, _selected_count()]


func resolve() -> Array:
	var chosen: Array[SpellDef] = []
	for c in _cards:
		if c.button_pressed:
			chosen.append(c.spell)
	return chosen
