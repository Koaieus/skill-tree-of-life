class_name OutcomeApplier

## The one place an [AttackOutcome] is applied to the world — the double-
## dispatch counterpart to [method HitInstance.land_on] (#381). A static
## utility rather than a Node/system: [method BattleSystem._apply_outcome]
## is its only caller today (#474 made VFX a pure observer, so the
## original two-caller design this issue started from no longer applies —
## see the plan/issue history), but it's named and isolated deliberately as
## the deterministic "apply this outcome" boundary #458's command-replay
## model will want.


## Land every hit in append order — the view lag that used to require
## withholding each target's paint first (#487) is now the recorded
## timeline's job: [method RevealRecorder.push_cause] stamps each hit's own
## `arrival_time` onto whatever it records, and [PresentationPlayer] is what
## makes the view catch up later. Ordering between hits doesn't matter since
## [IncidentReducer] guarantees at most one landing per node per wave; see
## the #381 plan's ordering fork.
static func apply(outcome: AttackOutcome) -> void:
	for hit in outcome.hits:
		if hit.target != null:
			RevealRecorder.push_cause(hit.arrival_time)
			hit.land_on(hit.target)
			RevealRecorder.pop_cause()
