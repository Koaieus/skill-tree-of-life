extends GutTest
## ManageBody's cards read the armed branch (#1222): a card is active iff its
## level is on it, so Allocate — the root's own verb — is active iff at root.

const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/manage_body.tscn")

var _ctl: PlayerInputController
var _body: ManageBody


func before_each() -> void:
	_ctl = PlayerInputController.new()
	add_child_autofree(_ctl)
	_body = _BODY_SCENE.instantiate()
	add_child_autofree(_body)
	_body.bind(null, null, _ctl)


func test_allocate_card_is_active_iff_at_root() -> void:
	assert_true(_body._allocate_card.is_armed(), "at root, Allocate is the active card")
	_ctl.arm_verb(PlayerInputController.ManageVerb.STAKE)
	assert_false(_body._allocate_card.is_armed())
	assert_true(_body._stake_card.is_armed(), "Stake's card is active while Stake is on the branch")


func test_clicking_allocate_pops_to_root() -> void:
	_ctl.arm_verb(PlayerInputController.ManageVerb.STAKE)
	_body._allocate_card.pressed.emit()
	assert_eq(_ctl.armed_stack.branch().size(), 1)
	assert_true(_body._allocate_card.is_armed())
	assert_false(_body._stake_card.is_armed())
