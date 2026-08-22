extends GutTest

## Acceptance for #457 — "the same seed produces the same map". The other half
## of the contract (one-shot resolution) is `test/unit/session/test_game_session.gd`.
##
## [b]Scope, per the owner call of 2026-08-21:[/b] the seed reproduces the MAP,
## not the FIGHTS. Combat reproducibility comes from the per-attack
## [member AttackPlan.resolve_seed] and loot rolls are host-only (#473) — see
## `test/unit/attack/test_attack_determinism.gd`. Do not extend this file to
## assert identical crits or relics; that is a deliberate non-goal.
##
## [b]The trap this file is built around:[/b] [method GraphProcgen.generate]
## MUTATES its config — `shape_mask.size_for()` sizes the mask in place and
## `_propagate_mask_radius` writes back into radial fields. Reusing one config
## object for both runs makes run 2 start from an already-sized mask, which
## reads as non-determinism and sends you debugging the wrong thing. Every run
## below builds its config from scratch.


func _config(config_seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.node_count = 40
	cfg.seed = config_seed
	cfg.shape_mask = CircularShapeMask.new()
	return cfg


## A structural fingerprint of a generated graph: node positions plus the
## edge set, both order-sensitive, which is what "the same map" means here.
func _fingerprint(config_seed: int) -> String:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(_config(config_seed), graph)

	var parts: PackedStringArray = []
	var nodes: Array = result.get("nodes", [])
	for n in nodes:
		var node: SkillNode = n
		parts.append("%d,%d" % [roundi(node.position.x), roundi(node.position.y)])
	parts.append("|")
	for e in graph.get_edges():
		var edge: Edge = e
		parts.append("%s-%s" % [nodes.find(edge.from), nodes.find(edge.to)])
	parts.append("|starters:%d" % (result.get("starting_nodes", []) as Array).size())
	return "/".join(parts)


func test_the_same_seed_produces_the_same_graph_twice() -> void:
	var first: String = await _fingerprint(20260822)
	var second: String = await _fingerprint(20260822)
	assert_eq(first, second, "the same seed generated two different maps")
	assert_gt(first.length(), 16, "fingerprint is suspiciously empty — did generation run?")


func test_a_different_seed_produces_a_different_graph() -> void:
	var first: String = await _fingerprint(20260822)
	var other: String = await _fingerprint(20260823)
	assert_ne(first, other, "two different seeds generated the same map")


## The seed reaching procgen is always concrete: `GraphProcgen` resolves no
## sentinel of its own, so two generations from an unresolved `0` would be
## identical (seed 0 is a legal RNG seed). Resolving up front is what makes
## "randomise me" actually randomise — and makes the result replayable.
func test_a_resolved_zero_seed_still_differs_between_runs() -> void:
	var first: String = await _fingerprint(RunConfig.resolve_seed(0))
	var second: String = await _fingerprint(RunConfig.resolve_seed(0))
	assert_ne(first, second, "two 'randomise me' runs produced the same map")
