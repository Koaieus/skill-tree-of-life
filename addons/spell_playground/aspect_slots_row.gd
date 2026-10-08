## The spell playground's aspect grant: 1..[constant MAX_SLOTS] slots, each an
## [Aspect] picked from [method AspectRoster.shared] plus an amount. The panel
## turns [method slotted] into SET modifiers on the caster's `<concept>_aspect`
## stats — the caps the infusion row spends against — so the row offers a
## stepper for exactly the slotted aspects.
##
## The same aspect in two slots SUMS (no clamp): a slot is a grant, not an
## exclusive pick.
@tool
class_name AspectSlotsRow
extends VBoxContainer

## Any pick, amount or slot count changed — read [method slotted] again.
signal changed

const MAX_SLOTS: int = 4

@onready var slot_count_box: SpinBox = %SlotCountBox

var _rows: Array[HBoxContainer] = []
var _pickers: Array[OptionButton] = []
var _amounts: Array[HSlider] = []
var _amount_labels: Array[Label] = []


func _ready() -> void:
	for i in MAX_SLOTS:
		var row := get_node("Slot%d" % i) as HBoxContainer
		var picker := row.get_node("Picker") as OptionButton
		var amount := row.get_node("Amount") as HSlider
		_rows.append(row)
		_pickers.append(picker)
		_amounts.append(amount)
		_amount_labels.append(row.get_node("AmountLabel") as Label)
		_fill_picker(picker)
		# Distinct defaults, so raising the slot count offers a new aspect.
		if picker.item_count > 0:
			picker.select(i % picker.item_count)
		picker.item_selected.connect(_on_slot_edited.unbind(1))
		amount.value_changed.connect(_on_slot_edited.unbind(1))
	slot_count_box.value_changed.connect(_on_slot_edited.unbind(1))
	_refresh_rows()


## `<concept>_aspect` stat id → granted amount, over the visible slots with an
## amount above zero.
func slotted() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for i in slot_count():
		var amount := int(_amounts[i].value)
		var picker := _pickers[i]
		if amount <= 0 or picker.selected < 0:
			continue
		var id: StringName = picker.get_item_metadata(picker.selected)
		out[id] = out.get(id, 0) + amount
	return out


func slot_count() -> int:
	return clampi(int(slot_count_box.value), 1, MAX_SLOTS)


func set_slot_count(n: int) -> void:
	slot_count_box.value = n


## Point slot [param index] at the aspect whose stat is [param stat_id], at
## [param amount]. Emits [signal changed] once.
func set_slot(index: int, stat_id: StringName, amount: int) -> void:
	var picker := _pickers[index]
	for item in picker.item_count:
		if picker.get_item_metadata(item) == stat_id:
			picker.select(item)
			break
	_amounts[index].set_value_no_signal(amount)
	_on_slot_edited()


func _fill_picker(picker: OptionButton) -> void:
	picker.clear()
	for aspect in AspectRoster.shared().aspects:
		if aspect == null or aspect.stat == null:
			continue
		var label := aspect.identity.noun if aspect.identity != null and aspect.identity.noun != "" \
				else String(aspect.id()).capitalize()
		picker.add_item(label)
		picker.set_item_metadata(picker.item_count - 1, aspect.stat.id)


func _on_slot_edited() -> void:
	_refresh_rows()
	changed.emit()


func _refresh_rows() -> void:
	var n := slot_count()
	for i in MAX_SLOTS:
		_rows[i].visible = i < n
		_amount_labels[i].text = str(int(_amounts[i].value))
