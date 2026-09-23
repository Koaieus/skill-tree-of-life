extends GutTest

## #39: the Pacifist gambit. Innate DP/MP are SET to 0; all mobility is bought
## with unspent AP converted to surplus at a steep ap_transfer_rate. Verifies
## the class statline AND that the zero-cap-plus-surplus state is coherent —
## the load-bearing #156 property (surplus lives outside the SET-short-circuit).
##
## #990: the mechanic tests below run on a HAND-BUILT board and a hand-built
## CoreClass of the same SHAPE as `pacifist_core.tres` (positive ADD_BASE
## grants on ap_transfer_rate/action_points/armor, SET 0 on movement/
## deallocation points) — never magnitudes read from the authored resource.
## `pacifist_core.tres` itself gets one shape-only test at the bottom.

const _PACIFIST := preload("res://entity/core/pacifist_core.tres")

## Test-chosen transfer rate — high enough that a small, easy-to-read AP
## surplus (3) produces a round number (12), same shape as the authored
## class's "double rate" identity without reading its actual rate.
const _RATE := 4.0

var _entity: Entity


func _build_pacifist_like_core() -> CoreClass:
	var rate_mod := StatModifier.new()
	rate_mod.stat_id = &"ap_transfer_rate"
	rate_mod.operation = StatModifier.Operation.ADD_BASE
	rate_mod.value = _RATE
	var ap_mod := StatModifier.new()
	ap_mod.stat_id = &"action_points"
	ap_mod.operation = StatModifier.Operation.ADD_BASE
	ap_mod.value = 3.0
	var armor_mod := StatModifier.new()
	armor_mod.stat_id = &"armor"
	armor_mod.operation = StatModifier.Operation.ADD_BASE
	armor_mod.value = 3.0
	var mp_zero := StatModifier.new()
	mp_zero.stat_id = &"movement_points"
	mp_zero.operation = StatModifier.Operation.SET
	mp_zero.value = 0.0
	mp_zero.priority = 100
	var dp_zero := StatModifier.new()
	dp_zero.stat_id = &"deallocation_points"
	dp_zero.operation = StatModifier.Operation.SET
	dp_zero.value = 0.0
	dp_zero.priority = 100

	var core := CoreClass.new()
	core.modifiers = [rate_mod, ap_mod, armor_mod, mp_zero, dp_zero]
	return core


func before_each() -> void:
	_entity = autofree(Entity.new())
	_entity.display_name = "Ascetic"
	_entity.stat_board = TestBoards.flat_entity_board()
	_entity.stat_board.ap_transfer_rate.base_value = 0.0
	_entity.core_class = _build_pacifist_like_core()
	add_child_autofree(_entity)  # _ready duplicates the board, then core_class.apply()s onto it
	await get_tree().process_frame


func test_statline() -> void:
	var b := _entity.stat_board
	assert_almost_eq(b.ap_transfer_rate.get_value(), _RATE, 0.001, "base 0 + class rate")
	assert_almost_eq(b.action_points.get_value(), b.action_points.base_value + 3.0, 0.001, "more AP to convert")
	assert_almost_eq(b.armor.get_value(), b.armor.base_value + 3.0, 0.001, "armor to survive non-attacking turns")


func test_innate_mobility_is_set_to_zero() -> void:
	var b := _entity.stat_board
	assert_eq(b.movement_points.get_value(), 0.0, "innate MP cap SET 0")
	assert_eq(b.deallocation_points.get_value(), 0.0, "innate DP cap SET 0")


func test_restraint_buys_mobility() -> void:
	var b := _entity.stat_board
	# End a turn with 3 AP unused (attacked once).
	b.action_points.set_current(3.0)
	_entity._on_turn_ended(_entity)
	# Cap is 0, but the surplus bin lives outside the SET-short-circuit, so the
	# available budget is entirely purchased: roundi(3 unused × rate 4) = 12.
	assert_eq(b.movement_points.available(), roundi(3.0 * _RATE), "mobility = unspent AP × rate, despite 0 cap")
	assert_eq(b.deallocation_points.available(), roundi(3.0 * _RATE), "reshape budget bought the same way")


func test_spending_all_ap_anchors_the_entity() -> void:
	var b := _entity.stat_board
	# Attacked out the whole AP bar — 0 unused.
	b.action_points.set_current(0.0)
	_entity._on_turn_ended(_entity)
	assert_eq(b.movement_points.available(), 0, "no restraint, no motion — anchored")
	assert_eq(b.deallocation_points.available(), 0, "and no reshape budget either")


# ── pacifist_core.tres shape (#990) ─────────────────────────────────────────

## No magnitudes: checks the authored `.tres` grants positive ADD_BASE on the
## transfer rate / AP / armor, and SETs innate MP/DP to exactly 0 — never a
## number that would red on a routine retune.
func test_pacifist_core_tres_shape() -> void:
	var by_stat: Dictionary = {}
	for m in _PACIFIST.modifiers:
		by_stat[(m as StatModifier).stat_id] = m as StatModifier

	for stat_id in [&"ap_transfer_rate", &"action_points", &"armor"]:
		var leaf: StatModifier = by_stat[stat_id]
		assert_eq(leaf.operation, StatModifier.Operation.ADD_BASE, "%s is a flat grant" % stat_id)
		assert_gt(leaf.value, 0.0, "%s adds, never subtracts" % stat_id)

	for stat_id in [&"movement_points", &"deallocation_points"]:
		var leaf: StatModifier = by_stat[stat_id]
		assert_eq(leaf.operation, StatModifier.Operation.SET, "%s is SET, not added to" % stat_id)
		assert_eq(leaf.value, 0.0, "…to exactly zero: no innate budget")
