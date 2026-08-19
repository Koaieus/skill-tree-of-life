class_name SpellLootPicker
extends ModalBase

## Modal pick-1-from-M spell draft (#204) — sibling of [LootPicker], same
## inherited-scene-of-[ModalBase] shape (#486): the shell/freeze/confirm
## mechanics live on [ModalBase], [SpellLootPickerBody] (`%BodySlot`) owns the
## [SpellDef] card-building/selection logic. Driven by
## `Events.spell_loot_requested`; HudRoot filters to the player and queues
## this behind the dust [LootPicker] (see HudRoot's `_pending_picks`).

const _BODY_SCENE := preload("res://ui/loot_picker/spell_loot_picker_body.tscn")


## Show the draft for a request. HudRoot has already set `request.handled` so
## the emitter won't auto-resolve behind us.
func present(request: SpellLootRequest) -> void:
	_present(_BODY_SCENE, "SPELL DRAFT", request)
