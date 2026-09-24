extends GutTest
## The subtype axis (#1056): a second key on the per-node pool filter,
## orthogonal to archetype. Five guards — the gate, its inertness, the entry-id
## collision it creates, decision 13's demotion, and the salted stream.
##
## See docs/design/node_subtypes.md for the model and the decisions.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")
const _PRESET := "res://procgen/presets/first_level/first_level.tres"
## Small enough to generate fast, big enough that a 0.3 placement chance lands
## on a healthy handful of nodes.
const _NODE_COUNT := 90
const _SEED := 10560

## The id-segment vocabulary `StatPool._op_short` mints, restated here so the
## format pin below is independent of the implementation it pins.
const _OP_SHORT := {
	StatModifier.Operation.ADD_BASE: "addb",
	StatModifier.Operation.INCREASE: "inc",
	StatModifier.Operation.MULTIPLY: "mul",
	StatModifier.Operation.ADD_BONUS: "addn",
	StatModifier.Operation.SET: "set",
}


func _subtype(id_: StringName, chance: float = 0.0) -> NodeSubtype:
	var s := NodeSubtype.new()
	s.id = id_
	s.base_chance = chance
	return s


func _pool(stat: StringName, subs: Array[NodeSubtype]) -> StatPool:
	var p := StatPool.new()
	p.stat_id = stat
	p.subtypes = subs
	return p


func _set_of(pools: Array[StatPool]) -> ModifierPoolSet:
	var pack := StatPack.new()
	pack.archetype_stat = &"dexterity"
	pack.pools = pools
	var packs: Array[StatPack] = [pack]
	var s := ModifierPoolSet.new()
	s.packs = packs
	return s


func _ids(entries: Array[ModifierPoolEntry]) -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append(String(e.id))
	return out


# ── 1. the gate ──────────────────────────────────────────────────────────

## A pool naming only `bless` must be invisible to a regular node and visible
## to a blessed one. Decision 12 — the set IS the give-up, so this also covers
## "blighted DEX cannot draw the crit pool".
func test_a_pool_gated_to_a_subtype_is_absent_from_another_subtypes_flatten() -> void:
	var bless := _subtype(&"bless")
	var gated := _pool(&"crit_chance", [bless])
	var shared := _pool(&"dexterity", [] as Array[NodeSubtype])
	var pool_set := _set_of([gated, shared] as Array[StatPool])

	var regular_ids := _ids(pool_set.flatten_for_node(&"dexterity", NodeSubtype.regular()))
	var bless_ids := _ids(pool_set.flatten_for_node(&"dexterity", bless))

	assert_false(regular_ids.is_empty(), "sanity: a regular DEX node still draws the shared pool")
	for id_ in regular_ids:
		assert_false(id_.begins_with("crit_chance_"),
			"a regular node must not draw a [bless]-gated pool — got %s" % id_)
	var saw_gated := false
	for id_ in bless_ids:
		if id_.begins_with("crit_chance_"):
			saw_gated = true
	assert_true(saw_gated, "a blessed node MUST draw the [bless]-gated pool — got %s" % str(bless_ids))
	# The shared pool is drawn by both — `[]` means any.
	assert_eq(bless_ids.size(), regular_ids.size() * 2,
		"the shared pool is drawn by both subtypes, the gated one only by bless")


# ── 2. inertness ─────────────────────────────────────────────────────────

## With no subtypes authored anywhere (every shipped pool today), the two-key
## filter selects exactly what the one-key archetype filter selected, and
## `to_entries` appends no id segment — so every entry id is byte-identical.
func test_an_empty_subtype_set_selects_exactly_what_the_archetype_gate_selects() -> void:
	# #1059 authored real gates on the shipped pools, so the question "is `[]`
	# inert" is now asked of a deep copy with every gate CLEARED. `duplicate(true)`
	# copies the packs and pools, so clearing here cannot leak into the cached
	# resource other tests load.
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	for pack in pool_set.packs:
		for pool in pack.pools:
			if pool != null:
				pool.subtypes = [] as Array[NodeSubtype]
	var blight := _subtype(&"blight")
	for primary: StringName in [&"strength", &"dexterity", &"intelligence",
			&"wisdom", &"perception", &"constitution"]:
		# What the archetype key alone selects, computed here rather than via
		# the function under test.
		var expected: Array[String] = []
		for pack in pool_set.packs:
			for pool in pack.pools:
				if pool == null:
					continue
				if pack.archetype_stat == &"" or pack.archetype_stat == primary:
					expected.append_array(_ids(pool.to_entries(pack.archetype_stat)))
		assert_eq(_ids(pool_set.flatten_for_node(primary, NodeSubtype.regular())), expected,
			"%s: the two-key flatten must select what the archetype gate selected" % primary)
		assert_eq(_ids(pool_set.flatten_for_node(primary, blight)), expected,
			"%s: an unauthored subtype changes nothing while every pool is []" % primary)
		assert_eq(_ids(pool_set.flatten_for_node(primary)), expected,
			"%s: the defaulted (null) subtype keeps today's callers unchanged" % primary)

	# Format pin: `<stat>_<op>_<arch>_t<tier>`, no subtype segment anywhere.
	for pack in pool_set.packs:
		for pool in pack.pools:
			var arch_seg: String = String(pack.archetype_stat) if pack.archetype_stat != &"" else "any"
			var op_seg: String = _OP_SHORT[pool.operation]
			var want: Array[String] = []
			for t in range(pool.min_tier, pool.max_tier + 1):
				want.append("%s_%s_%s_t%d" % [pool.stat_id, op_seg, arch_seg, t])
			assert_eq(_ids(pool.to_entries(pack.archetype_stat)), want,
				"an ungated pool's entry ids must not move (%s)" % pool.resource_name)


# ── 3. the entry-id collision ────────────────────────────────────────────

## Two pools for the same (stat, op, archetype) gated to different subtypes
## must mint DIFFERENT entry ids, or weight profiles target the wrong one. The
## segment appears ONLY when `subtypes` is non-empty, so no existing id moves.
func test_subtype_gated_pools_do_not_collide_on_entry_id() -> void:
	var bless := _subtype(&"bless")
	var blight := _subtype(&"blight")
	var blessed_pool := _pool(&"crit_chance", [bless])
	var blighted_pool := _pool(&"crit_chance", [blight])
	var ungated := _pool(&"crit_chance", [] as Array[NodeSubtype])

	var a := _ids(blessed_pool.to_entries(&"dexterity"))
	var b := _ids(blighted_pool.to_entries(&"dexterity"))
	var plain := _ids(ungated.to_entries(&"dexterity"))

	assert_eq(a.size(), plain.size(), "sanity: same tier span, same entry count")
	for i in a.size():
		assert_ne(a[i], b[i], "two subtype-gated pools must not collide on entry id")
		assert_ne(a[i], plain[i], "a gated pool's id must differ from the ungated one's")
	# The ungated id is byte-identical to what it was before the axis landed.
	var want: Array[String] = []
	for t in range(ungated.min_tier, ungated.max_tier + 1):
		want.append("crit_chance_addb_dexterity_t%d" % t)
	assert_eq(plain, want, "an empty `subtypes` appends no segment")
	# Author order is not identity: [bless, blight] and [blight, bless] are the
	# same set and must mint the same ids.
	var ab := _pool(&"crit_chance", [bless, blight])
	var ba := _pool(&"crit_chance", [blight, bless])
	assert_eq(_ids(ab.to_entries(&"dexterity")), _ids(ba.to_entries(&"dexterity")),
		"the segment is a SET — author order must not mint a second id")


# ── generation helpers (tests 4 & 5) ─────────────────────────────────────

func _fresh_config() -> GraphProcgenConfig:
	var cfg: GraphProcgenConfig = (load(_PRESET) as GraphProcgenConfig).duplicate(true)
	cfg.seed = _SEED
	# `topology` and `content` are top-level module `.tres` ExtResources, so the
	# deep duplicate above did NOT copy them — mutating either in place would
	# poison the cached resource every other test loads (#349 acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.content = cfg.content.duplicate(true)
	return cfg


## Appends a universal pool only a blighted node can draw. The pool set and its
## packs are ExtResources too, so every level gets its own copy first.
func _add_blight_pool(cfg: GraphProcgenConfig, blight: NodeSubtype) -> void:
	var pool_set: ModifierPoolSet = cfg.content.modifier_pool_set.duplicate(true)
	var packs: Array[StatPack] = []
	packs.assign(pool_set.packs)
	packs.append(_pack_of(_pool(&"armor", [blight])))
	pool_set.packs = packs
	cfg.content.modifier_pool_set = pool_set


func _pack_of(pool: StatPool) -> StatPack:
	var pack := StatPack.new()
	pack.pools = [pool] as Array[StatPool]
	return pack


func _generate(cfg: GraphProcgenConfig) -> Array:
	var graph: Graph = autofree((load("res://graph/graph.tscn") as PackedScene).instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("nodes", [])


## Only archetype-bearing nodes carry a stamped subtype: the budget-0 else
## branch and authored-scene nodes legitimately keep `null`.
func _content_nodes(nodes: Array) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for n in nodes:
		var sn := n as SkillNode
		if sn != null and sn.archetype != null:
			out.append(sn)
	return out


func _mod_text(sn: SkillNode) -> String:
	var parts: Array[String] = []
	for m in sn.modifiers:
		parts.append("%s/%d/%.6f" % [m.stat_id, m.operation, m.value])
	parts.sort()
	return ";".join(parts)


# ── 4. decision 13's demotion ────────────────────────────────────────────

## A subtype at `base_chance = 1.0` that no pool names must leave EVERY node on
## the resolved default — a node must never look like something it does not
## play. The control half proves the demotion is not vacuous: give that same
## subtype one drawable pool and nodes stand on it.
func test_a_subtype_with_no_drawable_content_demotes_to_the_default() -> void:
	var blight := _subtype(&"blight", 1.0)
	var starved := _fresh_config()
	starved.content.subtypes = [blight] as Array[NodeSubtype]
	var default_id: StringName = starved.content.resolved_default_subtype().id
	assert_eq(default_id, &"regular", "sanity: the preset authors no default override")

	var nodes := _content_nodes(await _generate(starved))
	assert_true(nodes.size() > 10, "sanity: the preset generated content-bearing nodes")
	for sn in nodes:
		assert_not_null(sn.subtype, "procgen stamps a subtype on every archetype node")
		assert_eq(sn.subtype.id, default_id,
			"a subtype no pool names must demote to the default (D13)")

	# Control: the same roll, with content for it, stands.
	var fed := _fresh_config()
	fed.content.subtypes = [blight] as Array[NodeSubtype]
	_add_blight_pool(fed, blight)
	var stood := 0
	for sn in _content_nodes(await _generate(fed)):
		if sn.subtype != null and sn.subtype.id == &"blight":
			stood += 1
	assert_true(stood > 0, "a subtype WITH drawable content must stand on some node")


# ── 5. the salt trap ─────────────────────────────────────────────────────

## Generating with `subtypes = []` and with a subtype authored must leave every
## node that ends up on the default with IDENTICAL modifiers. Red if the
## subtype roll comes off the main rng stream.
##
## The authored subtype deliberately has no drawable pool, so every node ends
## up on the default and the comparison covers the whole graph. A subtype that
## actually STANDS legitimately changes that node's own draws off the shared
## stream, which shifts every node after it — so a standing subtype cannot
## isolate the question this test asks. Its coverage lives in test 4's control.
func test_the_subtype_roll_does_not_shift_the_main_rng_stream() -> void:
	var without := _fresh_config()
	without.content.subtypes = [] as Array[NodeSubtype]
	var with_ := _fresh_config()
	with_.content.subtypes = [_subtype(&"blight", 0.3)] as Array[NodeSubtype]

	var a := await _generate(without)
	var b := await _generate(with_)
	assert_eq(a.size(), b.size(), "the subtype roll must not change the node count")
	for i in a.size():
		var sa := a[i] as SkillNode
		var sb := b[i] as SkillNode
		assert_eq(sa.position, sb.position, "node %d: placement must not shift" % i)
		assert_eq(_mod_text(sa), _mod_text(sb),
			"node %d: a default-subtype node must roll identical modifiers" % i)
