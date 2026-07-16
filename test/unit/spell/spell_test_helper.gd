class_name SpellTestHelper
extends RefCounted

## Lightweight builders for spell-resolver tests. Construct a Graph + a few
## SkillNodes + Entities + a SpellDef, all in-memory — no scene files driving
## test layout, no .tres fixtures per case. Resolver behaviour is pure
## w.r.t. world state (damage is deferred to VFX), so these fixtures are
## enough to assert on [member AttackOutcome.hits] and
## [member AttackOutcome.cancellations].
##
## Usage pattern:
## ```
## var h := SpellTestHelper.new()
## var graph := h.make_graph([[0,1],[1,2],[2,3]], test)   # line of 4
## var attacker := h.make_entity(graph, "A", Color.RED)
## var defender := h.make_entity(graph, "D", Color.BLUE)
## h.give_big_hp(defender)                                  # avoid mid-cast death noise
## h.assign_owner(graph, defender, [1, 2, 3])
## h.assign_owner(graph, attacker, [0])
## var config := h.make_config(h.fan_all(), h.owner_enemy(), null, {max_hops = 1})
## var spell := h.make_spell(config, [DamageEffect.new()], 10.0)
## var out := SpellResolver.resolve(spell, graph.get_skill_nodes()[1], graph.get_skill_nodes()[0], attacker, graph)
## ```

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")


func make_graph(adjacency: Array, gut: GutTest) -> Graph:
	var node_count: int = 0
	for pair in adjacency:
		node_count = max(node_count, int(pair[0]) + 1, int(pair[1]) + 1)
	var graph := _GRAPH_SCENE.instantiate()
	graph.name = "TestGraph"
	gut.add_child_autofree(graph)
	for i in node_count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		graph.skill_nodes_container.add_child(sn)
	for pair in adjacency:
		var a: SkillNode = graph.get_skill_nodes()[int(pair[0])]
		var b: SkillNode = graph.get_skill_nodes()[int(pair[1])]
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = a
		e.to = b
		graph.edges_container.add_child(e)
	return graph


## Zero `crit_chance`, so a test that pins damage MATH isn't rolling dice.
##
## The default board ships a 5% baseline crit (`crit_chance.tres`), and the
## stat-path roll uses a time-seeded RNG (see SpellResolver._resolve_crit), so
## a caller's seed can NOT make it reproduce. Left at 5%, every damage
## assertion in this suite fails ~5% of runs with exactly 2× the expected
## value — intermittent enough to read as noise. A crit test wants its own
## value anyway and sets it explicitly (see test_crit_resolution.gd). See #213.
func make_entity(graph: Graph, display_name: String, color: Color = Color.WHITE) -> Entity:
	var ent := Entity.new()
	ent.display_name = display_name
	ent.color = color
	ent.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	var cc: Stat = ent.stat_board.get_stat(&"crit_chance")
	if cc != null:
		cc.base_value = 0.0
	graph.add_child(ent)
	return ent


func give_big_hp(entity: Entity, value: float = 9999.0) -> void:
	if entity == null or entity.stat_board == null:
		return
	var nh: Stat = entity.stat_board.get_stat(&"node_health")
	if nh != null:
		nh.base_value = value


func assign_owner(graph: Graph, entity: Entity, indices: Array) -> void:
	var nodes := graph.get_skill_nodes()
	for i in indices:
		nodes[int(i)].owned_by = entity


## Build a SpellDef. `prop` is a PropagationConfig (use [method make_config]
## or wire one yourself).
func make_spell(prop: PropagationConfig, on_hits: Array[OnHitEffect], base_damage: float = 10.0) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "TestSpell"
	spell.base_damage = base_damage
	spell.propagation = prop
	spell.on_hit_effects = on_hits
	return spell


## Compose a PropagationConfig from parts. `opts` keys: max_hops (int, 0),
## max_visits_per_node (int, 1), damage_multiplier_per_hop (float, 1.0),
## seed_damage_fraction (float, 1.0).
func make_config(
		step: PropagationStep,
		filter: PropagationFilter,
		reducer: IncidentReducer,
		opts: Dictionary = {}) -> PropagationConfig:
	var c := PropagationConfig.new()
	c.step = step
	c.filter = filter
	c.reducer = reducer
	c.max_hops = int(opts.get("max_hops", 0))
	c.max_visits_per_node = int(opts.get("max_visits_per_node", 1))
	c.damage_multiplier_per_hop = float(opts.get("damage_multiplier_per_hop", 1.0))
	c.seed_damage_fraction = float(opts.get("seed_damage_fraction", 1.0))
	return c


# ── Tiny constructors so tests read declaratively ──────────────────────────

func fan_all() -> FanAllStep:
	return FanAllStep.new()


func no_step() -> NoStep:
	return NoStep.new()


func take_top_n(ranker: NodeRanker, n: int = 1, direction: int = TakeTopNStep.Direction.HIGHEST) -> TakeTopNStep:
	var s := TakeTopNStep.new()
	s.ranker = ranker
	s.take_count = n
	s.direction = direction
	return s


func degree_ranker() -> DegreeRanker:
	return DegreeRanker.new()


func stat_ranker(stat_id: StringName = &"node_health") -> StatRanker:
	var r := StatRanker.new()
	r.stat_id = stat_id
	return r


func owner_enemy() -> OwnerFilter:
	var f := OwnerFilter.new()
	f.scope = OwnerFilter.Scope.ENEMY
	return f


func owner(scope: int) -> OwnerFilter:
	var f := OwnerFilter.new()
	f.scope = scope
	return f


func degree_filter(compare: int = DegreeFilter.Compare.LESS) -> DegreeFilter:
	var f := DegreeFilter.new()
	f.compare = compare
	return f


func composite_filter(children: Array[PropagationFilter], mode: int = CompositeFilter.Mode.AND) -> CompositeFilter:
	var f := CompositeFilter.new()
	f.mode = mode
	f.children = children
	return f


func sum_reducer() -> SumDamageReducer:
	return SumDamageReducer.new()


func max_reducer() -> MaxDamageReducer:
	return MaxDamageReducer.new()


func cancel_if_multi() -> CancelIfMultiReducer:
	return CancelIfMultiReducer.new()


func hits_by_node(outcome: AttackOutcome) -> Dictionary:
	var out: Dictionary = {}
	for hit in outcome.hits:
		if not out.has(hit.target):
			out[hit.target] = []
		out[hit.target].append(hit)
	return out


func total_damage_on(outcome: AttackOutcome, node: SkillNode) -> float:
	var total: float = 0.0
	for hit in outcome.hits:
		if hit.target == node:
			total += hit.amount
	return total
