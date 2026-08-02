extends GutTest

## SP buckets: max canonical (PoolStat), wounded + staked stored, used derived.
## Identity: `used == max - current - wounded - staked` at all times.
## Transfers preserve max; only claim() and grant() mint.

const _DEF := preload("res://stats_system/defs/skill_points.tres")


## Pool at `current/current` — base_value matches so an unallocated fresh entity
## has used == 0.
func _fresh(current: int = 3) -> SkillPointStat:
	var sp := SkillPointStat.new()
	sp.definition = _DEF
	sp.base_value = float(current)
	sp.current = float(current)
	return sp


func _max(sp: SkillPointStat) -> int:
	return int(sp.value)


func _assert_invariant(sp: SkillPointStat) -> void:
	var derived := _max(sp) - roundi(sp.current) - sp.wounded - sp.staked
	assert_eq(sp.used, derived, "used getter must match the derivation")
	assert_gte(sp.used, 0, "used must never go negative")


# --- initial state ----------------------------------------------------------

func test_fresh_pool_max_equals_current() -> void:
	var sp := _fresh(3)
	assert_eq(_max(sp), 3)
	assert_eq(sp.used, 0)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.staked, 0)
	_assert_invariant(sp)


# --- transfers preserve max -------------------------------------------------

func test_spend_transfers_current_to_used() -> void:
	var sp := _fresh(3)
	assert_true(sp.spend(1))
	assert_eq(sp.current, 2.0)
	assert_eq(sp.used, 1)
	assert_eq(_max(sp), 3)
	_assert_invariant(sp)


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
	_assert_invariant(sp)
	sp.heal(1)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.current, 2.0)
	assert_eq(_max(sp), 3)
	_assert_invariant(sp)


func test_stake_extract_round_trip() -> void:
	var sp := _fresh(3)
	assert_true(sp.stake(1))
	assert_eq(sp.staked, 1)
	assert_eq(sp.current, 2.0)
	assert_eq(_max(sp), 3)
	_assert_invariant(sp)
	sp.extract(1)
	assert_eq(sp.staked, 0)
	assert_eq(sp.current, 3.0)
	assert_eq(_max(sp), 3)


# --- mints: claim + grant --------------------------------------------------

func test_claim_mints_max_only() -> void:
	var sp := _fresh(3)
	sp.claim(1)
	assert_eq(sp.used, 1, "the new SP lands in used (derived)")
	assert_eq(sp.current, 3.0, "current unchanged — that's what makes claim distinct from grant")
	assert_eq(_max(sp), 4)
	_assert_invariant(sp)


func test_claim_bypasses_the_ratchet_that_its_own_def_opts_into() -> void:
	# The near-miss behind D-31: `claim` is distinct from `grant` ONLY because a
	# raw `base_value` write skips the cap-change path. Its def opts INTO
	# heal_on_max_increase, so routing claim through the modifier pipeline (or
	# through PoolStat.set_base_ratcheted) would silently mint a spendable SP on
	# every allocation. This asserts the flag is genuinely on, so the test above
	# can't pass for the wrong reason.
	var def := _DEF as StandardPoolStatDef
	assert_true(def.heal_on_max_increase,
		"skill_points opts into the ratchet — claim's bypass is what makes it a mint-max-only")

	var sp := _fresh(3)
	sp.claim(1)
	assert_eq(sp.current, 3.0, "raw base_value write must not trigger on_max_increased")

	# ...and the ratcheted door on the very same pool does the opposite.
	sp.set_base_ratcheted(sp.base_value + 1.0)
	assert_eq(sp.current, 4.0, "set_base_ratcheted grants the delta, unlike claim")


func test_grant_mints_max_and_current() -> void:
	var sp := _fresh(3)
	sp.grant(1)
	assert_eq(sp.current, 4.0)
	assert_eq(sp.used, 0)
	assert_eq(_max(sp), 4)
	_assert_invariant(sp)


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


# --- bucket clamps ----------------------------------------------------------

func test_wound_caps_at_used_balance() -> void:
	var sp := _fresh(3)
	sp.spend(1)  # current=2, used=1
	sp.wound(5)  # more than `used` (1)
	assert_eq(sp.used, 0)
	assert_eq(sp.wounded, 1)
	_assert_invariant(sp)


func test_heal_caps_at_wounded_balance() -> void:
	# Build wounded=2 via claim + wound (legit state path) rather than poking
	# the bucket directly — keeps the invariant satisfied throughout.
	var sp := _fresh(0)
	sp.claim(2)  # base=2, used=2
	sp.wound(2)  # wounded=2, used=0
	assert_eq(sp.wounded, 2)
	sp.heal(5)
	assert_eq(sp.wounded, 0)
	assert_eq(sp.current, 2.0)
	_assert_invariant(sp)


func test_refund_caps_at_used_balance() -> void:
	var sp := _fresh(3)
	sp.spend(1)
	sp.refund(5)
	assert_eq(sp.used, 0)
	assert_eq(sp.current, 3.0)
	_assert_invariant(sp)


# --- the canonical-max promise ---------------------------------------------

func test_modifier_driven_max_works_normally() -> void:
	# A +5 ADD_BASE modifier should grow max by 5 (full PoolStat behavior).
	# heal_on_max_increase is true on the def → current also rises by 5.
	var sp := _fresh(3)
	var mod := StatModifier.new()
	mod.stat_id = &"skill_points"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 5.0
	sp.add_modifier(mod)
	assert_eq(_max(sp), 8)
	assert_eq(sp.current, 8.0)  # heal_on_max_increase
	_assert_invariant(sp)
	sp.remove_modifier(mod)
	assert_eq(_max(sp), 3)
