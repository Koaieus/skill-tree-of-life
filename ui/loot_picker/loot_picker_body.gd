@tool
class_name LootPickerBody
extends ModalBodyBase

## [LootPicker]'s swappable body (#486) — one card per [StatModifier]
## candidate. A [CompositeStatModifier] is a SINGLE all-or-nothing pick that
## lists every bundled stat in its body (#183); a plain modifier flattens to
## one line, so both share [method _make_card]. Confirm is only ever valid
## at exactly [member _pick_count] selected.
##
## The only production caller (`SkillDustAddon`) always asks for a pick-1
## round, and pick-1 is the shape a [ButtonGroup] fits natively: cards join
## an `allow_unpress` group so picking a different card auto-deselects the
## old one (no more "deselect first"), and clicking the selected card again
## drops the pick entirely. `pick_count > 1` is still real (pinned by this
## file's own tests) but a stock `ButtonGroup` is single-select only, so that
## path keeps the pre-existing manual cap: once N are picked, remaining
## cards lock so the player can't overshoot (must deselect one to swap).

var _request: LootPickRequest = null
var _cards: Array[Button] = []
var _pick_count: int = 0
var _group: ButtonGroup = null


func populate(request: Variant) -> void:
	_request = request as LootPickRequest
	_pick_count = _request.pick_count
	_group = null
	if _pick_count == 1:
		_group = ButtonGroup.new()
		_group.allow_unpress = true

	for c in _cards:
		c.queue_free()
	_cards.clear()

	for m in _request.candidates:
		var card := _make_card(m)
		add_child(card)
		_cards.append(card)


func _make_card(m: StatModifier) -> Button:
	var leaves := m.flatten()
	var lines: Array[String] = []
	for leaf in leaves:
		lines.append(leaf.format())
	# A single-stat card takes that stat's tint; a bundle mixes several stats,
	# so it reads in a neutral bundle tint rather than an arbitrary one.
	var tint := Color(0.9, 0.9, 0.95)
	if leaves.size() == 1:
		var def := StatRegistry.get_def(leaves[0].stat_id)
		tint = def.tint_color if def != null else Color.WHITE
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(150, 90)
	card.clip_text = true
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.text = "\n".join(lines)
	card.add_theme_color_override("font_color", tint)
	card.add_theme_color_override("font_hover_color", tint)
	card.add_theme_color_override("font_pressed_color", tint)
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
			c.disabled = at_cap and not c.button_pressed
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
	var chosen: Array[StatModifier] = []
	for i in _cards.size():
		if _cards[i].button_pressed:
			chosen.append(_request.candidates[i])
	return chosen
