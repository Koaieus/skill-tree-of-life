class_name OutcomeApplier

## The one place an [AttackOutcome] is applied to the world — the double-
## dispatch counterpart to [method HitInstance.land_on] (#381). A static
## utility rather than a Node/system: [method BattleSystem._apply_outcome]
## is its only caller today (#474 made VFX a pure observer, so the
## original two-caller design this issue started from no longer applies —
## see the plan/issue history), but it's named and isolated deliberately as
## the deterministic "apply this outcome" boundary #458's command-replay
## model will want.


## Withhold presentation on every target before landing anything (so the
## whole outcome mutates as one atomic step from the VFX layer's POV), then
## land every hit in append order. Two passes, same as the pre-#381
## hits-then-heals shape — ordering between hits no longer matters since
## [IncidentReducer] guarantees at most one landing per node per wave; see
## the #381 plan's ordering fork.
static func apply(outcome: AttackOutcome) -> void:
	for hit in outcome.hits:
		if hit.target != null:
			hit.target.hold_presentation()
	for hit in outcome.hits:
		if hit.target != null:
			hit.land_on(hit.target)
