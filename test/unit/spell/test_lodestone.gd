extends GutTest

## Lodestone end to end: the haul's arithmetic (pass-all plus load, Greed's ×2
## the only multiplier), conservation without Greed, the owner's diamond split,
## the rider gate, and a record replay landing the same stacks.

const LODESTONE: SpellDef = preload("res://attack/spell/defs/lodestone.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _GREED := preload("res://effects/status/greed.tres")
const _POISON_ID := preload("res://identity/defs/poison.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## Seed 1, a binary tree to depth 3: node i's children are 2i and 2i+1 (1..15).
static func _fan2() -> Array:
	var adj: Array = [[0, 1]]
	for i in range(1, 8):
		adj.append([i, 2 * i])
		adj.append([i, 2 * i + 1])
	return adj


# T=1 → A2, B3, C4; A→D5, B→E6, C→E6; D→F7, E→F7.
const DIAMOND := [[0, 1], [1, 2], [1, 3], [1, 4], [2, 5], [3, 6], [4, 6], [5, 7], [6, 7]]


## Lodestone with its Greed row swapped for [param intakes] (fresh rows: the
## shipped .tres's own are never touched).
func _variant(intakes: Dictionary) -> SpellDef:
	var spell := LODESTONE.duplicate() as SpellDef
	var rows: Array[AspectIntake] = []
	for identity: Identity in intakes:
		var row := AspectIntake.new()
		row.identity = identity
		row.innate = intakes[identity]
		rows.append(row)
	spell.intakes = rows
	return spell


## 0 (attacker) → the tree in [param adj]; the defender owns every other node,
## each holding [param poison] stacks. Resolves on a kept shadow.
func _cast(adj: Array, poison: float, spell: SpellDef = LODESTONE) -> Dictionary:
	var graph := h.make_graph(adj, self)
	var n := graph.get_skill_nodes()
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	var owned: Array = []
	for i in range(1, n.size()):
		owned.append(i)
	h.assign_owner(graph, def, owned)
	h.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if poison > 0.0:
		for i in range(1, n.size()):
			CombatWorld.live().combat_for(n[i]).apply_status(_POISON, poison)
	var shadow := CombatWorld.shadow()
	var outcome := SpellResolver.resolve_against(spell, n[1], n[0], atk, graph, shadow)
	return {n = n, graph = graph, shadow = shadow, outcome = outcome}


func _stacks(world: CombatWorld, node: SkillNode, d: StatusDef) -> int:
	return roundi(world.combat_for(node).get_status_power(d.id))


func _column(r: Dictionary, d: StatusDef, world: CombatWorld = null) -> Array:
	var w: CombatWorld = world if world != null else r.shadow
	var out: Array = []
	for i in range(1, (r.n as Array).size()):
		out.append(_stacks(w, r.n[i], d))
	return out


func _sum(xs: Array) -> int:
	var t := 0
	for x: int in xs:
		t += x
	return t


func _raw_hauls(r: Dictionary) -> Dictionary:
	var out := {}
	for hit in (r.outcome as AttackOutcome).hits:
		var s := hit as StatusInstance
		if s != null and s.raw and s.def.id == &"poison":
			var i: int = (r.n as Array).find(s.target)
			out[i] = out.get(i, []) + [roundi(s.power)]
	return out


func test_lodestone_is_catalogued() -> void:
	assert_has(SpellCatalog.ALL, LODESTONE)


func test_haul_arithmetic_with_greed_doubling_every_ring() -> void:
	var r := _cast(_fan2(), 1.0)
	var poison := _column(r, _POISON)
	var greed := _column(r, _GREED)
	assert_eq(poison[0], 85, "the seed lands 84 on its 1 poison")
	assert_eq(greed[0], 64, "the seed lands 64 Greed, its own stack spent")
	assert_eq(poison.slice(1), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "every other node hauled clean")
	assert_eq(greed.slice(1), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	r.shadow.free_shadow()


func test_no_greed_infused_poison_conserves_the_return() -> void:
	var r := _cast(_fan2(), 1.0, _variant({_POISON_ID: 1}))
	var poison := _column(r, _POISON)
	assert_eq(poison[0], 16, "nothing doubles: the seed lands 7 + 7 on its 2")
	assert_eq(poison.slice(1), [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], "every other node keeps 1")
	assert_eq(_sum(poison), 15 * 2, "the return conserves what the outbound left")
	r.shadow.free_shadow()


func test_owners_diamond_splits_by_trails_and_conserves() -> void:
	var r := _cast(DIAMOND, 0.0, _variant({_POISON_ID: 6}))
	var hauls := _raw_hauls(r)
	assert_eq(hauls.get(5, []), [2], "F's 6 splits D:E = 1:2")
	assert_eq(hauls.get(6, []), [4])
	assert_eq(hauls.get(3, []), [5], "E's 4 + 6 splits B:C evenly")
	assert_eq(hauls.get(4, []), [5])
	assert_eq(hauls.get(2, []), [8])
	assert_eq(hauls.get(1, []), [36])
	var poison := _column(r, _POISON)
	assert_eq(poison, [42, 0, 0, 0, 0, 0, 0], "everything ends on T")
	assert_eq(_sum(poison), 7 * 6, "with no Greed, total poison is conserved")
	r.shadow.free_shadow()


func test_wait_and_back_landings_plant_no_greed() -> void:
	var r := _cast(_fan2(), 1.0)
	var planted := {}
	for hit in (r.outcome as AttackOutcome).hits:
		var s := hit as StatusInstance
		if s != null and s.def.id == &"greed" and not s.raw:
			planted[s.target] = planted.get(s.target, 0) + 1
	assert_eq(planted.size(), 15, "every hostile node gets its rider")
	assert_true(planted.values().all(func(c: int) -> bool: return c == 1),
			"once — on its OUT landing, never on WAIT or BACK")
	r.shadow.free_shadow()


func test_the_record_replays_to_the_same_stacks() -> void:
	var r := _cast(_fan2(), 1.0)
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(r.outcome, r.graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, r.graph), CombatWorld.live())
	var live := CombatWorld.live()
	assert_eq(_column(r, _POISON, live), _column(r, _POISON), "poison lands where the shadow said")
	assert_eq(_column(r, _GREED, live), _column(r, _GREED), "Greed spends once per haul on replay too")
	assert_eq(_column(r, _POISON, live)[0], 85)
	r.shadow.free_shadow()
