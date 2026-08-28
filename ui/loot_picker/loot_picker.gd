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
	if not request.settled.is_connected(_on_request_settled):
		request.settled.connect(_on_request_settled, CONNECT_ONE_SHOT)


## A [LootPickRequest] carries its own resolve callback — [ModalBase] never
## calls it, this does.
func _on_confirmed(chosen: Array, request: Variant) -> void:
	(request as LootPickRequest).resolve(chosen)


## #564 — a round can settle THIS request without our own confirm ever firing:
## a mirror peer's [LootSystem] adapter force-resolves its rebuilt request when
## the host's outcome comes down without a local answer (host-side timeout or
## death-mid-pick forfeit). The normal confirm path already resolves AFTER
## `_close()`, so `dismiss()` there is a harmless no-op; this is what keeps the
## client from being left holding a modal for a question the host already
## answered.
func _on_request_settled(_chosen: Array) -> void:
	dismiss()
