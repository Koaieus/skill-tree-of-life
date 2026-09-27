extends GutTest

## #1135 — `GameSession.start` must not alias `RunConfig.participants` into the
## roster. The roster is run-level mutable state (seat handover writes
## [member Participant.kind] into it, `scenes/game_root.gd:606-690`); the
## config can be an authored `.tres` shared across runs and even reused for a
## replay via the pause-menu seed. Aliasing meant a handover during one run
## silently rewrote the participant object backing every future run built
## from the same config.


func before_each() -> void:
	GameSession.end()


func after_all() -> void:
	GameSession.end()


func _participant(id: int, kind: Participant.Kind) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	return p


func test_roster_participant_is_not_the_configs_own_object() -> void:
	var cfg := RunConfig.new()
	cfg.participants = [
		_participant(1, Participant.Kind.HUMAN),
		_participant(2, Participant.Kind.HUMAN),
	]

	GameSession.start(cfg)

	var roster_p := GameSession.roster.by_id(1)
	assert_not_same(roster_p, cfg.participants[0],
			"roster must hold a copy, not the config's own Participant")


func test_mutating_the_roster_participant_leaves_the_config_untouched() -> void:
	var cfg := RunConfig.new()
	cfg.participants = [
		_participant(1, Participant.Kind.HUMAN),
		_participant(2, Participant.Kind.HUMAN),
	]

	GameSession.start(cfg)
	GameSession.roster.by_id(1).kind = Participant.Kind.AI

	assert_eq(cfg.participants[0].kind, Participant.Kind.HUMAN,
			"a run-level mutation (handover) must never write back into the authored config")
