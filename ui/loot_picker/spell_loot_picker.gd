class_name SpellLootPicker
extends ModalBase

## Modal pick-1-from-M spell draft (#204) — sibling of [LootPicker], same
## inherited-scene-of-[ModalBase] shape (#486): the shell/freeze/confirm
## mechanics live on [ModalBase], [SpellLootPickerBody] (`%BodySlot`) owns the
## [SpellDef] card-building/selection logic. Driven by
## `Events.spell_loot_requested`; HudRoot filters to the player and queues
## this behind the dust [LootPicker] (see HudRoot's `_pending_modals`).

const _BODY_SCENE := preload("res://ui/loot_picker/spell_loot_picker_body.tscn")


func _ready() -> void:
	super()
	confirmed.connect(_on_confirmed)


## Show the draft for a request. HudRoot has already set `request.claim` so
## the emitter won't auto-resolve behind us.
func present(request: SpellLootRequest) -> void:
	_present(_BODY_SCENE, "SPELL DRAFT", request)
	if not request.settled.is_connected(_on_request_settled):
		request.settled.connect(_on_request_settled, CONNECT_ONE_SHOT)


## A [SpellLootRequest] carries its own resolve callback — [ModalBase] never
## calls it, this does.
func _on_confirmed(chosen: Array, request: Variant) -> void:
	(request as SpellLootRequest).resolve(chosen)


## #564 — see [LootPicker]'s own copy of this note: a round can settle this
## request out from under us (a mirror peer's rebuilt request, force-resolved
## by [LootSystem] when the host decided without a local answer). `dismiss()`
## is a no-op if the normal confirm path already closed us.
func _on_request_settled(_chosen: Array) -> void:
	dismiss()
