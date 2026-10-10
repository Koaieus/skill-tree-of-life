class_name FastPresentation
extends RefCounted

## Squeezes the presentation clock for a test that exercises a real swing or an
## AI turn but asserts the OUTCOME, not the timing: every presentation duration
## runs at [constant RATE] and the applier's camera pre-roll is gone. A test
## that asserts real-clock timing must not use this.

## Duration multiplier: 0.05 runs a 1.2s swing in 60ms.
const RATE := 0.05


static func on_battle_system(battle_system: BattleSystem) -> void:
	battle_system.presentation_rate_scale = RATE


static func on_root(root: GameRoot) -> void:
	on_battle_system(root.battle_system)
	root.command_applier.pre_roll_seconds = 0.0
