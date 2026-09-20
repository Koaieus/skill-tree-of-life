extends GutTest

## A joining CLIENT level waiting for the authority's world (2026-09-06, from a
## LAN playtest that ended on a black loading screen at 0%).
##
## `GameRoot._ready` used to `await command_link.resync_applied` bare, with
## [SceneDirector]'s 30s reveal timeout as the only way out — and a link that
## ended meanwhile presented its overlay UNDER the curtain. This pins the wait's
## three exits: the world lands, the link is lost, the host refuses us — and
## that while it waits, the pull is asked again rather than trusted once.
##
## The level's mounted default is a [LoopbackTransport] linked to nobody, which
## is exactly a joiner whose ask reaches no one.
##
## Every wait here is clocked on PROCESS frames, never `wait_frames` (GUT's
## alias for `wait_physics_frames`): `_ready` reaches the wait loop only after
## awaiting `_setup_level` and a `process_frame`, and the loop itself polls
## `process_frame`. A loaded suite run catches physics up with several physics
## steps per process frame, so counting physics frames returned before the
## fixture was in its wait — green alone, red once in the full run (2026-09-20).

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _REMOTE_PEER := 2

var _root: GameRoot
## Renewals only — the first pull is the fixture-ready signal, not an ask.
var _asks: Array[String] = []
var _first_pull_seen := false


func before_each() -> void:
	GameSession.end()
	GameSession.network = NetworkConfig.join("127.0.0.1", 0)
	GameSession.local_peer_id = _REMOTE_PEER
	_asks = []
	_first_pull_seen = false
	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	_root.route_to_meta_on_run_end = false
	# Fast enough to watch, slow enough that a frame is not a renewal.
	# Before the root enters the tree: its `_ready` reads the session's clock.
	(_root.get_node("%NetworkSession") as NetworkSession).join_pull_retry_sec = 0.05
	add_child_autofree(_root)
	# `_ready` issues its first pull (`pull_host_world`) and enters
	# `_await_join_world` in the same synchronous run, so the pull's log line IS
	# the fixture-ready signal. It is not counted: `_asks` holds renewals only.
	_root.command_link.logged.connect(_on_logged)
	var pulled: bool = await wait_until(func() -> bool: return _first_pull_seen, 5.0)
	assert_true(pulled, "fixture: the level asked for the host's world and is waiting")


func after_each() -> void:
	GameSession.end()


func _on_logged(line: String) -> void:
	if not line.contains("resync requested"):
		return
	if not _first_pull_seen:
		_first_pull_seen = true
		return
	_asks.append(line)


func test_the_fixture_is_a_mirror_still_waiting_for_its_world() -> void:
	assert_eq(_root.command_link.mode, CommandLink.Mode.MIRROR)
	assert_false(_root.is_reveal_ready(), "no world, no reveal")


func test_a_joiner_with_no_world_asks_for_it_again() -> void:
	var renewed: bool = await wait_until(func() -> bool: return _asks.size() >= 2, 5.0)
	assert_true(renewed, "the pull was renewed while nothing answered: %s" % [_asks])
	assert_false(_root.is_reveal_ready(), "and it is still waiting, not giving up")


func test_a_link_lost_while_waiting_ends_the_wait_and_lifts_the_curtain() -> void:
	var overlay := _root.hud_root.run_end_overlay
	assert_false(overlay.visible, "precondition")

	_root.transport.link_lost.emit("the host went away")
	await wait_process_frames(3)

	assert_true(_root.is_reveal_ready(), "the level stops waiting for a world that is not coming")
	assert_true(overlay.visible)
	assert_eq(overlay.reading, RunEndOverlay.Reading.LINK_LOST)
	assert_string_contains(overlay.subtitle_label.text, "the host went away")
	# And the asking stops with it.
	var asked := _asks.size()
	await wait_seconds(0.2)
	assert_eq(_asks.size(), asked, "no more pulls after the link ended")


func test_a_refusal_keeps_its_reason_over_the_hang_up_that_follows() -> void:
	var overlay := _root.hud_root.run_end_overlay

	_root.command_link.link_refused.emit("refused by peer — the run has already started")
	_root.transport.link_lost.emit("the host went away")
	await wait_process_frames(3)

	assert_true(_root.is_reveal_ready())
	assert_true(overlay.visible)
	assert_string_contains(overlay.subtitle_label.text, "already started")
	assert_false(overlay.subtitle_label.text.contains("went away"),
			"the generic hang-up did not paint over the reason")


func test_the_world_arriving_ends_the_wait_and_reveals() -> void:
	_root.command_link.resync_applied.emit("join: adopting the host's world")
	await wait_process_frames(3)

	assert_true(_root.is_reveal_ready(), "a world landed, the level is presentable")
	assert_false(_root.hud_root.run_end_overlay.visible)
