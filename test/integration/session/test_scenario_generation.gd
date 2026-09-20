extends GutTest

## #641 acceptance 1/2 — the observable win #597 exists for. `coop_versus.tres`
## has no consumer today; a [RunConfig] carrying a [Scenario] pointing at it
## must generate THAT preset's map, driven through the real `scenes/level.tscn`
## end-to-end — not asserted by reading `GameSession.config.scenario.preset`
## back.
##
## [b]Why the assertion is a gradient, not a node count.[/b]
## `scenes/level.tscn`'s OWN scene-authored `preset` (the fallback #597 D6
## keeps live) is `first_level.tres` — the OPPOSITE gradient: poor centre, rich
## rim (`test_coop_versus_preset.gd`'s `test_single_player_gradient_is_untouched`
## pins that). `coop_versus.tres` is centre-rich, rim-poor. If the Scenario's
## preset were silently ignored in favour of the scene's own fallback, this
## test would see the map generate — just with the WRONG gradient — rather
## than failing to generate at all. That is what makes this a real acceptance
## test for "the Scenario's preset wins", not a smoke test for "a map exists".

const _BARE_LEVEL := preload("res://scenes/level.tscn")
const _COOP_VERSUS_SCENARIO := preload("res://session/scenarios/coop_versus.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")

## Fraction of the generated radius a node's distance must fall under/over to
## count as "centre" / "rim" — matches the innermost/outermost band shape
## `test_coop_versus_preset.gd`'s decile test already uses.
const _BAND := 0.2

var _root: GameRoot


func before_each() -> void:
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func after_each() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await wait_physics_frames(3)
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func _participant(id: int, kind: Participant.Kind, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	return p


func test_a_scenario_pointing_at_coop_versus_produces_the_centre_rich_map() -> void:
	var cfg := RunConfig.new()
	cfg.scenario = _COOP_VERSUS_SCENARIO
	cfg.seed = 20260827
	cfg.participants = [_participant(1, Participant.Kind.HUMAN, _CAMP_1)]
	GameSession.start(cfg)

	# Launched through the BARE `scenes/level.tscn` — no [RunBootstrap] — so the
	# only thing that can have supplied a preset is [member GameSession.config],
	# same shape as `test_the_bare_level_refuses_to_generate_without_a_run` in
	# `test_level_consumes_session_roster.gd`.
	_root = _BARE_LEVEL.instantiate()
	_root.auto_start_turn = false
	_root.node_count_override = 200
	add_child(_root)
	# `player` is assigned last, well after `GraphProcgen.generate` populates
	# `skill_nodes_container` — polling it (rather than the container itself)
	# avoids reading the graph mid-generation, same hazard
	# `test_level_consumes_session_roster.gd`'s `_launch` avoids by polling
	# spawned entities instead of nodes.
	for _f in 900:
		if _root.player != null:
			break
		await wait_physics_frames(1)

	var nodes: Array = _root.graph.skill_nodes_container.get_children()
	assert_false(nodes.is_empty(), "level setup never completed — nothing generated")

	var radius := 0.0
	for n in nodes:
		radius = maxf(radius, n.position.length())
	assert_gt(radius, 0.0, "precondition: nodes must be spread out")

	var centre_total := 0.0
	var centre_count := 0
	var rim_total := 0.0
	var rim_count := 0
	for n in nodes:
		var footprint: Dictionary = n.get_meta("procgen_footprint", {})
		if not footprint.has("budget"):
			continue
		var t: float = n.position.length() / radius
		if t < _BAND:
			centre_total += float(footprint["budget"])
			centre_count += 1
		elif t > 1.0 - _BAND:
			rim_total += float(footprint["budget"])
			rim_count += 1
	assert_gt(centre_count, 0, "no nodes landed in the centre band — raise node_count_override")
	assert_gt(rim_count, 0, "no nodes landed in the rim band — raise node_count_override")

	var centre_mean := centre_total / float(centre_count)
	var rim_mean := rim_total / float(rim_count)
	assert_gt(centre_mean, rim_mean,
			"coop_versus is centre-rich (means: centre %.2f, rim %.2f) — a Scenario "
			% [centre_mean, rim_mean] + "pointing at it must win over the level's own "
			+ "first_level.tres scene fallback, which is rim-rich (the opposite shape)")
