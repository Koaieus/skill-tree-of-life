extends GutTest

## Marker arrows (`docs/design/aspect_matrix.md` § Arrow faces): a typed arrow
## that flies EARLY in the volley (low `AmmoType.order`) and changes how every
## arrow behind it lands. A volley lands in `order`, and each landing reads the
## target's live slice, so a marker's rider already sits on the node when the
## base arrows behind it hit — no plumbing beyond the volley order itself.
##
## One case per marker; each compares a marked volley against the same volley
## without the marker, through the shared fixture and [method _base_hits].
## The tests pin the payoff as behaviour, never a type's tuning numbers.
##
## Fixture: hub `_mid`(200,0) with three reaching leaves around a hostile
## target (450,0); raw damage far under the target's armor, so every base arrow
## lands on the floor `min_damage_taken`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

const _ARROW := &"arrow"
const _CURSE := &"curse"
const _HEX := &"hex"

## Small against the default flat-board node HP (10): a 4-arrow volley on the
## floor must leave the target alive, or the later arrows land on nothing.
## Reached by an ADD_BASE so a marker's own ADD_BASE stacks on top — a SET
## would override it.
const _FLOOR := 1.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _mid: SkillNode
var _target: SkillNode


func _set_stat(node: SkillNode, id: StringName, value: float,
		op: StatModifier.Operation = StatModifier.Operation.SET) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	node.add_local_modifier(m)


func _leaf(pos: Vector2) -> SkillNode:
	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = pos
	_graph.add_skill_node(leaf)
	_graph.add_edge(leaf, _mid)
	return leaf


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_mid = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_mid.position = Vector2(200, 0)
	_graph.add_skill_node(_mid)
	var leaves: Array[SkillNode] = [
		_leaf(Vector2(400, 0)), _leaf(Vector2(450, 150)), _leaf(Vector2(450, -300))]
	_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_target.position = Vector2(450, 0)
	_graph.add_skill_node(_target)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = TestBoards.flat_entity_board()
	_graph.entities_container.add_child(_attacker)
	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = TestBoards.flat_entity_board()
	_graph.entities_container.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _mid)
	for leaf in leaves:
		_alloc.force_allocate(_attacker, leaf)
	_alloc.force_allocate(_hostile, _target)
	autofree(_attacker)
	autofree(_hostile)

	for leaf in leaves:
		_set_stat(leaf, &"range", 1000.0)
		_set_stat(leaf, &"ranged_damage", 3.0)
	_set_stat(_target, &"armor", 100.0)
	_set_stat(_target, &"min_damage_taken",
			_FLOOR - _target.get_local_value(&"min_damage_taken"), StatModifier.Operation.ADD_BASE)


## Resolves one volley of [param counts] (ammo id → arrows) at the target.
func _volley(counts: Dictionary) -> AttackOutcome:
	for id in counts:
		_attacker.stat_board.arrows.add(id, counts[id])
	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	p.set_target(_target)
	p.ammo_counts = counts
	return p.resolve()


## [method _volley] resolved against [param world], a shadow the caller keeps
## alive, so the landed riders stay readable after the resolve.
func _volley_in(counts: Dictionary, world: CombatWorld) -> AttackOutcome:
	for id in counts:
		_attacker.stat_board.arrows.add(id, counts[id])
	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	p.set_target(_target)
	p.ammo_counts = counts
	return p.resolve_against(world)


## Every hit of the volley, in land order.
func _landed(outcome: AttackOutcome) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if not hit is ExertInstance:
			out.append(hit)
	out.sort_custom(func(a: HitInstance, b: HitInstance) -> bool:
		return a.structural_key < b.structural_key)
	return out


## The base arrows' DAMAGE landings, in land order.
func _base_hits(outcome: AttackOutcome) -> Array[HitInstance]:
	return _landed(outcome).filter(func(h: HitInstance) -> bool:
		return h.kind == HitInstance.Kind.DAMAGE and h.ammo_type_id == _ARROW)


## Σ power of [param status_id] riders landed strictly before [param hit].
func _stacks_before(outcome: AttackOutcome, hit: HitInstance, status_id: StringName) -> float:
	var total := 0.0
	for h in _landed(outcome):
		if h.structural_key >= hit.structural_key:
			break
		if h is StatusInstance and (h as StatusInstance).def.id == status_id:
			total += (h as StatusInstance).power
	return total


func test_curse_marker_lifts_the_floor_for_every_base_arrow_behind_it() -> void:
	assert_eq(_target.get_local_value(&"min_damage_taken"), _FLOOR, "fixture floor")
	var plain := _base_hits(_volley({_ARROW: 3}))
	_attacker.stat_board.arrows.take(_ARROW, _attacker.stat_board.arrows.total_stock())
	var marked_outcome := _volley({_CURSE: 1, _ARROW: 3})
	var marked := _base_hits(marked_outcome)
	assert_eq(plain.size(), 3, "the plain volley lands three base arrows")
	assert_eq(marked.size(), 3, "the marked volley lands three base arrows")
	for i in plain.size():
		var stacks := _stacks_before(marked_outcome, marked[i], _CURSE)
		assert_gt(stacks, 0.0, "base arrow %d lands after the curse rider" % i)
		assert_true(marked[i].effective_amount >= _FLOOR + stacks,
			"base arrow %d deals at least the raised floor (%s + %s), dealt %s"
			% [i, _FLOOR, stacks, marked[i].effective_amount])
		assert_gt(marked[i].effective_amount, plain[i].effective_amount,
			"base arrow %d hits harder behind the marker than without it" % i)


func test_hex_marker_raises_the_crit_chance_of_every_base_arrow_behind_it() -> void:
	var plain_world := CombatWorld.shadow()
	var plain := _base_hits(_volley_in({_ARROW: 3}, plain_world))
	_attacker.stat_board.arrows.take(_ARROW, _attacker.stat_board.arrows.total_stock())
	var marked_world := CombatWorld.shadow()
	var marked_outcome := _volley_in({_HEX: 1, _ARROW: 3}, marked_world)
	var marked := _base_hits(marked_outcome)
	assert_eq(plain.size(), 3, "the plain volley lands three base arrows")
	assert_eq(marked.size(), 3, "the marked volley lands three base arrows")
	var behind := 0
	for i in mini(plain.size(), marked.size()):
		if _stacks_before(marked_outcome, marked[i], _HEX) <= 0.0:
			continue
		behind += 1
		assert_gt(CritRoll.chance_for(marked[i], marked_world),
			CritRoll.chance_for(plain[i], plain_world),
			"base arrow %d reads a higher crit chance behind the hex marker" % i)
	assert_eq(behind, 3, "every base arrow lands after the hex rider")
	plain_world.free_shadow()
	marked_world.free_shadow()
