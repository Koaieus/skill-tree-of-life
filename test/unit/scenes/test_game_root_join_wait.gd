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

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _REMOTE_PEER := 2

var _root: GameRoot
var _asks: Array[String] = []


func before_each() -> void:
	GameSession.end()
	GameSession.network = NetworkConfig.join("127.0.0.1", 0)
	GameSession.local_peer_id = _REMOTE_PEER
	_asks = []
	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	_root.route_to_meta_on_run_end = false
	# Fast enough to watch, slow enough that a frame is not a renewal.
	_root.join_pull_retry_sec = 0.05
	add_child_autofree(_root)
	await wait_frames(6)
	_root.command_link.logged.connect(_on_logged)


func after_each() -> void:
	GameSession.end()


func _on_logged(line: String) -> void:
	if line.contains("resync requested"):
		_asks.append(line)


func test_the_fixture_is_a_mirror_still_waiting_for_its_world() -> void:
	assert_eq(_root.command_link.mode, CommandLink.Mode.MIRROR)
	assert_false(_root.is_reveal_ready(), "no world, no reveal")


func test_a_joiner_with_no_world_asks_for_it_again() -> void:
	await wait_seconds(0.3)
	assert_gte(_asks.size(), 2, "the pull was renewed while nothing answered: %s" % [_asks])
	assert_false(_root.is_reveal_ready(), "and it is still waiting, not giving up")


func test_a_link_lost_while_waiting_ends_the_wait_and_lifts_the_curtain() -> void:
	var overlay := _root.hud_root.run_end_overlay
	assert_false(overlay.visible, "precondition")

	_root.transport.link_lost.emit("the host went away")
	await wait_frames(3)

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
	await wait_frames(3)

	assert_true(_root.is_reveal_ready())
	assert_true(overlay.visible)
	assert_string_contains(overlay.subtitle_label.text, "already started")
	assert_false(overlay.subtitle_label.text.contains("went away"),
			"the generic hang-up did not paint over the reason")


func test_the_world_arriving_ends_the_wait_and_reveals() -> void:
	_root.command_link.resync_applied.emit("join: adopting the host's world")
	await wait_frames(3)

	assert_true(_root.is_reveal_ready(), "a world landed, the level is presentable")
	assert_false(_root.hud_root.run_end_overlay.visible)
