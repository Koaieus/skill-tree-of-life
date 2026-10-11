extends GutTest

## [StatusFilter] and the [method PropagationContext.stacks_of] seam under it:
## the filter reads the cast's WORLD, so a node cured on a shadow wave is
## rejected while the live node keeps its stacks.

var h: SpellTestHelper
var poison: StatusDef
var bleed: StatusDef


func before_each() -> void:
	h = SpellTestHelper.new()
	poison = _def(&"poison_t")
	bleed = _def(&"bleed_t")


func _def(id: StringName) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.power_max = 0.0
	d.decay = FlatDecay.new(0.0)
	return d


func _filter(defs: Array[StatusDef], min_stacks: float = 1.0) -> StatusFilter:
	var f := StatusFilter.new()
	f.statuses = defs
	f.min_stacks = min_stacks
	return f


func _lctx(graph: Graph, world: CombatWorld, node: SkillNode) -> LandingContext:
	var c := PropagationContext.new()
	c.graph = graph
	c.world = world
	var p := CastSpell.new()
	p.current_node = node
	p.graph = graph
	return LandingContext.for_test(p, node, c)


func _setup() -> Array:
	var graph := h.make_graph([[0, 1], [0, 2]], self)
	var e := h.make_entity(graph, "E", Color.BLUE)
	h.assign_owner(graph, e, [0, 1, 2])
	return [graph, graph.get_skill_nodes()]


func test_admits_only_nodes_with_a_listed_status() -> void:
	var s := _setup()
	var n: Array = s[1]
	n[1].get_combat().apply_status(poison, 2.0)
	n[2].get_combat().apply_status(bleed, 3.0)
	var lctx := _lctx(s[0], CombatWorld.shadow(), n[0])
	var f := _filter([poison] as Array[StatusDef])
	assert_true(f.allows(n[1], lctx), "poisoned node admitted")
	assert_false(f.allows(n[2], lctx), "only bleeding: not listed")
	assert_false(f.allows(n[0], lctx), "clean node rejected")
	assert_false(f.allows(null, lctx))


func test_any_listed_status_qualifies() -> void:
	var s := _setup()
	var n: Array = s[1]
	n[2].get_combat().apply_status(bleed, 3.0)
	var lctx := _lctx(s[0], CombatWorld.shadow(), n[0])
	assert_true(_filter([poison, bleed] as Array[StatusDef]).allows(n[2], lctx))


func test_min_stacks_is_the_threshold() -> void:
	var s := _setup()
	var n: Array = s[1]
	n[1].get_combat().apply_status(poison, 2.0)
	var lctx := _lctx(s[0], CombatWorld.shadow(), n[0])
	assert_true(_filter([poison] as Array[StatusDef], 2.0).allows(n[1], lctx))
	assert_false(_filter([poison] as Array[StatusDef], 3.0).allows(n[1], lctx))
	assert_eq(StatusFilter.new().min_stacks, 1.0, "default knob")


func test_narrow_keeps_order_of_the_admitted() -> void:
	var s := _setup()
	var n: Array = s[1]
	n[1].get_combat().apply_status(poison, 1.0)
	n[2].get_combat().apply_status(poison, 1.0)
	var lctx := _lctx(s[0], CombatWorld.shadow(), n[0])
	var cands: Array[SkillNode] = [n[2], n[0], n[1]]
	assert_eq(_filter([poison] as Array[StatusDef]).narrow(cands, lctx), [n[2], n[1]] as Array[SkillNode])


## A node cured on the shadow (wave N) is rejected on wave N+1 while the live
## node still carries its stacks.
func test_a_node_cured_on_the_shadow_is_rejected_while_live_keeps_its_stacks() -> void:
	var s := _setup()
	var n: Array = s[1]
	n[1].get_combat().apply_status(poison, 2.0)
	var world := CombatWorld.shadow()
	var lctx := _lctx(s[0], world, n[0])
	var f := _filter([poison] as Array[StatusDef])
	assert_true(f.allows(n[1], lctx), "precondition: infected before the cure")

	world.combat_for(n[1]).adjust_status_power(poison, -2.0)

	assert_false(f.allows(n[1], lctx), "cured on the world this cast walks")
	assert_eq(n[1].get_combat().get_status_power(&"poison_t"), 2.0,
			"the live node keeps its stacks until the record replays")
