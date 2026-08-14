extends GutTest

## #206 widened — the two-stage spell-grant distribution in
## GraphProcgenSpellGrants: a Poisson roll per pool entry (floored at 1,
## guaranteeing every spell in the pool appears at least once), then placed
## on distinct INT-archetype nodes. Pure-logic tests against the static
## helper directly — no full GraphProcgen.generate() needed.

func _mk_pool(entries: Array) -> SpellGrantPool:
	var pool := SpellGrantPool.new()
	var typed: Array[SpellGrantPoolEntry] = []
	for e in entries:
		typed.append(e)
	pool.entries = typed
	return pool


func _mk_entry(spell_name: String, weight: float = 1.0) -> SpellGrantPoolEntry:
	var e := SpellGrantPoolEntry.new()
	var s := SpellDef.new()
	s.name = spell_name
	e.spell_def = s
	e.weight = weight
	return e


func _mk_nodes(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		var n := SkillNode.new()
		autofree(n)
		n.name = "N%d" % i
		out.append(n)
	return out


func _spell_names_on(node: SkillNode) -> Array[String]:
	var out: Array[String] = []
	for e in node.effects:
		if e is SpellGrant and e.spell_def != null:
			out.append(e.spell_def.name)
	return out


## Acceptance #1: every pool entry lands on the level, even a low-weight one.
func test_every_pool_entry_gets_at_least_one_copy() -> void:
	var pool := _mk_pool([
		_mk_entry("Common", 100.0),
		_mk_entry("Rare", 0.001),
	])
	var nodes := _mk_nodes(20)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	GraphProcgenSpellGrants.distribute(nodes, pool, 1.0, rng)

	var all_names: Array[String] = []
	for n in nodes:
		all_names.append_array(_spell_names_on(n))
	assert_true(all_names.has("Common"), "high-weight spell present")
	assert_true(all_names.has("Rare"), "low-weight spell still guaranteed at least once")


## Acceptance #2: a spell's own copies never repeat a node.
func test_same_spell_never_placed_twice_on_one_node() -> void:
	var pool := _mk_pool([_mk_entry("Bolt", 1.0)])
	var nodes := _mk_nodes(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2

	GraphProcgenSpellGrants.distribute(nodes, pool, 1.0, rng)

	for n in nodes:
		var count := 0
		for name in _spell_names_on(n):
			if name == "Bolt":
				count += 1
		assert_true(count <= 1, "%s carries at most one copy of the same spell" % n.name)


## Acceptance #3: a spell's placement count is clamped to the eligible pool
## size — it can never exceed the number of nodes available.
func test_placement_clamped_to_node_count() -> void:
	var pool := _mk_pool([_mk_entry("Overrepresented", 1000.0)])
	var nodes := _mk_nodes(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	GraphProcgenSpellGrants.distribute(nodes, pool, 5.0, rng)

	var total := 0
	for n in nodes:
		total += _spell_names_on(n).size()
	assert_true(total <= 3, "can't place more copies than there are nodes")


## Acceptance #4: no-ops cleanly — unset pool, zero ratio, no nodes.
func test_noops_on_empty_inputs() -> void:
	var pool := _mk_pool([_mk_entry("Bolt", 1.0)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4

	var nodes_a := _mk_nodes(3)
	GraphProcgenSpellGrants.distribute(nodes_a, null, 1.0, rng)
	for n in nodes_a:
		assert_true(_spell_names_on(n).is_empty(), "null pool → nothing placed")

	var nodes_b := _mk_nodes(3)
	GraphProcgenSpellGrants.distribute(nodes_b, pool, 0.0, rng)
	for n in nodes_b:
		assert_true(_spell_names_on(n).is_empty(), "zero ratio → nothing placed")

	var empty_nodes: Array[SkillNode] = []
	GraphProcgenSpellGrants.distribute(empty_nodes, pool, 1.0, rng)  # must not crash


## Acceptance #5: is_eligible_node gates on the INT primary stat only.
func test_is_eligible_node_gates_on_intelligence() -> void:
	assert_true(GraphProcgenSpellGrants.is_eligible_node(&"intelligence"))
	assert_false(GraphProcgenSpellGrants.is_eligible_node(&"strength"))
	assert_false(GraphProcgenSpellGrants.is_eligible_node(&""))
