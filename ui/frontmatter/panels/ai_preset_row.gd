class_name AiPresetRow
extends HBoxContainer
## The AI preset row (#841, #1083): one dropdown per templated attribute of
## [member LobbyRoster.ai_preset], above the roster rows. Every AI seat without
## its own pick follows it. Core always; camp (#884) only where the policy lets
## an AI seat pick one. Tier appends one dropdown + one signal the same way.
##
## Every dropdown's FIRST entry is a sentinel meaning "no preset" (owner,
## 2026-09-10 — "preset row should get a sentinel... such that things don't
## change too much"), and it is the initial value. While it is selected this
## row templates nothing for that attribute — see
## [method LobbyRoster.resolve_templated].

## The core preset changed. `null` is the sentinel ("no preset") — never a
## real [CoreClass] that merely reads as "off"; the sentinel is its own
## dropdown entry, not inferred from an empty selection.
signal core_changed(core: CoreClass)
## The camp preset changed; `null` is the sentinel, #759 decision 5's "any camp".
signal camp_changed(camp: Faction)
## The tier preset changed (#1086): an [enum AIController.Tier] as an int, or
## `null` for the sentinel.
signal tier_changed(tier: Variant)

const _SENTINEL_LABEL := "(no preset)"

@onready var _core_pick: OptionButton = %CorePick
@onready var _camp_pick: OptionButton = %CampPick


func _ready() -> void:
	_core_pick.item_selected.connect(_on_core_selected)
	_camp_pick.item_selected.connect(_on_camp_selected)


## Fill the core dropdown with [param cores], sentinel first and selected —
## arming the preset is something the player opts into, never the row's own.
func set_core_choices(cores: Array[CoreClass]) -> void:
	_core_pick.clear()
	_core_pick.add_item(_SENTINEL_LABEL)
	_core_pick.set_item_metadata(0, null)
	for i in cores.size():
		var core: CoreClass = cores[i]
		_core_pick.add_item(core.display_name if core.display_name != "" else core.resource_path.get_file())
		_core_pick.set_item_metadata(i + 1, core)
	_core_pick.select(0)


## Fill the camp dropdown with [param camps], sentinel first and selected, and
## show it. Never called is the unpoliced / AI-camps-locked row: no camp control.
func set_camp_choices(camps: Array[Faction]) -> void:
	_camp_pick.clear()
	_camp_pick.add_item(_SENTINEL_LABEL)
	_camp_pick.set_item_metadata(0, null)
	for i in camps.size():
		var camp: Faction = camps[i]
		_camp_pick.add_item(camp.display_name if camp.display_name != "" else String(camp.id))
		_camp_pick.set_item_metadata(i + 1, camp)
	_camp_pick.select(0)
	_camp_pick.visible = true
	%CampLabel.visible = true


func _on_camp_selected(index: int) -> void:
	var camp: Variant = _camp_pick.get_item_metadata(index)
	camp_changed.emit(camp if camp is Faction else null)


func _on_core_selected(index: int) -> void:
	var core: Variant = _core_pick.get_item_metadata(index)
	core_changed.emit(core if core is CoreClass else null)
