@tool
class_name ManageBody
extends CommandTrayBodyBase
## Manage tab content (#114, #338): five live [ManageCard] buttons —
## Allocate/Move Core/Deallocate/Stake/Extract. Allocate/Deallocate/Stake/
## Extract arm PlayerInputController's shared Manage-verb dispatcher (#404);
## Move Core re-enters the pre-existing core-move targeting via
## [method PlayerInputController.enter_core_move_targeting]. Each card's
## pressed state mirrors whichever verb (or core-move) is currently armed.

@onready var _allocate_card: ManageCard = %AllocateCard
@onready var _move_card: ManageCard = %MoveCard
@onready var _dealloc_card: ManageCard = %DeallocCard
@onready var _stake_card: ManageCard = %StakeCard
@onready var _extract_card: ManageCard = %ExtractCard

## Card title colours (#664). These were five inline `title_color`s on
## `manage_body.tscn` until the armed-mode cursor badge became a second
## consumer of the same five values — and an [ArmedMode] is a `RefCounted` in
## `systems/` that cannot reach into a `.tscn` to read an export. So they moved
## to [ActionPalette] and are assigned here instead: a `.tscn` property cannot
## reference a field of an external `.tres`, so the assignment has to happen in
## code, and this is the scene's own script.
##
## Values carried over unchanged — a move, not a retune. The payoff is that the
## card a player just pressed and the badge now on their cursor match for free.
const _PALETTE := preload("res://ui/theme/action_palette.tres")

## Card → palette key. Move Core is keyed `&"move_core"` because it is a
## targeting mode rather than a [enum PlayerInputController.ManageVerb]; the
## other four are the lower-cased verb names, which is the same key
## [ManageArmedMode] looks its badge tint up by.
func _palette_keyed_cards() -> Dictionary:
	return {
		&"allocate": _allocate_card,
		&"move_core": _move_card,
		&"deallocate": _dealloc_card,
		&"stake": _stake_card,
		&"extract": _extract_card,
	}


## Paint the titles before anything else binds. Runs in the editor too (this is
## a `@tool` script), so the authored look survives in the scene view without a
## second copy of the colours living in the `.tscn`.
func _ready() -> void:
	var cards := _palette_keyed_cards()
	for key in cards:
		var card: ManageCard = cards[key]
		if card != null:
			card.title_color = _PALETTE.color_for(key)


func _on_bound() -> void:
	if Engine.is_editor_hint() or _input_ctl == null:
		return
	_allocate_card.pressed.connect(_input_ctl.arm_manage_verb.bind(PlayerInputController.ManageVerb.ALLOCATE))
	_dealloc_card.pressed.connect(_input_ctl.arm_manage_verb.bind(PlayerInputController.ManageVerb.DEALLOCATE))
	_stake_card.pressed.connect(_input_ctl.arm_manage_verb.bind(PlayerInputController.ManageVerb.STAKE))
	_extract_card.pressed.connect(_input_ctl.arm_manage_verb.bind(PlayerInputController.ManageVerb.EXTRACT))
	_move_card.pressed.connect(_input_ctl.enter_core_move_targeting)
	_input_ctl.manage_arm_changed.connect(_refresh.unbind(1))
	_input_ctl.core_move_targeting_changed.connect(_refresh.unbind(1))
	_refresh()


func teardown() -> void:
	if _input_ctl == null:
		return
	if _input_ctl.manage_arm_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.manage_arm_changed.disconnect(_refresh.unbind(1))
	if _input_ctl.core_move_targeting_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.core_move_targeting_changed.disconnect(_refresh.unbind(1))


func _refresh() -> void:
	if _input_ctl == null:
		return
	var arm := _input_ctl.manage_arm()
	_allocate_card.set_armed(arm == PlayerInputController.ManageVerb.ALLOCATE)
	_dealloc_card.set_armed(arm == PlayerInputController.ManageVerb.DEALLOCATE)
	_stake_card.set_armed(arm == PlayerInputController.ManageVerb.STAKE)
	_extract_card.set_armed(arm == PlayerInputController.ManageVerb.EXTRACT)
	_move_card.set_armed(_input_ctl.move_targeting_source() != null)
