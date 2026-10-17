extends GutTest

## #1654 acceptance 3 — a faced Dormant Core's kill offers its count grant in
## round 1 every time ([member StatModifier.loot_pinned]); the tier scale never
## touches a MULTIPLY/SET leaf.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://entity/blocker/faces/poison_face.tres")


func _factory() -> EntityFactory:
	var graph := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var factory := EntityFactory.new()
	autofree(factory)
	factory.graph = graph
	factory.allocation_system = alloc
	return factory


func test_faced_kill_offers_its_count_in_round_one_every_time() -> void:
	var factory := _factory()
	var victim := factory.spawn_blocker(EntityFactory.BlockerSize.MEDIUM, null,
			[], 0, 0.0, 0, 1, 0.25, _POISON, 9)
	var collector := factory.spawn_blocker(EntityFactory.BlockerSize.SMALL, null)
	var loot := LootSystem.new()
	autofree(loot)
	var hits := 0
	for s in 50:
		seed(s)
		var draw := loot._draw_payload(victim)
		var dust := SkillDustAddon.new()
		autofree(dust)
		dust.candidates.assign(draw["candidates"])
		dust.weights.assign(draw["weights"])
		dust.rounds = int(draw["rounds"])
		dust.begin_claim(collector)
		for m in dust.offers_for(SkillDustAddon.Phase.STAT):
			if (m as StatModifier).stat_id == &"poison_aspect":
				hits += 1
				break
	assert_eq(hits, 50, "round 1 offers the face's count on every draw")


func test_scale_skips_non_additive_leaves() -> void:
	var loot := LootSystem.new()
	autofree(loot)
	var mul := StatModifier.new()
	mul.operation = StatModifier.Operation.MULTIPLY
	mul.value = 2.0
	loot._scale_loot_value(mul, 0.5)
	assert_eq(mul.value, 2.0, "a ×2 stays ×2 under a tier fraction")
	var add := StatModifier.new()
	add.value = 4.0
	loot._scale_loot_value(add, 0.5)
	assert_eq(add.value, 2.0, "an additive leaf still scales")
