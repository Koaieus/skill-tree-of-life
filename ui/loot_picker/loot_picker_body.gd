@tool
class_name LootPickerBody
extends ModalBodyBase

## [LootPicker]'s swappable body (#486) — one card per [StatModifier]
## candidate. A [CompositeStatModifier] is a SINGLE all-or-nothing pick that
## lists every bundled stat in its body (#183); a plain modifier flattens to
## one line, so both share [method _make_card].
##
## [b]Always a pick-ONE.[/b] The loot shape is "pick 1 out of M, N times" — N
## rounds ([member SkillDustAddon.rounds]), each raising its own request. So the
## cards are simply a [ButtonGroup] with `allow_unpress`: choosing another card
## auto-deselects the old one in one click, and re-clicking the choice drops it.
## There is no cap to enforce and nothing to lock, because there is no N-per-draw
## to overshoot.

var _request: LootPickRequest = null
var _cards: Array[Button] = []
var _group: ButtonGroup = null


func populate(request: Variant) -> void:
	_request = request as LootPickRequest
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
	var chosen: Array[StatModifier] = []
	for i in _cards.size():
		if _cards[i].button_pressed:
			chosen.append(_request.candidates[i])
	return chosen
