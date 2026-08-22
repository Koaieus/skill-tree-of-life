@tool
class_name SpellLootPickerBody
extends ModalBodyBase

## [SpellLootPicker]'s swappable body (#486) — sibling of [LootPickerBody],
## same selection discipline (see that class's doc comment for why a loot draw
## is always a pick-ONE [ButtonGroup]), [SpellPickerButton] cards
## (`ui/spell_picker_bar/`) instead of plain [Button]s (instantiated for the
## card visual, never edited — #204 owns nothing under ui/spell_picker_bar/).

const _CARD_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

var _request: SpellLootRequest = null
var _cards: Array[SpellPickerButton] = []
var _group: ButtonGroup = null


func populate(request: Variant) -> void:
	_request = request as SpellLootRequest
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
	card.button_group = _group
	card.toggled.connect(_on_card_toggled)
	return card


func _on_card_toggled(_pressed: bool) -> void:
	# The group enforces exclusivity itself — this only forwards the change.
	selection_changed.emit()


func is_selection_valid() -> bool:
	return _group != null and _group.get_pressed_button() != null


func status_text() -> String:
	var total := _request.candidates.size() if _request != null else 0
	return "Choose 1 of %d" % total


func resolve() -> Array:
	var chosen: Array[SpellDef] = []
	for c in _cards:
		if c.button_pressed:
			chosen.append(c.spell)
	return chosen
