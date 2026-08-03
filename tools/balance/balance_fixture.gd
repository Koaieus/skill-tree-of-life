class_name BalanceFixture
extends RefCounted

## Real-fixture builder for the #268 balance harness. Assembles an actual
## `Entity` / `SkillNode` / `Graph` / `AllocationSystem` and drives the real
## game mechanics (level-up, allocation) to reach a target level — it does NOT
## hand-derive the D-16 owned-node formula (`starting_SP + sp_gain×(level−1) +
## milestones`). That formula moved twice already (see #268's "your axes moved"
## comment); driving `Entity._on_xp_replenished()` for real means a future
## change to `sp_gain_on_levelup` / the milestone cadence / the leveling
## formula is picked up automatically instead of drifting out of sync.
##
## Per decision 2/3 (#268): real fixtures, no formula-level reimplementation,
## no refactor of game code to fit the harness.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

## Minimum node count so hop-distance fixtures (core-adjacent, aura reach)
## always have a "beyond range" node available even at low levels.
const _MIN_NODES := 6

## Chain: a straight line — only hop DISTANCE matters, coverage-fraction
## readouts are meaningless on it (see Topology.TREE). Tree: a deterministic
## k-ary tree rooted at the core (heap-style indexing: node i's parent is
## `(i-1) / branching_factor`) — hop distance and node COUNT come apart,
## which is what a real (branching) territory looks like and what a
## coverage-fraction reading needs to mean anything. #268 review: a chain
## caps a range-R aura at exactly R covered nodes forever, so
## `aura_coverage_fraction` on a chain reports "safe" for a topological
## reason, never a balance one.
enum Topology { CHAIN, TREE }

var graph: Graph
var alloc: AllocationSystem
var entity: Entity
## Every SkillNode in the fixture's graph (owned or not — the chain/tree is
## padded to `_MIN_NODES`/beyond `wanted` for hop-distance headroom).
## `nodes[0]` is always the core.
var nodes: Array[SkillNode] = []
## The subset of `nodes` actually force_allocated to `entity` — this is the
## real ownership count/set, never derived back out of `skill_points.value`
## (that pool is mutable state, not a node count, and only happened to agree
## before the padding above could push it out of sync).
var owned_nodes: Array[SkillNode] = []


## Builds an entity at `level` (via the real level-up path), owning a
## territory of SkillNodes matching whatever `skill_points.value` comes out
## of that climb (D-16), parented under `root`. `core_class` is nullable — a
## null class is how a fixture expresses "zero STR/DEX/INT investment" (only
## the board's level→CON intrinsic still applies, since that one is
## class-independent).
##
## Coroutine: caller must `await`.
static func build(
	root: Node,
	level: int,
	core_class: CoreClass = null,
	topology: Topology = Topology.CHAIN,
	branching_factor: int = 3,
) -> BalanceFixture:
	var fx := BalanceFixture.new()
	fx.graph = _GRAPH_SCENE.instantiate()
	fx.graph.name = "BalanceGraph_%d" % Time.get_ticks_usec()
	root.add_child(fx.graph)

	fx.entity = Entity.new()
	fx.entity.display_name = "Fixture"
	fx.entity.stat_board = _BOARD.duplicate(true) as StatBoard
	fx.entity.core_class = core_class
	fx.graph.add_child(fx.entity)
	await root.get_tree().process_frame

	fx.alloc = AllocationSystem.new()
	fx.alloc.graph = fx.graph
	root.add_child(fx.alloc)

	# Drive the real level-up path (D-16) rather than re-deriving its formula.
	for _i in range(level - 1):
		fx.entity._on_xp_replenished()

	var wanted: int = maxi(int(fx.entity.stat_board.skill_points.value), 1)
	var node_count: int = maxi(wanted, _MIN_NODES)

	for i in node_count:
		var sn: SkillNode = _NODE_SCENE.instantiate()
		sn.name = "N%d" % i
		sn.position = Vector2((i % 8) * 100.0, (i / 8) * 100.0)
		fx.graph.add_skill_node(sn)
		fx.nodes.append(sn)

	match topology:
		Topology.CHAIN:
			for i in range(node_count - 1):
				fx.graph.add_edge(fx.nodes[i], fx.nodes[i + 1])
		Topology.TREE:
			for i in range(1, node_count):
				var parent_idx: int = (i - 1) / branching_factor
				fx.graph.add_edge(fx.nodes[parent_idx], fx.nodes[i])

	fx.alloc.force_allocate(fx.entity, fx.nodes[0])
	fx.entity.core_location = fx.nodes[0]
	fx.owned_nodes.append(fx.nodes[0])
	for i in range(1, mini(wanted, node_count)):
		fx.alloc.force_allocate(fx.entity, fx.nodes[i])
		fx.owned_nodes.append(fx.nodes[i])

	return fx


## Owned-node count actually reached — counted from what was actually
## force_allocated, never derived back out of `skill_points.value` (see the
## `owned_nodes` field doc).
func owned_count() -> int:
	return owned_nodes.size()


func core_node() -> SkillNode:
	return nodes[0] if not nodes.is_empty() else null


## Simulate `count` real turn-start upkeeps (`Entity._on_turn_started`) — pool
## replenishment, node regen, class aura, all through the production code path.
func run_turns(count: int) -> void:
	for _i in range(count):
		entity._on_turn_started(entity)
