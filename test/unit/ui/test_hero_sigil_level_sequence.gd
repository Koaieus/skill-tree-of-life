extends GutTest

## HeroSigilCard's XP replay (#317). The model applies a whole multi-level XP
## grant in one synchronous call; the card replays it as one gauge beat per
## level, and THAT is what paces the level badge and the LEVEL UP banner.
##
## This is the acceptance criterion most likely to rot silently, because none
## of it is visible in a single frame — it only exists as timing.

const _CARD_SCENE := preload("res://ui/hud/hero_sigil_card/hero_sigil_card.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _card: HeroSigilCard
var _entity: Entity
var _gauge: PoolGauge
var _levels: Array[int] = []


func before_each() -> void:
	_card = _CARD_SCENE.instantiate() as HeroSigilCard
	add_child_autofree(_card)
	await get_tree().process_frame

	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Leveller"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	add_child(_entity)
	await get_tree().process_frame  # _ready wires xp.replenished -> level-up

	_gauge = _card.get_node("%XPGauge") as PoolGauge
	# Fast timings: the ordering under test is preserved, the wall-clock isn't.
	_gauge.level_up_fill_time = 0.05
	_gauge.level_up_wrap_time = 0.02
	_gauge.level_up_hold_time = 0.02

	_levels = []
	_card.bind(_entity)
	_card.level_reached.connect(func(l: int): _levels.append(l))


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


func test_the_badge_follows_the_bar_not_the_model() -> void:
	var badge := _card.get_node("%LevelBadge") as Label
	assert_eq(badge.text, "1", "starts where bind() found it")
	_entity.stat_board.xp.replenish(20.0)
	# The model has already applied BOTH levels synchronously...
	assert_eq(_entity.level, 3, "model is instant")
	assert_eq(badge.text, "1", "...but the badge waits for the bar to say so")
	await _settle()
	assert_eq(badge.text, "3", "and catches up beat by beat")


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
	var chip := _card.get_node("%XPDeltaChip") as XpDeltaChip
	assert_almost_eq(chip.modulate.a, 0.0, 0.01, "resting invisible")
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	assert_eq(chip.text, "+3 XP")
	assert_gt(chip.modulate.a, 0.0, "and visible")


## Two sources in one turn (passive income + a kill reward) must read as one
## number, not flicker between them.
func test_a_second_grant_accumulates_into_a_live_chip() -> void:
	var chip := _card.get_node("%XPDeltaChip") as XpDeltaChip
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	_entity.stat_board.xp.replenish(2.0)
	await get_tree().process_frame
	assert_eq(chip.text, "+5 XP", "added into what's on screen")


## The chip is anchor-positioned, and anchors resolve on the layout pass that
## follows `_ready` — so its resting position must be captured lazily, or every
## pop would teleport it to the gauge's top-left corner and stay there.
func test_the_chip_pops_where_it_rests_not_at_the_origin() -> void:
	var chip := _card.get_node("%XPDeltaChip") as XpDeltaChip
	await get_tree().process_frame
	var laid_out := chip.position
	assert_ne(laid_out, Vector2.ZERO, "anchors resolved it away from the origin")
	_entity.stat_board.xp.replenish(3.0)
	await get_tree().process_frame
	assert_eq(chip.position.x, laid_out.x, "pops in place horizontally")
	assert_almost_eq(chip.position.y, laid_out.y, 2.0, "and starts its rise from there")


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
