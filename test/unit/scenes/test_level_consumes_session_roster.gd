extends GutTest

## #553 — the level SPAWNS FROM the session's roster instead of building its own,
## and the roster decides how many contenders procgen makes room for.
##
## Deliberately drives the real level scene rather than the helpers in isolation:
## the defect this unit fixes is not "the roster is grouped wrongly", it is the
## *order of authority* between `GameSession` and `_setup_level`, and only a
## level that actually runs can be wrong about that. Single process, no
## transport — the property #549's split was drawn along, so the two-machine
## half (#554) is what needs two processes, not this.
##
## [b]Two launches, on purpose.[/b] A full procgen level is the expensive thing
## here (and leaves texture RIDs the headless dummy renderer reports at exit),
## so the assertions are packed into as few as they fit rather than one per
## behaviour.
##
## [b]What is a pin and what is a guard.[/b] The starter-count and
## `local_peer_id` assertions genuinely bite — verified by reverting each and
## watching them fail. `assert_same` on the session's roster is a REGRESSION
## GUARD, not a pin: the code this replaced already reused the session's object
## when there was one, so no single-process observable separates them. It exists
## to catch a future edit that starts rebuilding the roster again.

const _SANDBOX := preload("res://scenes/first_level_sandbox.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _CAMP_3 := preload("res://entity/factions/camp_3.tres")

var _root: GameRoot


func before_each() -> void:
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func after_each() -> void:
	# Freed explicitly rather than by autofree: a level holds a few hundred
	# SkillNodes with textures, and draining them per test roughly halves the
	# headless dummy renderer's "leaked RIDs at exit" report. It does not clear
	# it — the remainder is texture-cache teardown for procgen content, reported
	# at engine shutdown and not reachable from here.
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await wait_physics_frames(3)
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func _participant(id: int, kind: Participant.Kind, camp: Faction, peer_id: int = 0) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	p.peer_id = peer_id
	return p


func _launch() -> GameRoot:
	var root: GameRoot = _SANDBOX.instantiate()
	root.auto_start_turn = false
	root.node_count_override = 40
	root.enemy_territory_size = 1
	# Deliberately pinned BELOW every roster these tests build. The scene authors
	# 5, which would leave room for a 6-contender roster by luck and let a level
	# that ignored the roster pass anyway. At 1, the preset's single authored
	# starting point plus this yields 2 starters — so a test with more than two
	# participants fails unless the count is genuinely derived.
	root.n_random_starters = 1
	add_child(root)
	_root = root
	# `_setup_level` is asynchronous — `GraphProcgen.generate` yields a frame per
	# phase so the loading bar can repaint. Freeing the level mid-await crashes
	# the engine outright, so wait for the spawn to land rather than for a fixed
	# frame count.
	for _f in 900:
		if not _spawned_entities(root).is_empty():
			break
		await wait_physics_frames(1)
	assert_false(_spawned_entities(root).is_empty(),
			"level setup never completed — nothing spawned")
	return root


## The roster's entities only. `entities_container` also holds the preset's
## blockers, which are `Entity`s too ([method GameRoot.spawn_blocker]) but are
## placement content rather than participants — counting them would make this
## suite a test of `first_level.tres`'s blocker budget.
##
## Discriminated by faction, not by name: two blockers of the same size collide
## on `Blocker_<size>` and Godot renames the later ones to `@Node@N`, so a name
## prefix silently under-counts them.
func _spawned_entities(root: GameRoot) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in root.graph.entities_container.get_children():
		if c is Entity and (c as Entity).faction != null \
				and (c as Entity).faction.id != &"blocker":
			out.append(c)
	return out


func test_the_session_roster_decides_the_contenders_the_camps_and_the_seat() -> void:
	# Four contenders across three camps, with two machines in them. One launch
	# covers every seam this unit touches except the no-session fallback.
	var roster := ParticipantRoster.new()
	var mine := _participant(1, Participant.Kind.LOCAL_HUMAN, _CAMP_1, 5)
	roster.add(mine)
	roster.add(_participant(2, Participant.Kind.REMOTE_HUMAN, _CAMP_2, 9))
	roster.add(_participant(3, Participant.Kind.AI, _CAMP_3))
	roster.add(_participant(4, Participant.Kind.AI, _CAMP_2))
	GameSession.start(RunConfig.new())
	GameSession.roster = roster
	GameSession.local_peer_id = 5

	var root := await _launch()

	# PIN: `n_random_starters` is pinned to 1 above, so the preset yields 2
	# starting points unless the count is derived from the roster. A short list
	# trims the spawn (with a warning) rather than failing loudly, which is why
	# entity count is the assertion.
	var spawned := _spawned_entities(root)
	assert_eq(spawned.size(), 4,
			"four contenders must get four starting points — the roster decides the "
			+ "camp count, procgen no longer decides how many opponents exist")

	# PIN: the camps come from the roster, not from the scene. The sandbox's own
	# fallback only ever authors `player` and `npc`, so camp_1/2/3 appearing at
	# all is proof the session's roster was the source.
	var camps: Array[StringName] = []
	for e in spawned:
		camps.append(e.faction.id)
	assert_true(camps.has(_CAMP_1.id), "camp_1 came from the roster")
	assert_true(camps.has(_CAMP_2.id))
	assert_true(camps.has(_CAMP_3.id))

	# PIN: `from_roster` is fed the session's `local_peer_id`. With a human on
	# another peer this must be a SEAT pinned to THIS machine's human — left at
	# the parameter default it degenerates to a seatless spectator.
	assert_false(root.seat_policy.follows_active_turn(),
			"a roster with a human on another peer is a SEAT, not a couch")
	assert_true(root.seat_policy.seats(root.player),
			"and the seat is THIS machine's human")

	# GUARD (see the class docstring — this does not bite on the code replaced):
	# the level must never hand a roster back to the session.
	assert_same(GameSession.roster, roster,
			"the level CONSUMES the session's roster — replacing the object is the "
			+ "setup desync #549 describes, and on a client it would discard the "
			+ "host's roster")


func test_direct_launch_with_no_session_roster_falls_back_and_seeds_one() -> void:
	# Acceptance item 3: launching a level scene directly still works. Nothing
	# calls GameSession.start here — `ensure_started` in `_setup_level` opens the
	# session, and the roster is the level's own fallback.
	assert_null(GameSession.roster, "precondition: no lobby ran")

	var root := await _launch()

	assert_not_null(GameSession.roster,
			"the fallback branch — and ONLY that branch — seeds the session")
	assert_eq(GameSession.roster.all().size(), 2,
			"default camp_sizes [1, 1] — one local human, one AI")
	assert_eq(_spawned_entities(root).size(), 2)
	assert_not_null(root.player, "the fallback's camp 0 is the local human")
	assert_true(root.seat_policy.follows_active_turn(),
			"one local human and no other machine is a couch")
