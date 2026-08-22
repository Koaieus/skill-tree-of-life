class_name LootPicker
extends ModalBase

## Modal pick-N-from-M loot chooser (#173) — the one HUD surface that lets the
## player pick, not just read (tooltip / spell-select are display-only). Mounted
## in HudRoot; driven by `Events.loot_pick_requested`. HudRoot filters to the
## PLAYER'S relics and calls `present(request)`; NPC relics never reach here
## (SkillDustAddon auto-resolves them).
##
## An inherited scene of `modal_base.tscn` (#486) — [ModalBase] owns the
## shell/freeze/confirm mechanics; [LootPickerBody] (`%BodySlot`) owns the
## card-building/selection logic specific to [StatModifier] candidates.

const _BODY_SCENE := preload("res://ui/loot_picker/loot_picker_body.tscn")


func _ready() -> void:
	super()
	confirmed.connect(_on_confirmed)


## Show the chooser for a request. HudRoot has already set `request.claim` so
## the emitter won't auto-resolve behind us.
func present(request: LootPickRequest) -> void:
	_present(_BODY_SCENE, "CLAIM LOOT", request)


## A [LootPickRequest] carries its own resolve callback — [ModalBase] never
## calls it, this does.
func _on_confirmed(chosen: Array, request: Variant) -> void:
	(request as LootPickRequest).resolve(chosen)
