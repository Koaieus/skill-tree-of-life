extends GutTest

## HighlightController follows the core-drag landing through
## [signal PlayerInputController.core_drag_target_changed]: forwarded into the
## active core-move provider, a no-op when anything else drives highlights.

var _ictl: PlayerInputController
var _ctl: HighlightController
var _landing: SkillNode


func before_each() -> void:
	_ictl = autofree(PlayerInputController.new())
	_landing = autofree(SkillNode.new())
	_ctl = HighlightController.new()
	_ctl.input_ctl = _ictl
	add_child_autofree(_ctl)


func test_emit_sets_core_provider_target() -> void:
	var core := CoreMoveHighlightProvider.new()
	_ctl.provider = core
	_ictl.core_drag_target_changed.emit(_landing)
	assert_eq(core.target, _landing, "the drag landing reaches the core-move provider")


func test_emit_without_core_provider_is_noop() -> void:
	var plan := MeleeAttackPlan.new()
	_ctl.provider = plan
	_ictl.core_drag_target_changed.emit(_landing)
	assert_eq(_ctl.provider, plan, "an attack plan keeps the highlights")
	assert_null(_ctl.active_core_provider(), "no core provider to forward into")
