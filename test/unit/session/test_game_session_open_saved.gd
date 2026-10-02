extends GutTest

## `GameSession.open_saved` — the third way a run opens: the save's config and
## roster as-is (no seed re-resolve), a world that ARRIVES, the image parked.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")


func before_each() -> void:
	GameSession.end()


func after_all() -> void:
	GameSession.end()


func _save() -> SaveFile:
	var cfg := RunConfig.new()
	cfg.seed = 98765
	var p := Participant.new()
	p.id = 3
	p.camp = _CAMP_1
	cfg.participants = [p] as Array[Participant]
	var save := SaveFile.new()
	save.config = cfg.to_dict()
	save.roster = ParticipantRoster.of(cfg.participants).to_dict()
	save.world = WorldImage.new(PackedByteArray([1]), PackedByteArray([2]))
	return save


func test_opens_the_saved_run_with_its_world_parked() -> void:
	var save := _save()
	assert_true(GameSession.open_saved(save))
	assert_true(GameSession.is_active())
	assert_eq(GameSession.config.seed, 98765, "the saved seed, never re-resolved")
	assert_eq(GameSession.roster.all().size(), 1)
	assert_eq(GameSession.roster.all()[0].id, 3)
	assert_eq(GameSession.world_source, GameSession.WorldSource.ARRIVES)
	assert_eq(GameSession.pending_world, save.world)


func test_a_refused_save_leaves_the_session_closed() -> void:
	var save := _save()
	save.load_result = SaveFile.LoadResult.CORRUPT
	assert_false(GameSession.open_saved(save))
	assert_false(GameSession.is_active())
	assert_null(GameSession.pending_world)


func test_every_other_entry_clears_a_parked_world() -> void:
	GameSession.open_saved(_save())
	GameSession.end()
	assert_null(GameSession.pending_world, "end")
	GameSession.open_saved(_save())
	GameSession.start(RunConfig.new())
	assert_null(GameSession.pending_world, "start")
	GameSession.open_saved(_save())
	var cfg := RunConfig.new()
	cfg.seed = 5
	GameSession.apply_received(cfg, null)
	assert_null(GameSession.pending_world, "apply_received")


## A sandbox's RunBootstrap must not replace a run open_saved opened.
func test_a_run_bootstrap_defers_to_a_loaded_run() -> void:
	GameSession.open_saved(_save())
	var boot := RunBootstrap.new()
	boot.run_setup = RunConfig.new()
	add_child_autofree(boot)
	assert_eq(GameSession.config.seed, 98765, "the bootstrap left the loaded run alone")
	assert_eq(GameSession.world_source, GameSession.WorldSource.ARRIVES)
