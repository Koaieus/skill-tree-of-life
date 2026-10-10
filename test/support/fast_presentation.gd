class_name FastPresentation
extends RefCounted

## Squeezes the presentation clock for a test that exercises a real swing or an
## AI turn but asserts the OUTCOME, not the timing: every presentation duration
## runs at [constant RATE] and the applier's camera pre-roll is gone. A test
## that asserts real-clock timing must not use this.
##
## Three clocks sit on a launch's path and each has its own seam: the outcome
## schedule ([member BattleSystem.presentation_rate_scale]), the post-landing
## [member BattleSystem.release_beat], and the presenter's wind-up — a
## [PresentationTempo] SHAPE, scaled into a private copy handed to
## [member AttackPresenter.presentation_tempo] so the shared `.tres` is never
## mutated. The wind-up was ~0.9 s of every AI magic cast before it was covered.
## Call each entry point once per fixture: the release beat scales in place.
## The tempo is only reached through a stage already mounted when this runs.

## Duration multiplier: 0.05 runs a 1.2s swing in 60ms.
const RATE := 0.05


static func on_battle_system(battle_system: BattleSystem) -> void:
	battle_system.presentation_rate_scale = RATE
	battle_system.release_beat *= RATE
	var presenter := battle_system.stage as AttackPresenter
	if presenter != null:
		presenter.presentation_tempo = scaled_tempo(presenter.tempo())


static func on_root(root: GameRoot) -> void:
	on_battle_system(root.battle_system)
	root.command_applier.pre_roll_seconds = 0.0


## A copy of [param tempo] with every authored duration (all of its float
## exports are seconds) multiplied by [constant RATE]. Ratios between beats —
## and so every ordering the presenter stages — survive.
static func scaled_tempo(tempo: PresentationTempo) -> PresentationTempo:
	var copy := tempo.duplicate() as PresentationTempo
	for prop in copy.get_property_list():
		if prop.type == TYPE_FLOAT and prop.usage & PROPERTY_USAGE_STORAGE:
			copy.set(prop.name, float(copy.get(prop.name)) * RATE)
	return copy
