extends GutTest

## A bare [HitLanding] — no spell, no [LandingContext] — is enough for
## [ApplyStatusEffect] to emit its [StatusInstance] (ADR 0044): the one on-hit
## vocabulary every attack mode shares.

const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")


func test_apply_status_on_a_bare_landing_emits_one_status_carrying_its_facts() -> void:
	var attacker: Entity = autofree(Entity.new())
	var target: SkillNode = autofree(SkillNode.new())
	var origin: SkillNode = autofree(SkillNode.new())
	var primary := DamageInstance.new()
	var landing := HitLanding.new()
	landing.attacker = attacker
	landing.source = primary
	landing.origin = origin
	landing.target = target
	landing.structural_key = 0.5
	landing.paired = primary

	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 3.0
	eff.apply(landing)

	assert_eq(landing.hits.size(), 1, "one status emitted into the landing's sink")
	var status := landing.hits[0] as StatusInstance
	assert_not_null(status, "the emitted hit is a StatusInstance")
	if status == null:
		return
	assert_eq(status.def, _TEST_DEF)
	assert_almost_eq(status.power, 3.0, 0.0001)
	assert_eq(status.target, target)
	assert_eq(status.origin, origin)
	assert_eq(status.attacker, attacker)
	assert_eq(status.paired, primary, "the status rides the landing's primary hit")
	assert_almost_eq(status.structural_key, 0.5, 0.0001)


## A spell-context effect on a non-spell landing is an authoring error: it
## emits nothing and says so, once.
func test_a_spell_effect_on_a_bare_landing_reports_once_and_emits_nothing() -> void:
	var landing := HitLanding.new()
	landing.target = autofree(SkillNode.new())
	var eff := DamageEffect.new()
	eff.apply(landing)
	eff.apply(landing)
	assert_eq(landing.hits.size(), 0, "a spell effect emits nothing off a spell landing")
	# Exactly one: a second push_error would fail the test as unexpected.
	assert_push_error("needs a spell landing", "reported once per effect instance")


## [method HitLanding.riding] is the one paired-landing construction every
## non-spell mode shares: the primary's facts, the primary as the gate, the
## caller's sink and cache by reference, and one key shared with the primary.
func test_riding_copies_the_primary_and_shares_its_key() -> void:
	var primary := DamageInstance.new()
	primary.attacker = autofree(Entity.new())
	primary.source = &"a_source"
	primary.origin = autofree(SkillNode.new())
	primary.read_node = autofree(SkillNode.new())
	primary.target = autofree(SkillNode.new())
	primary.structural_key = 0.75
	var sink: Array[HitInstance] = [primary]
	var cache := {&"k": 1}

	var landing := HitLanding.riding(primary, sink, cache)

	assert_eq(landing.attacker, primary.attacker)
	assert_eq(landing.source, primary.source)
	assert_eq(landing.origin, primary.origin)
	assert_eq(landing.read_node, primary.read_node)
	assert_eq(landing.target, primary.target)
	assert_almost_eq(landing.structural_key, 0.75, 0.0001)
	assert_eq(landing.paired, primary, "the primary gates the landing")
	assert_true(is_same(landing.hits, sink), "the caller's sink, by reference")
	assert_true(is_same(landing.gather_cache, cache), "the caller's cache, by reference")
	assert_ne(landing.hit_key, 0, "a landing mints a key")
	assert_eq(primary.hit_key, landing.hit_key, "the primary shares the landing's key")


func test_a_bare_landing_is_unscaled() -> void:
	assert_almost_eq(HitLanding.new().stack_scale, 1.0, 0.0001)


## [member HitLanding.stack_scale] is a landing term any mode carries: a
## status minted on a bare (non-spell) landing at scale 2 lands double the
## folded stacks.
func test_stack_scale_on_a_bare_landing_doubles_the_landed_stacks() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var attacker := _entity(graph)
	var defender := _entity(graph)
	var home := _node(graph)
	var target := _node(graph)
	await get_tree().process_frame
	alloc.force_allocate(attacker, home)
	attacker.core_location = home
	alloc.force_allocate(defender, target)
	defender.core_location = target

	var unscaled := _land_scaled(attacker, home, target, 1.0)
	var doubled := _land_scaled(attacker, home, target, 2.0)
	assert_gt(unscaled, 0.0, "fixture: the status lands stacks")
	assert_almost_eq(doubled, StatusDef.round_half_up(unscaled * 2.0), 0.0001,
			"stack_scale 2 lands double the folded stacks")


func _entity(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(e)
	return e


func _node(graph: Graph) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(n)
	return n


## Mints one status off a bare landing at [param scale], lands it on
## [param target] in the live world and returns the landed amount.
func _land_scaled(attacker: Entity, home: SkillNode, target: SkillNode, scale: float) -> float:
	var landing := HitLanding.new()
	landing.attacker = attacker
	landing.read_node = home
	landing.target = target
	landing.stack_scale = scale
	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 3.0
	eff.apply(landing)
	var status := landing.hits[0] as StatusInstance
	var world := CombatWorld.live()
	status.land_on(world.combat_for(target), world)
	return status.amount
