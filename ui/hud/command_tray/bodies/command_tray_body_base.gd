@tool
class_name CommandTrayBodyBase
extends MarginContainer
## Base for the four Command Tray per-mode body scenes (#114): Manage /
## Melee / Ranged / Magic. [CommandTray] instantiates exactly one of these
## into its content slot per the currently-selected attack mode and calls
## [method bind] / [method teardown] across swaps — same "swap a
## pre-authored scene by context" shape [ContextPanel] already uses, but
## keyed by *attack mode* rather than *player context* (attack-plan active /
## core-move targeting / pinned node / idle), which is a different axis:
## e.g. picking the Melee tab doesn't mean an attack plan exists yet, and
## a pinned node has nothing to do with which mode tab is selected. That
## mismatch is why the tray can't just reuse a ContextPanel instance
## verbatim — see command_tray.gd's header comment.
##
## Root is a MarginContainer (0 margin) so the tray's fixed-height content
## chrome sees this body's real minimum size, same reasoning as
## CombatReadoutCard (see that class's doc comment).

var _player: Entity
var _battle_system: BattleSystem
var _input_ctl: PlayerInputController
## The seat's armed-input stack ([member PlayerInputController.armed_stack]):
## the armed plan and its signals. Null when bound without a controller.
var _armed_stack: ArmedStack


func bind(player: Entity, battle_system: BattleSystem, input_ctl: PlayerInputController) -> void:
	_player = player
	_battle_system = battle_system
	_input_ctl = input_ctl
	_armed_stack = input_ctl.armed_stack if input_ctl != null else null
	_on_bound()


## Virtual — subclasses wire their own signals off the deps captured above.
func _on_bound() -> void:
	pass


## The seat's armed plan, or null.
func _armed_plan() -> AttackPlan:
	return _armed_stack.attack_plan() if _armed_stack != null else null


## The RESET button: clear the armed plan's selection.
func _reset_plan() -> void:
	if _armed_stack != null:
		_armed_stack.reset_plan()


## Called by [CommandTray] right before the body is freed on a mode switch.
## Override to disconnect anything connected in [method _on_bound].
func teardown() -> void:
	pass
