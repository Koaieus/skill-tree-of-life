@tool
class_name ManageBody
extends CommandTrayBodyBase
## Manage tab content (#114, #338): five live [ManageCard] buttons —
## Allocate/Move Core/Deallocate/Stake/Extract. Allocate/Deallocate/Stake/
## Extract switch the [ArmedStack] to their level (Allocate pops to the root);
## Move Core arms [CoreMoveMode] via
## [method PlayerInputController.enter_core_move_targeting]. A card is lit iff
## its level is on the stack's active branch.

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
## [ManageVerbMode] looks its badge tint up by.
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
	if Engine.is_editor_hint() or _input_ctl == null or _input_ctl.armed_stack == null:
		return
	# Allocate is the root's native click: its card pops back to the root.
	_allocate_card.pressed.connect(_input_ctl.armed_stack.clear_to_root)
	_dealloc_card.pressed.connect(_input_ctl.arm_verb.bind(PlayerInputController.ManageVerb.DEALLOCATE))
	_stake_card.pressed.connect(_input_ctl.arm_verb.bind(PlayerInputController.ManageVerb.STAKE))
	_extract_card.pressed.connect(_input_ctl.arm_verb.bind(PlayerInputController.ManageVerb.EXTRACT))
	_move_card.pressed.connect(_input_ctl.enter_core_move_targeting)
	_input_ctl.armed_stack.changed.connect(_refresh)
	_refresh()


func teardown() -> void:
	if _input_ctl == null or _input_ctl.armed_stack == null:
		return
	if _input_ctl.armed_stack.changed.is_connected(_refresh):
		_input_ctl.armed_stack.changed.disconnect(_refresh)


## A card is active iff its level is on the active branch (owner, 2026-09-30) —
## so Allocate, the root's own verb, is active iff nothing sits above the root.
func _refresh() -> void:
	if _input_ctl == null or _input_ctl.armed_stack == null:
		return
	var stack := _input_ctl.armed_stack
	_allocate_card.set_armed(stack.branch().size() == 1)
	_dealloc_card.set_armed(stack.find(DeallocateMode) != null)
	_stake_card.set_armed(stack.find(StakeMode) != null)
	_extract_card.set_armed(stack.find(ExtractMode) != null)
	_move_card.set_armed(stack.find(CoreMoveMode) != null)
