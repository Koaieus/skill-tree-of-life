extends GutTest

## #271 — the progression economy: D-15 (xp_per_turn = WIS // 2, BalancedCore's
## 5-attribute grants) and D-16 (sp_gain_on_levelup, starting SP > 1), which
## collide on entity/default_entity_board.tres and so ship together.
##
## Fixtures are built via preload(...) + Entity.new() with stat_board/core_class
## assigned before add_child, matching test_level_up_bonuses.gd's established
## pattern for this exact domain (level, BalancedCore, xp).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _ENEMY_CORE := preload("res://entity/core/basic_enemy_core.tres")

const _LEVEL_SCALED := [&"strength", &"dexterity", &"intelligence", &"constitution"]
const _ALL_FIVE := [&"strength", &"dexterity", &"intelligence", &"constitution", &"wisdom"]


func _make_entity(core_class: CoreClass = null) -> Entity:
	var ent := Entity.new()
	autofree(ent)
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	ent.core_class = core_class
	add_child(ent)
	await get_tree().process_frame
	return ent


## Decision 1 (D-15): xp_per_turn intrinsic is WIS // 2, integer division —
## replacing the old floor(log10(WIS)) step function.
func test_xp_per_turn_is_wisdom_floor_div_2() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board

	board.wisdom.base_value = 20.0
	assert_eq(int(board.xp_per_turn.value), 10, "WIS 20 -> xp_per_turn 10")

	board.wisdom.base_value = 21.0
	assert_eq(int(board.xp_per_turn.value), 10, "WIS 21 still floors to 10 (integer division)")

	board.wisdom.base_value = 100.0
	assert_eq(int(board.xp_per_turn.value), 50, "WIS 100 -> xp_per_turn 50")


## Decision 3: BalancedCore grants +10 to all five attributes at base,
## including CON (default_value 0, so +10 base is what brings it to parity
## with the other four) and WIS.
func test_balanced_core_grants_plus_10_to_all_five_attributes_at_level_1() -> void:
	var ent: Entity = await _make_entity(_BALANCED)
	var board := ent.stat_board

	assert_eq(int(board.strength.value), int(board.strength.base_value) + 10)
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value) + 10)
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value) + 10)
	# CON's default_value is 0 (not 10 like the other four) — the +10 base
	# grant is what brings it to parity.
	assert_eq(int(board.constitution.value), 10, "CON: default 0 + BalancedCore's +10 base")
	assert_eq(int(board.wisdom.value), int(board.wisdom.base_value) + 10)


## Decision 4 / Amendment A: BalancedCore's per-level grant is +1 STR/DEX/INT
## only. WIS never scales with level (D-15's stall) and CON's level channel
## lives on the board intrinsic mod_level_to_con, NOT on BalancedCore — so this
## guards the *observable* outcome (STR/DEX/INT/CON all +4 across 1->5, WIS
## flat) without caring which channel delivered CON's share.
func test_leveling_1_to_5_raises_str_dex_int_con_but_not_wis() -> void:
	var ent: Entity = await _make_entity(_BALANCED)
	var board := ent.stat_board

	var at_1: Dictionary = {}
	for id in _ALL_FIVE:
		at_1[id] = int(board.get_stat(id).value)

	ent.level += 4  # 1 -> 5

	for id in _LEVEL_SCALED:
		assert_eq(int(board.get_stat(id).value), at_1[id] + 4, "%s +4 across levels 1->5" % id)
	assert_eq(int(board.wisdom.value), at_1[&"wisdom"], "WIS excluded from per-level grant (D-15 stall guard)")


## Decision 5: a level-up mints sp_gain_on_levelup SP (default 2), replacing
## the old hardcoded grant(1).
func test_level_up_mints_sp_gain_on_levelup_not_1() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board
	var max_before: float = board.skill_points.value
	var current_before: float = board.skill_points.current

	ent._on_xp_replenished()

	assert_eq(board.skill_points.value, max_before + 2.0, "max SP +2 (default sp_gain_on_levelup)")
	assert_eq(board.skill_points.current, current_before + 2.0, "current SP +2")


func test_level_up_mints_sp_gain_on_levelup_when_stat_is_raised() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board
	board.sp_gain_on_levelup.base_value = 3.0
	var max_before: float = board.skill_points.value

	ent._on_xp_replenished()

	assert_eq(board.skill_points.value, max_before + 3.0, "raising the stat to 3 mints 3")


## Decision 6: +1 extra SP on every 5th level, on top of sp_gain_on_levelup.
func test_milestone_level_mints_one_extra_sp() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board

	# Level 1 -> 2 -> 3 -> 4 -> 5: the 5th level-up (reaching level 5) is the
	# milestone and mints sp_gain_on_levelup + 1.
	for _i in range(3):
		ent._on_xp_replenished()
	var max_before_milestone: float = board.skill_points.value
	ent._on_xp_replenished()  # reaches level 5
	assert_eq(int(board.level.value), 5, "sanity: entity is now level 5")
	assert_eq(board.skill_points.value, max_before_milestone + 3.0, "level 5 mints sp_gain_on_levelup(2) + 1")

	var max_before_6: float = board.skill_points.value
	ent._on_xp_replenished()  # reaches level 6
	assert_eq(int(board.level.value), 6, "sanity: entity is now level 6")
	assert_eq(board.skill_points.value, max_before_6 + 2.0, "level 6 mints plain sp_gain_on_levelup, no milestone")


## #320 item 7: the milestone rule lives in ONE place, and it is a pure
## function of the level being asked about — not of the entity's current level.
## The HUD narrates a multi-level cascade one beat at a time, seconds after the
## model applied every level, so asking "how much did level 5 mint" while the
## entity already sits at level 6 has to answer for 5.
func test_sp_minted_for_level_answers_for_the_level_asked_not_the_current_one() -> void:
	var ent: Entity = await _make_entity()
	for _i in range(5):
		ent._on_xp_replenished()
	assert_eq(int(ent.level), 6, "sanity: entity is now level 6")
	var plain: int = ent.sp_minted_for_level(6)
	assert_eq(ent.sp_minted_for_level(5), plain + 1, "level 5 is a milestone even when asked from level 6")
	assert_eq(ent.sp_minted_for_level(10), plain + 1, "level 10 is a milestone even before it is reached")
	assert_eq(ent.sp_minted_for_level(4), plain, "level 4 mints the plain per-level yield")


## Decision 7 / D-16: starting SP is raised above the old default of 1.
func test_starting_sp_is_above_1() -> void:
	var ent: Entity = await _make_entity()
	assert_gt(ent.stat_board.skill_points.value, 1.0, "starting SP > 1 (D-16; placeholder 3, TBD #268)")


## Amendment B: basic_enemy_core.tres used to grant an explicit xp_per_turn
## SET alongside its WIS grant, which was only correct while the intrinsic was
## floor(log10(WIS)) = 1. Now that the intrinsic itself is WIS // 2, an
## explicit grant would double-count it — it's been removed, and the granted
## WIS alone must derive xp_per_turn through the ordinary intrinsic. basic_enemy_core's
## WIS grant is a TBD (#268) difficulty dial that gets retuned, so assert the
## relationship, not a specific number.
func test_basic_enemy_core_xp_per_turn_derives_from_wisdom_not_double_counted() -> void:
	var ent: Entity = await _make_entity(_ENEMY_CORE)
	@warning_ignore("integer_division")
	assert_eq(int(ent.stat_board.xp_per_turn.value), int(ent.stat_board.wisdom.value) / 2,
			"BasicEnemyCore: xp_per_turn must derive from WIS // 2, not double-counted")
