extends GutTest

## The round-trip guard for [AttackRecord] (#1000): a hand-built
## [AttackOutcome] survives `capture -> rebuild -> capture` with every wire key
## present, equal in value AND Variant type, every rebuilt hit carrying the
## captured fields, and the timeline's hit ALIASING restored (an event's hit
## IS an entry of the flat list). Mechanism-independent: it pins the record's
## agreement with itself whatever `capture` / `rebuild` are built on, so a key
## swapped, dropped or mistyped on either side is red here rather than a silent
## default on a peer.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := "res://effects/status/poison.tres"

var _graph: Graph
var _nodes: Array[SkillNode] = []
var _attacker: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes.clear()
	for i in 5:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = "n%d" % i
		_graph.add_skill_node(node)
		node.global_position = Vector2(i * 100, 0)
		_nodes.append(node)
	for i in 4:
		_graph.add_edge(_nodes[i], _nodes[i + 1])
	_attacker = Entity.new()
	_attacker.display_name = "Attacker"
	_graph.entities_container.add_child(_attacker)
	await get_tree().process_frame
	assert_gt(_attacker.entity_id, 0, "entity_id mints on entry to entities_container")


func _dealloc(node: SkillNode, level: int, wound: int, chip: float,
		labels: PackedStringArray) -> DeallocEntry:
	var e := DeallocEntry.new()
	e.node = node
	e.node_id = _graph.get_stable_id(node)
	e.allocation_level = level
	e.wound = wound
	e.chip = chip
	e.revoked_labels = labels
	return e


func _fill(hit: HitInstance, target: SkillNode, origin: SkillNode, amount: float,
		key: float, crit_tier: int) -> HitInstance:
	hit.target = target
	hit.origin = origin
	hit.attacker = _attacker
	hit.effective_amount = amount
	hit.amount = amount
	hit.structural_key = key
	hit.is_crit = crit_tier > 0
	hit.crit_tier = crit_tier
	hit.hp_before = amount * 3.0
	hit.hp_after = amount * 2.0
	hit.hp_max = amount * 4.0
	return hit


## One of everything the record encodes: three hit kinds, a gated landing, a
## popped vertex, a cascade with and without labels, a ragged predecessor set
## and an event that aliases two hits.
func _build_outcome() -> AttackOutcome:
	var o := AttackOutcome.new()
	o.resolve_seed = 987654321
	o.ap_cost = 2
	o.mana_cost = 7
	o.cadence = ScheduleEntry.Cadence.BEAT

	var dmg := _fill(DamageInstance.new(), _nodes[1], _nodes[0], 12.5, 1.0, 2) as DamageInstance
	dmg.popped_vertex = _nodes[4]
	dmg.deallocations = [
		_dealloc(_nodes[2], 3, 1, 0.25, PackedStringArray(["+5 STR", "regen"])),
		_dealloc(_nodes[3], 1, 0, 0.0, PackedStringArray()),
	]
	var heal := _fill(HealInstance.new(), _nodes[2], _nodes[1], 4.0, 2.0, 0)
	var status := _fill(StatusInstance.new(), _nodes[3], _nodes[2], 1.5, 3.0, 0) as StatusInstance
	status.def = load(_POISON) as StatusDef
	status.host_kind = StatusInstance.HostKind.ENTITY
	var gated := _fill(DamageInstance.new(), _nodes[4], _nodes[3], 9.0, 4.0, 0)
	gated.gated = true
	o.hits.assign([dmg, heal, status, gated])

	var e0 := PropagationEvent.new()
	e0.beat = 0
	e0.verb = PropagationEvent.Verb.EDGE
	e0.origin = _nodes[0]
	e0.target = _nodes[1]
	e0.predecessor = null
	e0.visit_index = 0
	e0.hits.assign([dmg, heal])
	var e1 := PropagationEvent.new()
	e1.beat = 1
	e1.verb = PropagationEvent.Verb.CANCEL
	e1.origin = _nodes[1]
	e1.target = _nodes[3]
	e1.predecessor = _nodes[0]
	e1.predecessors.assign([_nodes[0], _nodes[2]])
	e1.visit_index = 2
	e1.is_terminal = true
	e1.hits.assign([status])
	o.timeline.assign([e0, e1])
	return o


func test_capture_survives_a_rebuild_key_for_key_and_type_for_type() -> void:
	var outcome := _build_outcome()
	var first := AttackRecord.capture(outcome, _graph)
	var rebuilt := AttackRecord.rebuild(first, _graph)
	var second := AttackRecord.capture(rebuilt, _graph)
	assert_gt(first.size(), 30, "a capture holds every wire key")
	for key in first.keys():
		assert_true(second.has(key), "rebuild -> capture keeps key %s" % key)
		assert_eq(typeof(second.get(key)), typeof(first[key]), "%s Variant type" % key)
		assert_eq(second.get(key), first[key], "%s value" % key)
	for key in second.keys():
		assert_true(first.has(key), "a re-capture invents no key (%s)" % key)


func test_every_captured_hit_field_comes_back_on_the_rebuilt_hit() -> void:
	var outcome := _build_outcome()
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _graph), _graph)
	assert_eq(rebuilt.resolve_seed, outcome.resolve_seed, "seed")
	assert_eq(rebuilt.ap_cost, outcome.ap_cost, "ap")
	assert_eq(rebuilt.mana_cost, outcome.mana_cost, "mana")
	assert_eq(rebuilt.cadence, outcome.cadence, "cadence")
	assert_eq(rebuilt.hits.size(), outcome.hits.size(), "hit count")
	for i in mini(rebuilt.hits.size(), outcome.hits.size()):
		var a := outcome.hits[i]
		var b := rebuilt.hits[i]
		var at := "hit[%d]." % i
		assert_eq(b.kind, a.kind, at + "kind")
		assert_eq(b.effective_amount, a.effective_amount, at + "effective_amount")
		assert_true(is_same(b.target, a.target), at + "target")
		assert_true(is_same(b.origin, a.origin), at + "origin")
		assert_true(is_same(b.attacker, a.attacker), at + "attacker")
		assert_eq(b.structural_key, a.structural_key, at + "structural_key")
		assert_eq(b.gated, a.gated, at + "gated")
		assert_eq(b.is_crit, a.is_crit, at + "is_crit")
		assert_eq(b.crit_tier, a.crit_tier, at + "crit_tier")
		assert_eq(b.hp_before, a.hp_before, at + "hp_before")
		assert_eq(b.hp_after, a.hp_after, at + "hp_after")
		assert_eq(b.hp_max, a.hp_max, at + "hp_max")
		assert_true(is_same(b.popped_vertex, a.popped_vertex), at + "popped_vertex")
		assert_eq(b.deallocations.size(), a.deallocations.size(), at + "deallocations")
		for k in mini(b.deallocations.size(), a.deallocations.size()):
			var da := a.deallocations[k]
			var db := b.deallocations[k]
			var dat := at + "dealloc[%d]." % k
			assert_true(is_same(db.node, da.node), dat + "node")
			assert_eq(db.node_id, da.node_id, dat + "node_id")
			assert_eq(db.allocation_level, da.allocation_level, dat + "allocation_level")
			assert_eq(db.wound, da.wound, dat + "wound")
			assert_eq(db.chip, da.chip, dat + "chip")
			assert_eq(db.revoked_labels, da.revoked_labels, dat + "revoked_labels")
	var status := rebuilt.hits[2] as StatusInstance
	assert_not_null(status, "a STATUS hit rebuilds as a StatusInstance")
	if status != null:
		assert_eq(status.def.resource_path, _POISON, "status def path")
		assert_eq(status.host_kind, StatusInstance.HostKind.ENTITY, "status host")
		assert_true(status.power_resolved, "a replayed status lands flat")
	assert_eq(rebuilt.hits[3].amount, 0.0, "a gated landing rebuilds as a dud")


func test_the_timeline_rebuilds_with_its_aliasing() -> void:
	var outcome := _build_outcome()
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _graph), _graph)
	assert_eq(rebuilt.timeline.size(), outcome.timeline.size(), "event count")
	for i in mini(rebuilt.timeline.size(), outcome.timeline.size()):
		var a := outcome.timeline[i]
		var b := rebuilt.timeline[i]
		var at := "event[%d]." % i
		assert_eq(b.beat, a.beat, at + "beat")
		assert_eq(b.verb, a.verb, at + "verb")
		assert_eq(b.visit_index, a.visit_index, at + "visit_index")
		assert_eq(b.is_terminal, a.is_terminal, at + "is_terminal")
		assert_true(is_same(b.origin, a.origin), at + "origin")
		assert_true(is_same(b.target, a.target), at + "target")
		assert_true(is_same(b.predecessor, a.predecessor), at + "predecessor")
		assert_eq(b.predecessors, a.predecessors, at + "predecessors")
		assert_eq(b.hits.size(), a.hits.size(), at + "hits")
		for k in mini(b.hits.size(), a.hits.size()):
			var index := outcome.hits.find(a.hits[k])
			assert_true(is_same(b.hits[k], rebuilt.hits[index]),
					at + "hits[%d] IS flat hit %d, not a copy" % [k, index])
	assert_true(rebuilt.schedule != null, "rebuild compiles a schedule")
