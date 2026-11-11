extends GutTest

## #1797 — [OutcomeApplier] drains an open worklist ([HitQueue]).
##
## The properties pinned here:
##   1. a hit pushed while the queue drains lands after its pusher, after every
##      unlanded hit of its own `schedule_index`, before the first of a greater
##      one, and never ahead of the cursor; it ends up in the outcome's `hits`
##   2. the crit stream is drawn in exactly that land order
##   3. a spell-style un-awaited instant drain and `apply` on an instant clock
##      land the same hits in the same order
## Nothing in production pushes yet (#1798's gather is the first pusher), so
## the pusher here is a test-local hit.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SEED := 1797
const _CRIT_CHANCE := 0.5


## A TRUE-typed damage hit that logs itself as it lands and, when handed a
## queue and a hit, pushes that hit onto the queue from inside its landing.
class _Logged extends DamageInstance:
	var label: String = ""
	var log: Array = []
	var queue: HitQueue = null
	var pushed: HitInstance = null

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		log.append(label)
		super(node, world)
		if queue != null and pushed != null:
			queue.push(pushed)


var _graph: Graph
var _owner: Entity
var _attacker: Entity
var _nodes: Array[SkillNode] = []
var _log: Array = []


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_owner = Entity.new()
	_owner.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_owner)
	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.get_stat(&"crit_chance").base_value = _CRIT_CHANCE
	_graph.add_child(_attacker)
	await get_tree().process_frame
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		_graph.add_skill_node(sn)
		sn.owned_by = _owner
		_nodes.append(sn)
	await get_tree().process_frame
	_log = []


func _hit(label: String, target: SkillNode, schedule_index: int) -> _Logged:
	var h := _Logged.new()
	h.label = label
	h.log = _log
	h.target = target
	h.attacker = _attacker
	h.amount = 0.1
	h.type = DamageInstance.Type.TRUE
	h.schedule_index = schedule_index
	h.structural_key = float(schedule_index)
	return h


func _crit_tiers(order: Array) -> Array:
	var ref := RandomNumberGenerator.new()
	ref.seed = _SEED
	var tiers: Array = []
	for _h in order:
		tiers.append(1 if ref.randf() < _CRIT_CHANCE else 0)
	return tiers


## Group 0 holds a, the pusher p and its sibling s; p pushes x at its own
## index 0. Group 1's b pushes y at index 0 — an index the drain has already
## passed. Expected: x after the sibling s and before b; y right after b
## (never ahead of the cursor) and before c.
func test_a_pushed_hit_lands_in_the_unlanded_tail_by_schedule_order() -> void:
	var a := _hit("a", _nodes[0], 0)
	var p := _hit("p", _nodes[1], 0)
	var s := _hit("s", _nodes[2], 0)
	var b := _hit("b", _nodes[0], 1)
	var c := _hit("c", _nodes[1], 2)
	var x := _hit("x", _nodes[2], 0)
	var y := _hit("y", _nodes[1], 0)
	var outcome := AttackOutcome.new()
	for h in [a, p, s, b, c]:
		outcome.hits.append(h)
	var queue := HitQueue.over(outcome.hits)
	p.queue = queue
	p.pushed = x
	b.queue = queue
	b.pushed = y
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED
	await OutcomeApplier.drain(queue, CombatWorld.live(), BeatClock.instant_clock(), null, rng)

	assert_eq(_log, ["a", "p", "s", "x", "b", "y", "c"],
			"a pushed hit lands after its group's unlanded hits, before the next group, never before the cursor")
	assert_true(outcome.hits.has(x) and outcome.hits.has(y),
			"every pushed hit is in the outcome's record")
	assert_eq(outcome.hits.size(), 7, "the record holds every hit that landed, once")

	var landed: Array = [a, p, s, x, b, y, c]
	var expected := _crit_tiers(landed)
	# The seed must tell this order from "pushed hits land last", or the crit
	# assert below could not fail.
	assert_ne(expected,
			_reorder(_crit_tiers([a, p, s, b, c, x, y]), [a, p, s, b, c, x, y], landed),
			"the seed discriminates the land order from append order")
	assert_eq(landed.map(func(h: HitInstance) -> int: return h.crit_tier), expected,
			"the crit stream is drawn in land order")


## [param tiers] were drawn in [param drawn] order; read them back in [param order].
func _reorder(tiers: Array, drawn: Array, order: Array) -> Array:
	var out: Array = []
	for h in order:
		out.append(tiers[drawn.find(h)])
	return out


func _twin_outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	# Appended out of land order, with a tie, so the order is the queue's work.
	for spec in [["c", 2.0], ["a", 0.0], ["b1", 1.0], ["b2", 1.0], ["a2", 0.0]]:
		var h := _hit(spec[0], _nodes[0], -1)
		h.attacker = null
		h.structural_key = spec[1]
		outcome.hits.append(h)
	outcome.schedule = OutcomeSchedule.compile(outcome)
	return outcome


func test_an_instant_drain_and_apply_land_in_the_same_order() -> void:
	OutcomeApplier.apply(_twin_outcome(), CombatWorld.live(), BeatClock.instant_clock())
	var applied := _log.duplicate()
	_log.clear()
	var wave := _twin_outcome()
	# Spell-style: un-awaited, so the drain must finish before this returns.
	OutcomeApplier.drain(HitQueue.over(wave.hits), CombatWorld.live(), BeatClock.instant_clock())
	assert_eq(applied, ["a", "a2", "b1", "b2", "c"], "apply lands in schedule order")
	assert_eq(_log, applied, "the un-awaited instant drain lands the same order, synchronously")
