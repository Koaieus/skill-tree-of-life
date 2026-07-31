extends GutTest

## XpTrack's XP replay (#317, relocated in #320). The model applies a whole
## multi-level XP grant in one synchronous call; the track replays it as one
## gauge beat per level, and THAT is what paces the level readout, the Hero
## Sigil's badge and the LEVEL UP banner.
##
## This is the acceptance criterion most likely to rot silently, because none
## of it is visible in a single frame — it only exists as timing.

const _TRACK_SCENE := preload("res://ui/hud/xp_track/xp_track.tscn")
const _CARD_SCENE := preload("res://ui/hud/hero_sigil_card/hero_sigil_card.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _track: XpTrack
var _entity: Entity
var _gauge: PoolGauge
var _levels: Array[int] = []


func before_each() -> void:
	_track = _TRACK_SCENE.instantiate() as XpTrack
	# A real width, so the anchored chip has somewhere to resolve to.
	_track.custom_minimum_size = Vector2(800, 52)
	add_child_autofree(_track)
	await get_tree().process_frame

	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Leveller"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	add_child(_entity)
	await get_tree().process_frame  # _ready wires xp.replenished -> level-up

	_gauge = _track.get_node("%XPGauge") as PoolGauge
	# Fast timings: the ordering under test is preserved, the wall-clock isn't.
	_gauge.level_up_fill_time = 0.05
	_gauge.level_up_wrap_time = 0.02
	_gauge.level_up_hold_time = 0.02

	_levels = []
	_track.bind(_entity)
	_track.level_reached.connect(func(l: int): _levels.append(l))


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.get_parent().remove_child(_entity)


## Runs the replay to completion. Generous: each level is fill+hold+wrap plus a
## deferred hop between beats.
func _settle() -> void:
	for i in 60:
		await get_tree().process_frame
		await wait_seconds(0.01)


func test_one_level_reaches_once_and_settles_on_the_pool() -> void:
	_entity.stat_board.xp.replenish(7.0)
	await _settle()
	assert_eq(_levels, [2] as Array[int], "one beat, one level")
	assert_almost_eq(_gauge.max_value, 10.0, 0.01, "settled on the grown cap")
	assert_almost_eq(_gauge.current, 2.0, 0.05, "settled on the carried overflow")


## The bug #317 names: `_xp_leveled` was a bare bool, so a 2-level cascade
## played exactly one fill→wrap→fill.
func test_a_two_level_cascade_plays_one_beat_per_level_in_order() -> void:
	_entity.stat_board.xp.replenish(20.0)
	await _settle()
	assert_eq(_levels, [2, 3] as Array[int], "ascending, one per level crossed")
	assert_eq(_entity.level, 3, "and the model agrees (sanity)")
	assert_almost_eq(_gauge.max_value, 15.0, 0.01, "settled on the final cap")


func test_the_level_readout_follows_the_bar_not_the_model() -> void:
	var label := _track.get_node("%LevelLabel") as Label
	assert_eq(label.text, "LEVEL 1", "starts where bind() found it")
	_entity.stat_board.xp.replenish(20.0)
	# The model has already applied BOTH levels synchronously...
	assert_eq(_entity.level, 3, "model is instant")
	assert_eq(label.text, "LEVEL 1", "...but the readout waits for the bar to say so")
	await _settle()
	assert_eq(label.text, "LEVEL 3", "and catches up beat by beat")


## The Hero Sigil's badge is driven from here by HudRoot (#320), so badge,
## banner and bar all beat together instead of the badge racing the model.
func test_the_hero_sigil_badge_rides_the_same_beat() -> void:
	var card := _CARD_SCENE.instantiate() as HeroSigilCard
	add_child_autofree(card)
	await get_tree().process_frame
	card.bind(_entity)
	_track.level_reached.connect(card.show_level)
	var badge := card.get_node("%LevelBadge") as Label
	assert_eq(badge.text, "1", "starts where bind() found it")

	_entity.stat_board.xp.replenish(20.0)
	assert_eq(badge.text, "1", "not yanked forward by the model's instant level-up")
	await _settle()
	assert_eq(badge.text, "3", "bumped by the gauge's beats")


## A level that never crosses an XP cap produces no beat — `level` is an ordinary
## moddable stat and a `+level` modifier is legal (.claude/rules/stats-system.md).
## The track's settle-time re-sync catches it; the badge must ride the same edge,
## or it sits permanently one behind a readout that corrected itself.
func test_a_level_granted_outside_the_xp_pool_still_reaches_both_readouts() -> void:
	var card := _CARD_SCENE.instantiate() as HeroSigilCard
	add_child_autofree(card)
	await get_tree().process_frame
	card.bind(_entity)
	_track.level_display_changed.connect(card.show_level)
	var badge := card.get_node("%LevelBadge") as Label
	var label := _track.get_node("%LevelLabel") as Label

	_entity.stat_board.level.base_value += 1  # no XP, no cap crossed, no beat
	_entity.stat_board.xp.replenish(1.0)      # a plain gain, to force a settle
	await _settle()

	assert_eq(_levels, [] as Array[int], "no cap crossed, so nothing to narrate")
	assert_eq(label.text, "LEVEL 2", "the track re-syncs on settle")
	assert_eq(badge.text, "2", "and the badge rides the same edge, not the beat")


## The card must NOT bind XP itself any more (#320) — a second binder on the
## same pool runs a second sequencer and emits a second `level_reached`, which
## AnnouncementLayer's coalescing absorbs into one banner stamped "×2" for a
## single level.
func test_the_hero_sigil_card_no_longer_binds_the_xp_pool() -> void:
	var card := _CARD_SCENE.instantiate() as HeroSigilCard
	add_child_autofree(card)
	await get_tree().process_frame
	var xp: PoolStat = _entity.stat_board.xp
	var before := xp.replenished_by.get_connections().size()
	card.bind(_entity)
	assert_eq(xp.replenished_by.get_connections().size(), before,
			"binding the card must not add a listener to the XP pool")


## The retarget-on-interrupt requirement: passive per-turn XP is the main
## income source and routinely lands while a kill's replay is still playing.
func test_xp_landing_mid_replay_is_not_swallowed() -> void:
	_entity.stat_board.xp.replenish(20.0)
	await get_tree().process_frame
	await wait_seconds(0.03)  # mid-cascade, first segment still filling
	_entity.stat_board.xp.replenish(2.0)
	await _settle()
	assert_eq(_levels, [2, 3] as Array[int], "the late grant crossed no extra level")
	assert_almost_eq(_gauge.current, float(_entity.stat_board.xp.current), 0.05,
			"the bar settles on the pool's LIVE value, including the interrupt")


func test_a_late_grant_that_levels_gets_its_own_beat() -> void:
	_entity.stat_board.xp.replenish(7.0)
	await get_tree().process_frame
	# 30 more from 2/10 crosses two further caps (10 and 15), so the replay
	# queue must grow while its first segment is already playing.
	_entity.stat_board.xp.replenish(30.0)
	await _settle()
	assert_eq(_levels, [2, 3, 4] as Array[int], "appended, still one beat per level")


## The chip replaces the player's XP floater toast entirely (#317), so it is
## the ONLY "+N XP" the player ever sees — see test_xp_toast.gd for the
## matching absence assertion.
func test_the_chip_announces_the_grant() -> void:
	var chip := _track.get_node("%XPDeltaChip") as XpDeltaChip
	assert_almost_eq(chip.modulate.a, 0.0, 0.01, "resting invisible")
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	assert_eq(chip.text, "+3 XP")
	assert_gt(chip.modulate.a, 0.0, "and visible")


## Two sources in one turn (passive income + a kill reward) must read as one
## number, not flicker between them.
func test_a_second_grant_accumulates_into_a_live_chip() -> void:
	var chip := _track.get_node("%XPDeltaChip") as XpDeltaChip
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	_entity.stat_board.xp.replenish(2.0)
	await get_tree().process_frame
	assert_eq(chip.text, "+5 XP", "added into what's on screen")


## The chip is anchor-positioned, and anchors resolve on the layout pass that
## follows `_ready` — so its resting position must be captured lazily, or every
## pop would teleport it to the wrap's top-left corner and stay there.
func test_the_chip_pops_where_it_rests_not_at_the_origin() -> void:
	var chip := _track.get_node("%XPDeltaChip") as XpDeltaChip
	await get_tree().process_frame
	var laid_out := chip.position
	assert_ne(laid_out, Vector2.ZERO, "anchors resolved it away from the origin")
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	assert_eq(chip.position.x, laid_out.x, "pops in place horizontally")
	assert_almost_eq(chip.position.y, laid_out.y, 2.0, "and starts its rise from there")


## Where the chip rises MATTERS: its first home (#317) put it inside the 110px
## gauge on the card, so it rose in gold-on-gold across the mana row and read as
## nothing at all. On the track it must clear the bar entirely.
func test_the_chip_rises_clear_of_the_gauge() -> void:
	var chip := _track.get_node("%XPDeltaChip") as XpDeltaChip
	await get_tree().process_frame
	assert_lt(chip.get_global_rect().end.y, _gauge.get_global_rect().position.y + 1.0,
			"the chip sits above the bar, not on top of it")


## A gain that crosses nothing must still move the bar — it used to hard-cut,
## now it tweens, and either way it must not be lost.
func test_a_plain_gain_animates_to_the_new_value() -> void:
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(_gauge.current, 3.0, "tweening, not snapped")
	await _settle()
	assert_almost_eq(_gauge.current, 3.0, 0.05, "arrives")
	assert_eq(_levels, [] as Array[int], "and announces nothing")
