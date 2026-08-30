extends GutTest

## #504 design B — the world mutates on the reveal clock.
##
## [OutcomeApplier] walks hits in `arrival_time` order and lands each one AT
## its `arrival_time`, on a [BeatClock] it owns. This is the acceptance the
## headless suite can judge; the one it cannot is whether the health bar,
## shatter, fog and damage numbers visibly move together, which needs a real
## frame (see the issue).
##
## The three properties pinned here:
##   1. an instant clock lands everything synchronously (the drain / test mode)
##   2. a real clock lands each hit at its own beat, in order
##   3. draining mid-window lands the REMAINDER — design B's one real risk is a
##      loop interrupted partway leaving hits permanently unapplied

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _owner: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_owner = Entity.new()
	_owner.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_owner)
	await get_tree().process_frame
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		_graph.add_skill_node(sn)
		sn.owned_by = _owner
		_nodes.append(sn)
	await get_tree().process_frame


## A TRUE-typed DamageInstance: `Mitigation.apply` returns the raw amount
## unchanged for TRUE, so the fixture's HP arithmetic is exact rather than
## armour-dependent (see `.claude/rules/turn-manager.md`).
## #543: the fixture authors a STRUCTURAL key, and the applier compiles it
## into seconds. These outcomes carry the default
## [constant ScheduleEntry.Cadence.LITERAL], where the key IS the second — so
## every number below still means exactly what it did when it was written
## straight into `arrival_time`, but it now travels the production route
## (compile, then wait) instead of bypassing it.
func _hit(target: SkillNode, amount: float, arrival_time: float) -> DamageInstance:
	var d := DamageInstance.new()
	d.target = target
	d.amount = amount
	d.type = DamageInstance.Type.TRUE
	d.structural_key = arrival_time
	return d


func _outcome(hits: Array[DamageInstance]) -> AttackOutcome:
	var o := AttackOutcome.new()
	for h in hits:
		o.hits.append(h)
	return o


func test_instant_clock_lands_every_hit_synchronously() -> void:
	var before: Array[float] = []
	for sn in _nodes:
		before.append(sn.get_current_hp())
	var outcome := _outcome([
		_hit(_nodes[0], 3.0, 0.0),
		_hit(_nodes[1], 3.0, 0.5),
		_hit(_nodes[2], 3.0, 1.0),
	])
	# Not awaited: with an instant clock the applier never parks, which is what
	# keeps tests that read world state on the line after `launch_attack`
	# working unmodified.
	OutcomeApplier.apply(outcome, CombatWorld.live(), BeatClock.instant_clock())
	for i in 3:
		assert_almost_eq(_nodes[i].get_current_hp(), before[i] - 3.0, 0.001,
				"hit %d must have landed with no waiting" % i)


func test_real_clock_lands_each_hit_at_its_own_arrival_time() -> void:
	var landed: Array[SkillNode] = []
	var handler := func(node: SkillNode, _amount: float, _source: Variant) -> void:
		landed.append(node)
	Events.skill_node_damaged.connect(handler)

	var outcome := _outcome([
		_hit(_nodes[0], 3.0, 0.0),
		_hit(_nodes[1], 3.0, 0.15),
		_hit(_nodes[2], 3.0, 0.30),
	])
	OutcomeApplier.apply(outcome, CombatWorld.live(), BeatClock.for_tree(get_tree()))

	assert_eq(landed.size(), 1, "only the t=0 hit lands before any waiting")
	await get_tree().create_timer(0.20).timeout
	assert_eq(landed.size(), 2, "the 0.15s hit has landed; the 0.30s one has not")
	await get_tree().create_timer(0.25).timeout
	Events.skill_node_damaged.disconnect(handler)
	assert_eq(landed, _nodes, "all three landed, in arrival order")


## Ordering is authored, never emergent: a hit appended LAST but arriving
## FIRST must land first. This is the half of #499 that stops allocation order
## leaking into combat outcome, now also observable as beat order.
func test_hits_land_in_arrival_order_not_append_order() -> void:
	var landed: Array[SkillNode] = []
	var handler := func(node: SkillNode, _amount: float, _source: Variant) -> void:
		landed.append(node)
	Events.skill_node_damaged.connect(handler)

	var outcome := _outcome([
		_hit(_nodes[2], 3.0, 0.30),
		_hit(_nodes[0], 3.0, 0.0),
		_hit(_nodes[1], 3.0, 0.15),
	])
	OutcomeApplier.apply(outcome, CombatWorld.live(), BeatClock.for_tree(get_tree()))
	await get_tree().create_timer(0.45).timeout
	Events.skill_node_damaged.disconnect(handler)
	assert_eq(landed, _nodes, "arrival order wins over append order")


## The drain. An attack's mutation is spread over real time, so an interrupted
## window would strand every hit that had not landed — a world that is valid
## but permanently wrong. `BeatClock.drain()` releases the parked loop and
## makes the remainder synchronous.
func test_draining_mid_window_lands_the_remaining_hits() -> void:
	var before: Array[float] = []
	for sn in _nodes:
		before.append(sn.get_current_hp())
	var clock := BeatClock.for_tree(get_tree())
	var outcome := _outcome([
		_hit(_nodes[0], 3.0, 0.0),
		_hit(_nodes[1], 3.0, 10.0),
		_hit(_nodes[2], 3.0, 20.0),
	])
	OutcomeApplier.apply(outcome, CombatWorld.live(), clock)
	assert_almost_eq(_nodes[1].get_current_hp(), before[1], 0.001,
			"precondition: the 10s hit is still pending")

	# Synchronous by design — the parked loop resumes inside this call, which
	# is what makes it usable from `_exit_tree` while the nodes are still alive.
	clock.drain()

	for i in 3:
		assert_almost_eq(_nodes[i].get_current_hp(), before[i] - 3.0, 0.001,
				"hit %d must have landed on the drain" % i)


func test_drain_is_idempotent_and_safe_with_nothing_pending() -> void:
	var clock := BeatClock.instant_clock()
	clock.drain()
	clock.drain()
	assert_true(clock.instant, "an already-instant clock stays instant")
