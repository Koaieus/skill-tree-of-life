class_name SpellPickerBar
extends HBoxContainer

## Renders the player [SpellBook] as a row of [SpellPickerButton]s. Selecting
## one routes through [signal spell_selected] which UIRoot forwards to
## [member BattleSystem.selected_spell]. The bar self-syncs disabled state of
## each button against the currently-selected source (so spells whose
## min_degree the source can't satisfy go grey).

signal spell_selected(spell: SpellDef)

const _SpellPickerButton := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

var _group: ButtonGroup
var _book: SpellBook = null
var _buttons_by_spell: Dictionary[SpellDef, SpellPickerButton] = {}

# The live "what is this spell being cast from?" context — used to grey out
# buttons whose min_degree isn't met by the current source. Set externally by
# UIRoot from the active MagicAttackPlan; pass null to clear gating.
var _gating_attacker: Entity = null
var _gating_source: SkillNode = null


func _ready() -> void:
	_group = ButtonGroup.new()
	_group.allow_unpress = false


## Bind to the player's spellbook. Replaces any previous binding.
func bind_spellbook(book: SpellBook) -> void:
	_book = book
	_rebuild()


## Highlight the button matching `spell` without firing [signal spell_selected].
func sync_selected(spell: SpellDef) -> void:
	for s in _buttons_by_spell.keys():
		_buttons_by_spell[s].set_pressed_no_signal(s == spell)


## Tell the bar which (attacker, source) context to gate against. Pass
## (null, null) to clear gating (all spells enabled).
func update_gating_context(attacker: Entity, source: SkillNode) -> void:
	_gating_attacker = attacker
	_gating_source = source
	_refresh_castability()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_buttons_by_spell.clear()
	if _book == null:
		return
	if _group == null:
		_group = ButtonGroup.new()
		_group.allow_unpress = false
	for spell in _book.spells:
		if spell == null:
			continue
		var btn: SpellPickerButton = _SpellPickerButton.instantiate()
		btn.spell = spell
		btn.button_group = _group
		btn.pressed.connect(_on_spell_button_pressed.bind(spell))
		add_child(btn)
		_buttons_by_spell[spell] = btn
	_refresh_castability()


func _refresh_castability() -> void:
	if _book == null:
		return
	for spell in _buttons_by_spell.keys():
		var btn := _buttons_by_spell[spell]
		btn.set_castable(_book.is_castable(spell, _gating_source, _gating_attacker))


func _on_spell_button_pressed(spell: SpellDef) -> void:
	spell_selected.emit(spell)
