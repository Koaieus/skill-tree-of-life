extends GutTest

## XpTrack's XP replay (#317, relocated in #320). The model applies a whole
## multi-level XP grant in one synchronous call; the track replays it as one
## gauge beat per level, and THAT is what paces the level readout, the Hero
## Sigil's badge and the LEVEL UP banner.
##
## [b]No clock in here (#981).[/b] "Which segment fills at which XP value" is
## [method PoolLevelSequencer.pending] after the grant — a table, the same one
## the track pops from. "The readout follows the bar" and "the badge rides the
## same beat" are asserted at the gauge's own [signal PoolGauge.level_segment_held],
## emitted from the test rather than awaited off its tween. Whether the track
## then chains every segment through the gauge on the real clock, and where the
## bar settles, is `test/integration/ui/test_xp_track_real_clock.gd`.
##
## Never `await` after a grant in a test that then beats by hand: the track's
## deferred replay would start the real tween behind those beats and fire the
## same signal a second time.

const _TRACK_SCENE := preload("res://ui/hud/xp_track/xp_track.tscn")
const _CARD_SCENE := preload("res://ui/hud/hero_sigil_card/hero_sigil_card.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _track: XpTrack
var _entity: Entity
var _gauge: PoolGauge
var _levels: Array[int] = []
## The test's own read of the schedule, recorded off the pool exactly as the
## track records its (`value_changed`, ascending).
var _seq: PoolLevelSequencer


func before_each() -> void:
	_track = _TRACK_SCENE.instantiate() as XpTrack
	# A real width, so the anchored chip has somewhere to resolve to.
	_track.custom_minimum_size = Vector2(800, 52)
	add_child_autofree(_track)
	await get_tree().process_frame

	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Leveller"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(_entity)
	await get_tree().process_frame  # _ready wires xp.replenished -> level-up

	_gauge = _track.get_node("%XPGauge") as PoolGauge
	var xp: PoolStat = _entity.stat_board.xp
	_seq = PoolLevelSequencer.new(float(xp.value))
	xp.value_changed.connect(func(): _seq.observe(float(xp.current), float(xp.value)))

	_levels = []
	_track.bind(_entity)
	_track.level_reached.connect(func(l: int): _levels.append(l))


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.get_parent().remove_child(_entity)


func _fill_tos() -> Array:
	return _seq.pending().map(func(s): return s.fill_to)


func _new_maxes() -> Array:
	return _seq.pending().map(func(s): return s.new_max)


## One beat at the full bar, at the gauge's own seam.
func _beat(new_max: float) -> void:
	_gauge.level_segment_held.emit(new_max)


## Beat every segment the schedule holds, in order.
func _beat_all() -> void:
	for segment in _seq.pending():
		_beat(segment.new_max)


func test_one_level_reaches_once_and_carries_the_overflow() -> void:
	_entity.stat_board.xp.replenish(7.0)
	assert_eq(_fill_tos(), [5.0], "one segment: fill to the cap reached")
	assert_eq(_new_maxes(), [10.0], "then adopt the grown cap")
	_beat_all()
	assert_eq(_levels, [2] as Array[int], "one beat, one level")
	assert_almost_eq(float(_entity.stat_board.xp.current), 2.0, 0.01,
			"the settle target is the carried overflow (sanity)")


## The bug #317 names: `_xp_leveled` was a bare bool, so a 2-level cascade
## played exactly one fill→wrap→fill.
func test_a_two_level_cascade_plays_one_beat_per_level_in_order() -> void:
	_entity.stat_board.xp.replenish(20.0)
	assert_eq(_fill_tos(), [5.0, 10.0], "ascending, one segment per level crossed")
	assert_eq(_new_maxes(), [10.0, 15.0], "each on its own new cap")
	_beat_all()
	assert_eq(_levels, [2, 3] as Array[int], "ascending, one per level crossed")
	assert_eq(_entity.level, 3, "and the model agrees (sanity)")


func test_the_level_readout_follows_the_bar_not_the_model() -> void:
	var label := _track.get_node("%LevelLabel") as Label
	assert_eq(label.text, "LEVEL 1", "starts where bind() found it")
	_entity.stat_board.xp.replenish(20.0)
	# The model has already applied BOTH levels synchronously...
	assert_eq(_entity.level, 3, "model is instant")
	assert_eq(label.text, "LEVEL 1", "...but the readout waits for the bar to say so")
	_beat(10.0)
	assert_eq(label.text, "LEVEL 2", "and catches up beat by beat")
	_beat(15.0)
	assert_eq(label.text, "LEVEL 3")


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
	_beat(10.0)
	assert_eq(badge.text, "2", "bumped by the gauge's beat")
	_beat(15.0)
	assert_eq(badge.text, "3", "beat by beat")


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
	assert_false(_seq.has_pending(), "no cap crossed, so nothing to narrate")
	# The deferred hop into the settle phase, then the settle's own end signal
	# at the gauge's seam — the re-sync edge.
	await get_tree().process_frame
	_gauge.fill_finished.emit()

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
	_beat(10.0)  # mid-cascade: the first level landed, the second is queued
	_entity.stat_board.xp.replenish(2.0)
	assert_eq(_fill_tos(), [5.0, 10.0], "the late grant crossed no extra level")
	_beat(15.0)
	assert_eq(_levels, [2, 3] as Array[int], "one beat per level, still")
	assert_almost_eq(float(_entity.stat_board.xp.current), 7.0, 0.01,
			"the settle target reads the pool's LIVE value, including the interrupt")


func test_a_late_grant_that_levels_gets_its_own_beat() -> void:
	_entity.stat_board.xp.replenish(7.0)
	# 30 more from 2/10 crosses two further caps (10 and 15), so the replay
	# queue must grow behind the segment already recorded.
	_entity.stat_board.xp.replenish(30.0)
	assert_eq(_fill_tos(), [5.0, 10.0, 15.0], "appended, ascending")
	_beat_all()
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
	assert_false(_seq.has_pending(), "and announces nothing")
	assert_eq(_levels, [] as Array[int])
