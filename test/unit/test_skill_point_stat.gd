extends GutTest

## Four-bucket SP model: used + current + wounded + staked == max (identity).
## Transfers preserve max; only claim() / grant() mint.

const _DEF := preload("res://stats_system/defs/skill_points.tres")


func _fresh(current: int = 3) -> SkillPointStat:
	var sp := SkillPointStat.new()
	sp.definition = _DEF
	sp.current = float(current)
	return sp


func _max(sp: SkillPointStat) -> int:
	return int(sp.value)


func _assert_invariant(sp: SkillPointStat) -> void:
	var sum := sp.used + roundi(sp.current) + sp.wounded + sp.staked
	assert_eq(_max(sp), sum, "max must equal sum of buckets")


# --- initial state ----------------------------------------------------------

func test_fresh_pool_max_equals_current() -> void:
	var sp := _fresh(3)
	assert_eq(_max(sp), 3)
	assert_eq(sp.used, 0)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.staked, 0)


# --- transfers preserve max -------------------------------------------------

func test_spend_transfers_current_to_used() -> void:
	var sp := _fresh(3)
	assert_true(sp.spend(1))
	assert_eq(sp.current, 2.0)
	assert_eq(sp.used, 1)
	_assert_invariant(sp)
	assert_eq(_max(sp), 3)


func test_spend_refund_round_trip() -> void:
	var sp := _fresh(3)
	sp.spend(1)
	sp.refund(1)
	assert_eq(sp.current, 3.0)
	assert_eq(sp.used, 0)
	assert_eq(_max(sp), 3)


func test_spend_insufficient_fails() -> void:
	var sp := _fresh(0)
	assert_false(sp.spend(1))
	assert_eq(sp.current, 0.0)
	assert_eq(sp.used, 0)


func test_wound_heal_round_trip() -> void:
	var sp := _fresh(3)
	sp.spend(2)
	# (current=1, used=2, max=3)
	sp.wound(1)
	assert_eq(sp.used, 1)
	assert_eq(sp.wounded, 1)
	assert_eq(_max(sp), 3)
	sp.heal(1)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.current, 2.0)
	assert_eq(_max(sp), 3)


func test_stake_extract_round_trip() -> void:
	var sp := _fresh(3)
	assert_true(sp.stake(1))
	assert_eq(sp.staked, 1)
	assert_eq(sp.current, 2.0)
	assert_eq(_max(sp), 3)
	sp.extract(1)
	assert_eq(sp.staked, 0)
	assert_eq(sp.current, 3.0)
	assert_eq(_max(sp), 3)


# --- mints: claim + grant --------------------------------------------------

func test_claim_mints_into_used() -> void:
	var sp := _fresh(3)
	sp.claim(1)
	assert_eq(sp.used, 1)
	assert_eq(sp.current, 3.0)
	assert_eq(_max(sp), 4)  # max bumped by 1


func test_grant_mints_into_current() -> void:
	var sp := _fresh(3)
	sp.grant(1)
	assert_eq(sp.current, 4.0)
	assert_eq(_max(sp), 4)  # max bumped by 1


# --- the original bug: force-allocate N nodes, deallocate all, no leak -----

func test_force_allocate_then_full_dealloc_preserves_currency() -> void:
	var sp := _fresh(3)
	# Mimic spawning with 3 force-allocated nodes (procgen / scripted setup).
	sp.claim(1)
	sp.claim(1)
	sp.claim(1)
	assert_eq(_max(sp), 6)  # base 3 + 3 claimed
	assert_eq(sp.current, 3.0)
	assert_eq(sp.used, 3)
	# Voluntary dealloc all 3 → SP returns to current; max unchanged.
	sp.refund(1)
	sp.refund(1)
	sp.refund(1)
	assert_eq(sp.used, 0)
	assert_eq(sp.current, 6.0)
	assert_eq(_max(sp), 6)
	_assert_invariant(sp)


# --- the leak we'd hit if order were wrong ---------------------------------

func test_heal_at_zero_used_does_not_clamp_away_sp() -> void:
	# If wounded → current ran in the wrong order (drop wounded first, then
	# set_current), set_current would clamp to the lowered cap and silently
	# eat 1 SP. This guards the order discipline.
	var sp := _fresh(0)
	sp.wounded = 1  # synthetic: 1 SP exists in the wounded bucket
	assert_eq(_max(sp), 1)
	sp.heal(1)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.current, 1.0)
	assert_eq(_max(sp), 1)


# --- amount clamping --------------------------------------------------------

func test_wound_caps_at_used_balance() -> void:
	var sp := _fresh(3)
	sp.spend(1)
	sp.wound(5)  # more than `used` (1)
	assert_eq(sp.used, 0)
	assert_eq(sp.wounded, 1)


func test_heal_caps_at_wounded_balance() -> void:
	var sp := _fresh(3)
	sp.wounded = 2
	sp.heal(5)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.current, 5.0)


func test_refund_caps_at_used_balance() -> void:
	var sp := _fresh(3)
	sp.spend(1)
	sp.refund(5)
	assert_eq(sp.used, 0)
	assert_eq(sp.current, 3.0)
