extends GutTest
## #718 — which archetype's nodes can roll which procgen pool.
##
## Two guards, both structural. Neither pins a magnitude: every `unit_value`,
## `range_floor` and `pool_weight` under `procgen/pools/` is the owner's to
## retune between balance passes, and a test that pins one turns a deliberate
## tune red while catching nothing (#719, #717).
##
## The bug they exist for: `1aa8f29` re-pointed the CON pack's curse from
## `intelligence` to `dexterity` by editing `stat_id` alone. The pool's
## `archetype_stat` had never been authored, and its default `&""` means
## **universal** — so the curse shipped on all six archetypes rather than on
## CON nodes. Its stale `tags = [&"int", …]` then handed it a 3x weight boost
## on INT nodes (`awp_main`) and a hard ban on gold/purple (`forbid_tags`).
##
## Nothing headless caught either half. `StatPack._get_configuration_warnings`
## does flag a pool whose non-empty `archetype_stat` disagrees with its pack's
## (it was firing on `intelligence.tres` at the time), but it is `@tool`-only —
## an inspector triangle. `test_no_configuration_warnings` is that check made
## headless. It still cannot catch a `&""` pool, because universal pools are
## legal in any pack by design; `test_curse_scoping_law` covers that side.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")

## The law, as authored (#718): the two solid archetypes tax the two
## quick/clever attributes; the two quick/clever archetypes tax the two
## defensive stats. WIS and PER are deliberately curse-free — a stated
## asymmetry, not an omission: they are 5% / 3% of the graph and already pay
## by being locked out of universal content via their `forbid_tags` (#750).
const _CURSED_STAT := {
	&"strength": &"intelligence",      # power over thought
	&"constitution": &"dexterity",     # armor is heavy
	&"intelligence": &"node_health",   # the mage's territory is brittle
	&"dexterity": &"armor",            # the duelist wears no plate
}

const _CURSE_FREE: Array[StringName] = [&"wisdom", &"perception"]


func _negative_stat_ids(primary: StringName) -> Array[StringName]:
	# An entry is a downside iff BOTH ends of its rolled range are negative.
	# `value_range.y` is the end nearer zero for a negative pool — the pair is
	# role-ordered by StatPool._tier_magnitude_bounds, not numerically sorted —
	# so `y < 0` is exactly "negative at both ends". Same idiom the existing
	# negative-pool tests use.
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var out: Array[StringName] = []
	for e in pool_set.flatten_for_node(primary):
		if e.value_range.y < 0.0 and not e.stat_id in out:
			out.append(e.stat_id)
	return out


func test_curse_scoping_law() -> void:
	for primary: StringName in _CURSED_STAT:
		var expected: StringName = _CURSED_STAT[primary]
		var negatives := _negative_stat_ids(primary)
		assert_true(expected in negatives,
			"a %s node must be able to roll a %s downside (#718's law) — found %s"
			% [String(primary), String(expected), str(negatives)])


func test_a_curse_reaches_only_its_own_archetype() -> void:
	# The half `_get_configuration_warnings` structurally cannot check: a pool
	# left at the `&""` default is legal everywhere, so the only way to catch
	# one is to look at who can draw it. Every cursed stat in the law must be
	# unreachable from every OTHER archetype.
	for primary: StringName in _CURSED_STAT:
		var negatives := _negative_stat_ids(primary)
		for other: StringName in _CURSED_STAT:
			if other == primary:
				continue
			var foreign: StringName = _CURSED_STAT[other]
			# min_damage_taken is CON-scoped and also negative, but it is not
			# in the law's table, so it never collides with this check.
			assert_false(foreign in negatives,
				"a %s node must NOT roll %s's %s curse — that pool has leaked its scope (probably an unauthored archetype_stat, which defaults to &\"\" = universal)"
				% [String(primary), String(other), String(foreign)])


func test_wisdom_and_perception_stay_curse_free() -> void:
	for primary in _CURSE_FREE:
		var negatives := _negative_stat_ids(primary)
		assert_eq(negatives.size(), 0,
			"%s is deliberately curse-free (#718) but can roll downsides on %s"
			% [String(primary), str(negatives)])


func test_no_configuration_warnings() -> void:
	# The headless half of the `@tool`-only inspector check. Sweeps every pack
	# AND every pool reachable from the shipped pool set.
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var complaints: Array[String] = []
	for pack in pool_set.packs:
		assert_not_null(pack, "the pool set must not carry a null pack")
		if pack == null:
			continue
		for w in pack._get_configuration_warnings():
			complaints.append("pack %s: %s" % [String(pack.archetype_stat), w])
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			if p == null:
				continue
			for w in p._get_configuration_warnings():
				complaints.append("pool %s/%s: %s" % [
						String(pack.archetype_stat), String(p.stat_id), w])
	assert_eq(complaints.size(), 0,
		"procgen pool content has configuration warnings — these are invisible headless, so they accrete silently:\n  %s"
		% "\n  ".join(complaints))
