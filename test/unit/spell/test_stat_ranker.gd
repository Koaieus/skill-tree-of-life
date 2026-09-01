extends GutTest

## Behaviour of [StatRanker] (#702), plus load-time validation of every
## authored `stat_id` in the shipped spell defs.
##
## Before #702 there was no behavioural coverage at all — test_spell_defs.gd
## asserted only that Bruiser's step *has* a StatRanker, not that it ranks.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DEFS_DIR := "res://attack/spell/defs/"


func _setup(node_count: int) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board: EntityStatBoard = _BOARD.duplicate(true)
	board.node_health.base_value = 10.0
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var nodes: Array[SkillNode] = []
	for i in node_count:
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		n.name = "N%d" % i
		graph.skill_nodes_container.add_child(n)
		nodes.append(n)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for n in nodes:
		alloc.force_allocate(entity, n)

	return {"graph": graph, "entity": entity, "nodes": nodes}


func _hp(node: SkillNode) -> PoolStat:
	return node.node_board.get_stat(&"node_health") as PoolStat


func _ranker(stat_id: StringName) -> StatRanker:
	var r := StatRanker.new()
	r.stat_id = stat_id
	return r


# ── Scoring ─────────────────────────────────────────────────────────────────

func test_ranks_by_current_health_where_the_cap_ties() -> void:
	# The issue's whole claim. Two nodes of one entity share a cap (#660 made it
	# a live provider off the owner's baseline), so a cap ranker cannot separate
	# them; a current ranker must.
	var ctx: Dictionary = await _setup(2)
	var wounded: SkillNode = ctx.nodes[0]
	var healthy: SkillNode = ctx.nodes[1]
	_hp(wounded).set_current(2.0)
	_hp(healthy).set_current(9.0)

	var by_cap := _ranker(&"node_health")
	assert_almost_eq(
		by_cap.score(wounded, null, null), by_cap.score(healthy, null, null), 0.001,
		"ranking by cap is a tie — this is the bug, pinned")

	var by_current := _ranker(&"node_health__current")
	assert_lt(
		by_current.score(wounded, null, null), by_current.score(healthy, null, null),
		"the more-damaged node must rank lower, so HIGHEST picks the healthy one")


func test_score_of_a_null_node_is_zero() -> void:
	assert_almost_eq(_ranker(&"node_health__current").score(null, null, null), 0.0, 0.001)


func test_default_stat_id_is_the_current_accessor() -> void:
	assert_eq(
		StatRanker.new().stat_id, &"node_health__current",
		"the export default is the per-node-varying signal, not the tied cap")


# ── The description is player-facing, so the token must not leak ────────────

func test_description_spells_out_an_accessor_token() -> void:
	assert_eq(_ranker(&"node_health__current").get_description(), "current node_health",
		"the `__` join is authoring grammar, not tooltip text")
	assert_eq(_ranker(&"armor").get_description(), "armor",
		"a bare id is printed unchanged")


# ── Load-time validation of authored content ────────────────────────────────

func _collect_stat_rankers(res: Resource, out: Array[StatRanker], seen: Array[int]) -> void:
	if res == null or seen.has(res.get_instance_id()):
		return
	seen.append(res.get_instance_id())
	if res is StatRanker:
		out.append(res as StatRanker)
	for p in res.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var v: Variant = res.get(p.name)
		if v is Resource:
			_collect_stat_rankers(v as Resource, out, seen)
		elif v is Array:
			for e in (v as Array):
				if e is Resource:
					_collect_stat_rankers(e as Resource, out, seen)


## Every `StatRanker` reachable from a shipped `.tres`, paired with its file.
## Scanned off disk rather than a preload list, so a spell def added later is
## covered without anyone remembering to append it here.
func _authored_rankers() -> Array:
	var found: Array = []
	var dir := DirAccess.open(_DEFS_DIR)
	assert_not_null(dir, "spell defs directory must exist")
	if dir == null:
		return found
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var path := _DEFS_DIR + f
		var res: Resource = load(path)
		var rankers: Array[StatRanker] = []
		_collect_stat_rankers(res, rankers, [] as Array[int])
		for r in rankers:
			found.append({"path": path, "ranker": r})
	return found


func test_every_authored_stat_id_names_a_real_stat_and_accessor() -> void:
	# The gap no read-time policy can close: a typo'd BASE id degrades to 0.0
	# with no warning at all, which silently ranks that node worst. Same posture
	# as test_stat_def_roster.gd — fail on bad authored content, at load.
	var authored := _authored_rankers()
	assert_gt(authored.size(), 0, "at least one shipped spell must use a StatRanker")

	var ctx: Dictionary = await _setup(1)
	var node: SkillNode = ctx.nodes[0]
	var entity: Entity = ctx.entity

	for entry in authored:
		var r: StatRanker = entry.ranker
		var where: String = entry.path
		var base := StatFormula.base_of(r.stat_id)
		assert_not_null(
			StatRegistry.get_def(base),
			"%s: StatRanker.stat_id '%s' has no StatDef for base id '%s'"
				% [where, r.stat_id, base])

		var accessor := StatFormula.accessor_of(r.stat_id)
		if accessor == &"":
			continue
		# Resolve in the same order NodeCombat._read_accessor does — node board
		# first, then the owner's — rather than mirroring a table of which class
		# answers what.
		var s: Stat = node.node_board.get_stat(base)
		if s == null:
			s = entity.stat_board.get_stat(base)
		assert_not_null(s, "%s: no live Stat for '%s' on either board" % [where, base])
		if s == null:
			continue
		assert_true(
			s.accessors().has(accessor),
			"%s: '%s' answers no accessor '%s' (it answers %s)"
				% [where, base, accessor, str(s.accessors().keys())])


# ── The shadow world (docs/domain/attack-timeline.md) ───────────────────────

func test_ranker_reads_the_cast_s_own_damage_on_a_shadow() -> void:
	# A cap does not move mid-cast, so rank-by-cap never had to care which world
	# it read. `__current` does: an attack resolves on a shadow and lands there
	# as it goes, so wave 0's damage must be visible when wave 1 ranks.
	var ctx: Dictionary = await _setup(2)
	var a: SkillNode = ctx.nodes[0]
	var b: SkillNode = ctx.nodes[1]
	_hp(a).set_current(9.0)
	_hp(b).set_current(8.0)

	var world := CombatWorld.shadow()
	# Every shadow needs this — RefCounted has no cycle collector, so an
	# unreleased clone is never collected at all (CombatWorld.free_shadow).
	var pctx := PropagationContext.new()
	pctx.graph = ctx.graph
	pctx.world = world
	var r := _ranker(&"node_health__current")

	assert_gt(r.score(a, null, pctx), r.score(b, null, pctx),
		"before any damage, `a` is the healthier of the two")

	# Damage `a` on the SHADOW only — exactly what an earlier wave does.
	world.combat_for(a).take_damage(5.0, null)

	assert_lt(r.score(a, null, pctx), r.score(b, null, pctx),
		"the ranker must see this cast's own damage, not pre-cast HP")
	assert_almost_eq(_hp(a).current, 9.0, 0.001,
		"and the live node must be untouched — nothing but a replayed record mutates it")

	world.free_shadow()


func test_live_world_reads_identically_to_the_node() -> void:
	var ctx: Dictionary = await _setup(1)
	var node: SkillNode = ctx.nodes[0]
	_hp(node).set_current(4.0)
	var pctx := PropagationContext.new()
	pctx.graph = ctx.graph  # world defaults to CombatWorld.live()
	var r := _ranker(&"node_health__current")

	assert_almost_eq(r.score(node, null, pctx), 4.0, 0.001,
		"on a live world combat_for returns the node's own slice — same answer, one path")
	assert_almost_eq(r.score(node, null, null), 4.0, 0.001,
		"and a null ctx falls back to the same read")
