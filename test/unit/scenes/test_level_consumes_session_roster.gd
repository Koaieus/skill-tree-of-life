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
const _BARE_LEVEL := preload("res://scenes/level.tscn")
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


## [param scene] so the bare level can be launched too — its whole contract is
## what it does with NO run, which the sandbox (a [RunBootstrap] on top of that
## same scene) cannot express.
##
## #584 deleted the `n_random_starters` pin this used to carry. It existed to
## hold the starter count below every roster these tests build, so a level that
## ignored the roster could not pass by luck. That guard is now structural
## rather than a pin: the export is gone and `_setup_level` derives the count
## from `roster.all()` on the only surviving path, so there is no knob left for
## a level to read instead.
func _launch(scene: PackedScene = _SANDBOX, node_count: int = 40) -> GameRoot:
	var root: GameRoot = scene.instantiate()
	root.auto_start_turn = false
	root.node_count_override = node_count
	root.enemy_territory_size = 1
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
	var mine := _participant(1, Participant.Kind.HUMAN, _CAMP_1, 5)
	mine.display_name = "Bramh"
	roster.add(mine)
	roster.add(_participant(2, Participant.Kind.HUMAN, _CAMP_2, 9))
	roster.add(_participant(3, Participant.Kind.AI, _CAMP_3))
	roster.add(_participant(4, Participant.Kind.AI, _CAMP_2))
	GameSession.start(RunConfig.new())
	GameSession.roster = roster
	GameSession.local_peer_id = 5

	var root := await _launch()

	# PIN: `first_level.tres` authors ONE starting point, so a level that read
	# anything other than the roster yields one starter, not four. A short list
	# trims the spawn (with a warning) rather than failing loudly, which is why
	# entity count is the assertion.
	#
	# Launched through the SANDBOX scene on purpose, though this is the lobby's
	# path: its [RunBootstrap] child must defer to the run already open rather
	# than replacing it. That is the pause menu's `reload_current_scene` in
	# miniature — re-starting there would reroll the seed and swap the map out
	# from under a player who asked to retry. `assert_same` below is what bites.
	var spawned := _spawned_entities(root)
	assert_eq(spawned.size(), 4,
			"four contenders must get four starting points — the roster decides the "
			+ "camp count, procgen no longer decides how many opponents exist")

	# PIN: the camps come from the roster, not from the scene. The sandbox's
	# authored run names camp_1..camp_6 against six AI, so a THREE-camp spread
	# across four contenders is reachable only from this test's own roster.
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

	# PIN (#741): the lobby-typed name is run shape like camp — it rides the
	# roster to the spawned entity, so the HUD shows what the slot typed.
	assert_eq(root.player.display_name, "Bramh",
			"the roster's name is what the HUD will show")

	# GUARD (see the class docstring — this does not bite on the code replaced):
	# the level must never hand a roster back to the session.
	# Bites twice since #584: it still guards against a level rebuilding the
	# roster, and now also against the RunBootstrap child clobbering a live run.
	assert_same(GameSession.roster, roster,
			"the level CONSUMES the session's roster — replacing the object is the "
			+ "setup desync #549 describes, and on a client it would discard the "
			+ "host's roster")


## #584: the sandbox scene starts its OWN run from an authored `RunConfig`,
## and the level below it cannot tell that apart from a lobby-composed one.
##
## This replaces `..._falls_back_and_seeds_one`. What it inherits: a direct
## launch still yields a populated map, a local human, and a couch seat. What it
## gains is the acceptance item the fallback could never meet — the fallback
## owned two Factions, so every AI past the first collapsed into one allied NPC
## camp. An authored roster names its camps, so they are genuine rivals.
func test_direct_launch_starts_the_scenes_own_authored_run() -> void:
	assert_null(GameSession.roster, "precondition: no lobby ran")
	assert_false(GameSession.is_active(), "precondition: no session either")

	var root := await _launch(_SANDBOX, 300)

	assert_true(GameSession.is_active(),
			"the RunBootstrap child opened the run — the level no longer can")
	var participants := GameSession.roster.all()
	assert_eq(participants.size(), 7,
			"`session/runs/first_level_run.tres` authors one human and six AI")
	assert_eq(_spawned_entities(root).size(), 7)
	assert_not_null(root.player, "the authored run's human is this machine's")
	assert_true(root.seat_policy.follows_active_turn(),
			"one local human and no other machine is a couch")

	# The acceptance item, and the reason the fallback had to go.
	var ai_camps := {}
	for p in participants:
		if p.kind == Participant.Kind.AI:
			ai_camps[p.camp.id] = true
	assert_gt(ai_camps.size(), 1,
			"the AI must be RIVALS — the deleted fallback put every one of them "
			+ "on the shared npc faction, i.e. one allied blob")


## #584 decision 3: the shipped level cannot invent a run, and that inability is
## the whole point of the split. `scenes/level.tscn` is `_SANDBOX` minus the
## [RunBootstrap] child, so this is the one behaviour the two scenes differ on.
##
## Both halves of "fails loudly instead of inventing one" are asserted, because
## either alone is satisfiable by a bug: an empty `entities_container` is also
## what a level that crashed silently leaves behind, and a `push_error` is also
## what a level that complained and then generated anyway emits.
func test_the_bare_level_refuses_to_generate_without_a_run() -> void:
	assert_false(GameSession.is_active(), "precondition: no lobby ran")

	var root: GameRoot = _BARE_LEVEL.instantiate()
	root.auto_start_turn = false
	root.node_count_override = 40
	add_child(root)
	_root = root
	for _f in 30:
		await wait_physics_frames(1)

	assert_push_error_count(1,
			"it must fail LOUDLY — a silent empty level is the same symptom as a crash")
	assert_true(_spawned_entities(root).is_empty(),
			"the shipped level invented a run — the fallback is back")
	assert_null(root.player, "and seated somebody in it")
	assert_false(GameSession.is_active(),
			"a level must never open a session; `GameSession.start` is a composer's call")
