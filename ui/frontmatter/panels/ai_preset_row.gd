class_name AiPresetRow
extends HBoxContainer
## The AI preset row (#841, #1083): one dropdown per templated attribute of
## [member LobbyRoster.ai_preset], above the roster rows. Every AI seat without
## its own pick follows it. Ships the core dropdown; tier and camp append one
## dropdown + one signal each.
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

const _SENTINEL_LABEL := "(no preset)"

@onready var _core_pick: OptionButton = %CorePick


func _ready() -> void:
	_core_pick.item_selected.connect(_on_core_selected)


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


func _on_core_selected(index: int) -> void:
	var core: Variant = _core_pick.get_item_metadata(index)
	core_changed.emit(core if core is CoreClass else null)
