extends GutTest
## #718 — which archetype's nodes can roll which procgen pool.
##
## Two guards, both structural. Neither pins a magnitude: every `unit_value`,
## `range_floor` and `pool_weight` under `procgen/pools/` is the owner's to
## retune between balance passes, and a test that pins one turns a deliberate
## tune red while catching nothing (#719, #717).
##
## The bug they exist for: `1aa8f29` re-pointed the CON pack's curse from
## `intelligence` to `dexterity` by editing `stat_id` alone. The pool's own
## `archetype_stat` had never been authored, and its default `&""` meant
## **universal** — so the curse shipped on all six archetypes rather than on
## CON nodes. #751 removed that field: the pack (the file) is now the only
## gate, so a pool's scope is where it sits, and
## `test_every_pack_is_gated_by_its_file_name` pins each pack's one value.
## `test_curse_scoping_law` and the sweeps below still read effective scope
## (who can draw what), and `test_no_configuration_warnings` makes the
## `@tool`-only inspector checks headless.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")

## The law, as authored (#718): the two solid archetypes tax the two
## quick/clever attributes; the two quick/clever archetypes tax the two
## defensive stats. WIS and PER are deliberately curse-free — a stated
## asymmetry, not an omission: they are 5% / 3% of the graph and already pay
## by being locked out of universal *defensive* content (armor, node_health)
## via their `forbid_tags` (#750); mobility still rolls.
const _CURSED_STAT := {
	&"strength": &"intelligence",      # power over thought
	&"constitution": &"dexterity",     # armor is heavy
	&"intelligence": &"node_health",   # the mage's territory is brittle
	&"dexterity": &"armor",            # the duelist wears no plate
}

const _CURSE_FREE: Array[StringName] = [&"wisdom", &"perception"]

## Every archetype, for the sweeps that must check absence as well as presence.
const _ALL_ARCHETYPES: Array[StringName] = [&"strength", &"dexterity",
	&"intelligence", &"constitution", &"wisdom", &"perception"]

## #1058 decision 4 — where each DoT family's potency lives. Archetype picks
## the family: STR corrupts, DEX poisons, INT withers, CON curses. Structural
## only, like everything else here: no magnitude is pinned.
const _POTENCY_HOME := {
	&"corruption_potency": &"strength",
	&"poison_potency": &"dexterity",
	&"wither_potency": &"intelligence",
	&"curse_potency": &"constitution",
}


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
				"a %s node must NOT roll %s's %s curse — that pool has leaked its scope (probably filed in the wrong pack, or in universal.tres)"
				% [String(primary), String(other), String(foreign)])


func test_wisdom_and_perception_stay_curse_free() -> void:
	for primary in _CURSE_FREE:
		var negatives := _negative_stat_ids(primary)
		assert_eq(negatives.size(), 0,
			"%s is deliberately curse-free (#718) but can roll downsides on %s"
			% [String(primary), str(negatives)])


func _reachable_stat_ids(primary: StringName,
		subtype: NodeSubtype = null) -> Array[StringName]:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var out: Array[StringName] = []
	for e in pool_set.flatten_for_node(primary, subtype):
		if not e.stat_id in out:
			out.append(e.stat_id)
	return out


## #1058 — each potency is drawable from its own archetype and from no other.
## The absence half is the one that matters: a potency pool left on the wrong
## archetype (or at the `&""` universal default) hands every node in the game
## the whole DoT offense, which is the `#718` bug wearing a different stat.
##
## #1059 then gated every potency to the `blight` subtype, so the sweep runs
## over all three poles and exactly one (archetype, pole) cell may reach each
## potency.
func test_each_dot_potency_reaches_only_its_own_archetype() -> void:
	var blight := NodeSubtype.new()
	blight.id = &"blight"
	var bless := NodeSubtype.new()
	bless.id = &"bless"
	var poles: Array[NodeSubtype] = [NodeSubtype.regular(), blight, bless]
	for primary in _ALL_ARCHETYPES:
		for stat: StringName in _POTENCY_HOME:
			var home: StringName = _POTENCY_HOME[stat]
			for pole in poles:
				var reachable := _reachable_stat_ids(primary, pole)
				if home == primary and pole.id == &"blight":
					assert_true(stat in reachable,
						"a blighted %s node must be able to roll %s (#1058 decision 4, #1059's pole) — reachable: %s"
						% [String(primary), String(stat), str(reachable)])
				else:
					assert_false(stat in reachable,
						"a %s/%s node must NOT roll %s — that is blighted %s's content"
						% [String(primary), String(pole.id), String(stat), String(home)])

## #1094 — the archive umbrella (`dot_stacks_per_hit`) is blighted WIS's own
## content and no other archetype/pole may roll it (same absence shape as
## `_POTENCY_HOME`'s sweep above, one stat instead of four).
func test_dot_stacks_per_hit_is_blighted_wisdom_only() -> void:
	var blight := NodeSubtype.new(); blight.id = &"blight"
	var bless := NodeSubtype.new(); bless.id = &"bless"
	var poles: Array[NodeSubtype] = [NodeSubtype.regular(), blight, bless]
	for primary in _ALL_ARCHETYPES:
		for pole in poles:
			var reachable := _reachable_stat_ids(primary, pole)
			if primary == &"wisdom" and pole.id == &"blight":
				assert_true(&"dot_stacks_per_hit" in reachable,
					"blighted wisdom must be able to roll dot_stacks_per_hit — reachable: %s" % str(reachable))
			else:
				assert_false(&"dot_stacks_per_hit" in reachable,
					"a %s/%s node must NOT roll dot_stacks_per_hit — that is blighted wisdom's content"
					% [String(primary), String(pole.id)])


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


## #750 — WIS (gold) and PER (purple) are locked out of universal *defensive*
## content by `forbid_tags = [&"defense"]`, and only that: mobility still
## rolls. Runs each entry through the real weight pipeline
## (`GraphProcgen._v4_weighted_pick` on a one-entry list — non-null iff its
## effective weight is > 0), with the module's own profiles and forbid list.
const _MODULE_CONTENTS: Array[String] = [
	"res://procgen/modules/first_level/content.tres",
	"res://procgen/modules/coop_versus/content.tres",
]


func _is_drawable(entry: ModifierPoolEntry, content: GraphProcgenContent,
		policy: ArchetypePolicy, forbid: Array[StringName]) -> bool:
	var ctx := WeightContext.new()
	ctx.archetype = policy.id
	ctx.position = Vector2.ZERO
	ctx.node_index = 0
	ctx.forbid_tags = forbid
	var one: Array[ModifierPoolEntry] = [entry]
	return GraphProcgen._v4_weighted_pick(one, content.weight_profiles, ctx,
		1 << 20, RandomNumberGenerator.new()) != null


func test_gold_and_purple_forbid_defense_but_roll_mobility() -> void:
	for path in _MODULE_CONTENTS:
		var content := load(path) as GraphProcgenContent
		assert_not_null(content, path)
		var seen := 0
		for policy: ArchetypePolicy in content.archetypes:
			if policy == null or not policy.id in [&"gold", &"purple"]:
				continue
			seen += 1
			var forbid: Array[StringName] = policy.forbid_tags
			var mobility_live := 0
			for e in content.modifier_pool_set.flatten_for_node(policy.primary_stat):
				var live := _is_drawable(e, content, policy, forbid)
				if &"defense" in e.tags:
					assert_false(live, "%s: %s must never roll %s (defense is forbidden)"
						% [path.get_file(), String(policy.id), String(e.id)])
				if &"mobility" in e.tags and live:
					mobility_live += 1
			assert_gt(mobility_live, 0, "%s: %s must still roll mobility content"
				% [path.get_file(), String(policy.id)])
		assert_eq(seen, 2, "%s must author both gold and purple" % path)


## #751 — the pack is the only archetype gate, so the pack's `archetype_stat`
## is the whole scoping fact: it must equal the file's stem, and `&""`
## (universal) is legal on exactly one pack, `universal.tres`. A forgotten
## field reads as universal, which is why the file name is pinned to it.
const _POOLS_DIR := "res://procgen/pools/"
const _UNIVERSAL_STEM := "universal"


func test_every_pack_is_gated_by_its_file_name() -> void:
	var universal: Array[String] = []
	var packs := 0
	for f in DirAccess.get_files_at(_POOLS_DIR):
		if not f.ends_with(".tres"):
			continue
		var pack := load(_POOLS_DIR + f) as StatPack
		if pack == null:
			continue
		packs += 1
		var stem := f.get_basename()
		if pack.archetype_stat == &"":
			universal.append(f)
		var want: StringName = &"" if stem == _UNIVERSAL_STEM else StringName(stem)
		assert_eq(pack.archetype_stat, want,
			"%s: a pack's archetype_stat must be its file stem (universal.tres: &\"\")" % f)
	assert_gt(packs, 6, "expected the six archetype packs plus universal.tres")
	assert_eq(universal, [_UNIVERSAL_STEM + ".tres"] as Array[String],
		"exactly one pack is universal, and it is universal.tres")
