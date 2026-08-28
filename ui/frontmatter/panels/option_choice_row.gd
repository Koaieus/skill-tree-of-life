class_name OptionChoiceRow
extends HBoxContainer

## One named-ladder picker in the lobby's run section (#643) — a label plus an
## [OptionButton] listing a [LobbyOptionSet] in its AUTHORED order.
##
## Deliberately the same shape as [AiCountRow]: a row scene the screen
## configures through a `set_*` call and hears back from through one signal,
## never a control the screen reaches into. [LobbyScreen] owns every choice
## (#643 decision 4) — this row reports an INDEX and knows nothing about
## [ScenarioOverride], which is what lets #558 and #638 reuse it for ladders
## that patch entirely different modules.

## Emitted only for a REAL pick. [param index] is into
## [method LobbyOptionSet.choices], so it survives an authored null slot.
signal option_picked(index: int)

@onready var _label: Label = %Label
@onready var _picker: OptionButton = %Picker

## Set while this row is writing its own widget, so the programmatic
## `select()` in [method set_choices] cannot masquerade as a player's pick.
## [OptionButton.select] does not emit `item_selected`, but [method set_value]
## exists for the screen to restore a remembered pick and the guard makes that
## safe by construction rather than by trusting the engine's current behaviour.
var _updating := false


func _ready() -> void:
	_picker.item_selected.connect(_on_item_selected)


## Fills the dropdown from [param option_set] and shows the row. A null or empty
## set leaves the row HIDDEN — the policy did not unlock this knob, and #643
## acceptance 2's "renders no control" is a fact about visibility, not about an
## empty dropdown.
func set_choices(title: String, option_set: LobbyOptionSet) -> void:
	_label.text = title
	_picker.clear()
	var choices: Array[LobbyOption] = [] if option_set == null else option_set.choices()
	visible = not choices.is_empty()
	for c in choices:
		_picker.add_item(c.label)
	# Nothing is selected until the host picks. That is #643 acceptance 5 made
	# structural: "no explicit pick" has to be a state the widget can BE in, or
	# the screen could never tell "the host chose L" from "L happens to be
	# first" and would write an override for a control nobody touched.
	_picker.select(-1)


## Re-selects [param index] without emitting — the rebuild-survival half
## ([member LobbyScreen._picked_options] is the source of truth, this is only
## its view). `-1` restores the untouched state.
func set_value(index: int) -> void:
	_updating = true
	_picker.select(index)
	_updating = false


## The index currently shown, or `-1` for "the host has not picked".
func get_value() -> int:
	return _picker.selected


func _on_item_selected(index: int) -> void:
	if _updating:
		return
	option_picked.emit(index)
