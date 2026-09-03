extends GutTest

## #728 pick-spell-first targeting: [SpellTargetUnion] over a real Graph +
## Entity fixture. Four things the acceptance spec names, none of which the
## older per-source tests could state:
##
##   1. The union EQUALS the naive per-source union — characterized against an
##      oracle that calls [method Targeting.valid_targets] once per source,
##      i.e. the implementation this issue replaced.
##   2. It costs strictly fewer whole-graph sweeps than that oracle: the
##      candidate set comes from the range finder first, so
##      `_filter_skill_nodes` is not called once per source.
##   3. The auto-picked source is the strongest local `spell_damage`, with the
##      lowest stable id breaking a tie (multiplayer-load-bearing: an
##      order-dependent pick makes host and client disagree).
##   4. "No eligible source" and "no valid target" are DIFFERENT states, not
##      one `is_empty()` — one toasts, the other draws an empty reach.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


## Counts whole-graph sweeps. [method Targeting._filter_skill_nodes] is the
## O(V) walk the inversion exists to stop calling per source, and
## [method Targeting.valid_targets] is its only caller — so spying the public
## method counts exactly the sweeps without reaching into privates.
class CountingTargeting extends NodeTargeting:
	var sweeps := 0

	func valid_targets(plan: AttackPlan, source: SkillNode) -> Array[SkillNode]:
		sweeps += 1
		return super.valid_targets(plan, source)


var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _mine: Array[SkillNode] = []
var _theirs: Array[SkillNode] = []


## A path: mine[0] - mine[1] - mine[2] - theirs[0] - theirs[1]. Owned degrees
## are 1/2/1, so a min_degree=2 spell has exactly ONE eligible caster while a
## min_degree=1 spell has three — which is what lets the tests below move the
## eligible set without touching the graph.
func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	var chain: Array[SkillNode] = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		_graph.add_skill_node(sn)
		sn.global_position = Vector2(i * 100.0, 0.0)
		chain.append(sn)
		if i > 0:
			_graph.add_edge(chain[i - 1], sn)

	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# An empty book, not the authored default: `eligible_sources` gates on
	# min_degree and ownership, never on membership, so the book's contents are
	# irrelevant — but it must EXIST, since it is the one home for the predicate.
	_attacker.spellbook = SpellBook.new()
	_graph.add_child(_attacker)
	_hostile = autofree(Entity.new())
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_mine = [chain[0], chain[1], chain[2]]
	_theirs = [chain[3], chain[4]]
	for n in _mine:
		_alloc.force_allocate(_attacker, n)
	for n in _theirs:
		_alloc.force_allocate(_hostile, n)


func _spell(targeting: Targeting, min_degree: int = 1) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "UnionProbe"
	spell.min_degree = min_degree
	spell.targeting = targeting
	return spell


func _hostile_hop_targeting(max_hops: int) -> CountingTargeting:
	var t := CountingTargeting.new()
	t.ownership_filter = SkillNode.Ownership.HOSTILE
	var f := HopRangeFinder.new()
	f.max_hops = max_hops
	t.range_finder = f
	return t


func _hostile_euclidean_targeting(max_distance: float) -> CountingTargeting:
	var t := CountingTargeting.new()
	t.ownership_filter = SkillNode.Ownership.HOSTILE
	var f := EuclideanRangeFinder.new()
	f.max_distance = max_distance
	t.range_finder = f
	return t


## The implementation #728 replaced: [method Targeting.valid_targets] once per
## source, deduped. Kept HERE, in the test, as the oracle the real union is
## characterized against — never in production, where it is the O(owned x V)
## shape the issue exists to remove.
func _naive_union(spell: SpellDef, plan: AttackPlan) -> Array[SkillNode]:
	var seen: Dictionary[SkillNode, bool] = {}
	for source in _attacker.spellbook.eligible_sources(spell, _attacker):
		for t in spell.targeting.valid_targets(plan, source):
			seen[t] = true
	var out: Array[SkillNode] = []
	for t in seen:
		out.append(t)
	return out


func _plan_for(spell: SpellDef) -> MagicAttackPlan:
	var p: MagicAttackPlan = autofree(MagicAttackPlan.new())
	p.attacker = _attacker
	p.spell = spell
	return p


## The sources that actually reach [param target] — the only ones that can
## contend for it. The auto-pick is per target, not global: the node with the
## most `spell_damage` is irrelevant to a target it cannot reach.
func _contenders(union: SpellTargetUnion, target: SkillNode) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for source in union.sources:
		if union.targets_from(source).has(target):
			out.append(source)
	return out


func _ids(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(_graph.get_stable_id(n))
	out.sort()
	return out


# ── 1. equals the naive union ──────────────────────────────────────────────

func test_hop_union_equals_the_naive_per_source_union() -> void:
	var spell := _spell(_hostile_hop_targeting(2))
	var plan := _plan_for(spell)
	var union := SpellTargetUnion.build(spell, _attacker, _graph, plan)
	assert_eq(_ids(union.targets()), _ids(_naive_union(spell, plan)),
			"the inverted union must be exactly the deduped per-source union")
	assert_false(union.targets().is_empty(), "precondition: the fixture reaches something")


func test_euclidean_union_equals_the_naive_per_source_union() -> void:
	var spell := _spell(_hostile_euclidean_targeting(150.0))
	var plan := _plan_for(spell)
	var union := SpellTargetUnion.build(spell, _attacker, _graph, plan)
	assert_eq(_ids(union.targets()), _ids(_naive_union(spell, plan)),
			"the single-sweep euclidean union must match the per-source oracle")
	assert_false(union.targets().is_empty(), "precondition: the fixture reaches something")


## Reach really is per source and not one radius reused: only the node nearest
## the enemy border can see over it at this distance.
func test_the_union_is_wider_than_any_single_source() -> void:
	var spell := _spell(_hostile_hop_targeting(1))
	var plan := _plan_for(spell)
	var union := SpellTargetUnion.build(spell, _attacker, _graph, plan)
	assert_eq(union.sources.size(), 3, "precondition: every owned node clears min_degree 1")
	var widest := 0
	for source in union.sources:
		widest = max(widest, union.targets_from(source).size())
	assert_true(union.targets().size() >= widest,
			"the union is at least as wide as its widest single source")


# ── 2. the loop order, not the cache ───────────────────────────────────────

func test_the_union_never_sweeps_the_whole_graph_per_source() -> void:
	var targeting := _hostile_hop_targeting(2)
	var spell := _spell(targeting)
	var plan := _plan_for(spell)
	assert_eq(_attacker.spellbook.eligible_sources(spell, _attacker).size(), 3,
			"precondition: three eligible casters, so a naive union would sweep 3x")
	SpellTargetUnion.build(spell, _attacker, _graph, plan)
	assert_eq(targeting.sweeps, 0,
			"candidates come from the range finder first — no whole-graph walk at all")


# ── 3. the auto-picked source ──────────────────────────────────────────────

func test_the_auto_picked_source_is_the_strongest_local_spell_damage() -> void:
	var spell := _spell(_hostile_hop_targeting(3))
	var plan := _plan_for(spell)
	# The node FURTHEST from the border gets the boost, so "strongest" and
	# "nearest the target" disagree — a union that quietly picked the nearest
	# source would pass a weaker version of this test.
	_mine[0].add_local_modifier(_flat(&"spell_damage", 50.0))
	var union := SpellTargetUnion.build(spell, _attacker, _graph, plan)
	var boosted_won := false
	for target in union.targets():
		var contenders := _contenders(union, target)
		var strongest: SkillNode = contenders[0]
		for c in contenders:
			if c.get_local_value(&"spell_damage") > strongest.get_local_value(&"spell_damage"):
				strongest = c
		assert_eq(union.source_for(target), strongest,
				"each target casts from the strongest node that can REACH it")
		if strongest == _mine[0]:
			boosted_won = true
	assert_true(boosted_won,
			"precondition: the boosted node wins at least one target it does not own by distance")


func test_a_tie_on_spell_damage_is_broken_by_the_lowest_stable_id() -> void:
	var spell := _spell(_hostile_hop_targeting(3))
	var plan := _plan_for(spell)
	# No modifiers anywhere: all three owned nodes tie at the board value, so
	# only the tiebreak can decide. It must be the id, not iteration order —
	# a host and a client that disagree here disagree about the launch command.
	var union := SpellTargetUnion.build(spell, _attacker, _graph, plan)
	var contested := 0
	for target in union.targets():
		var contenders := _contenders(union, target)
		var lowest: SkillNode = contenders[0]
		for c in contenders:
			if _graph.get_stable_id(c) < _graph.get_stable_id(lowest):
				lowest = c
		if contenders.size() > 1:
			contested += 1
		assert_eq(union.source_for(target), lowest,
				"a tie resolves to the lowest stable id, deterministically")
	assert_gt(contested, 0, "precondition: at least one target has more than one contender")


func _flat(stat_id: StringName, amount: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = amount
	return m


# ── 4. the two dead ends are different states ──────────────────────────────

func test_no_eligible_source_is_distinct_from_no_valid_target() -> void:
	# (a) structural: nothing owned clears min_degree. The picker toasts.
	var unreachable_degree := _spell(_hostile_hop_targeting(3), 9)
	var a := SpellTargetUnion.build(unreachable_degree, _attacker, _graph,
			_plan_for(unreachable_degree))
	assert_false(a.has_eligible_sources(), "no owned node clears min_degree 9")
	assert_false(a.has_targets())

	# (b) positional: casters exist, nothing hostile is in reach. NOT a denial
	# — the drawn reach is what explains it (owner, 2026-09-03).
	var too_short := _spell(_hostile_hop_targeting(0))
	var b := SpellTargetUnion.build(too_short, _attacker, _graph, _plan_for(too_short))
	assert_true(b.has_eligible_sources(), "the casters are there")
	assert_false(b.has_targets(), "they just cannot reach anything hostile")


# ── The union is what the reach visual is drawn from ───────────────────────

func test_the_euclidean_reach_visual_draws_one_ring_per_eligible_caster() -> void:
	var spell := _spell(_hostile_euclidean_targeting(150.0))
	var union := SpellTargetUnion.build(spell, _attacker, _graph, _plan_for(spell))
	var finder: RangeFinder = spell.targeting.range_finder
	var visual := finder.get_union_visual(_attacker, union)
	assert_eq(visual.rings.size(), union.sources.size(),
			"every eligible caster contributes its own circle, at its own radius")


func test_the_hop_reach_visual_is_drawn_even_when_nothing_is_targetable() -> void:
	# The (b) dead end above, from the player's side: selecting the spell must
	# still show where it reaches, or an empty target set reads as a blank.
	# Push the border back one node so a 1-hop spell reaches into neutral
	# ground and no further: casters exist, reach exists, no hostile is inside.
	_alloc.force_deallocate(_theirs[0])
	var spell := _spell(_hostile_hop_targeting(1))
	var union := SpellTargetUnion.build(spell, _attacker, _graph, _plan_for(spell))
	var finder: RangeFinder = spell.targeting.range_finder
	var visual := finder.get_union_visual(_attacker, union)
	assert_true(union.has_eligible_sources())
	assert_false(union.has_targets(), "precondition: this is the (b) dead end — nothing in reach")
	assert_false(visual.edges.is_empty(),
			"the reach is still drawn, so the empty target set reads as futility, not a blank")
