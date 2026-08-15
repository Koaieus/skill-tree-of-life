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
