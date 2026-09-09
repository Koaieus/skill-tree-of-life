extends GutTest

## #814 — a defender the physics space has not seen yet silently does not
## defend. [method BladeDefenderZones.query] answers "who carries `swing_drag`
## / `deflection` in reach?" with [method
## PhysicsDirectSpaceState2D.intersect_shape], and an `Area2D` whose collision
## bit just changed is not visible to that query until a physics frame has run
## past it (`.claude/rules/melee-fixtures.md`'s "two extra teeth"). Before
## #814 this failed COMPLETELY silently: no error, no warning, the wall or
## plate just doesn't act. This pins the SAME-FRAME case the issue names as
## the one that must not stay silent any longer — attach the addon, resolve
## before any intervening `physics_frame`, and the debug cross-check must
## `push_warning` naming the missed node.
##
## The cross-check itself re-walks the graph (`BladeDefenderZones.
## _debug_cross_check`) — the very O(map) cost #811 deleted from the release
## path — so it is gated on `OS.is_debug_build()`. GUT always runs a debug
## build, which is what makes it observable here at all.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")

const _SPACING := 150.0


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity(graph: Graph) -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	graph.add_child(entity)
	return entity


## The attacker's own pivot-tip blade, plus a hostile node parked OFF the
## whip's reach entirely — mirrors `test_blade_whip_reach.gd`'s own fixture
## shape (its `Hostile` starts at `(100000, 100000)`). Both settle through
## the normal two physics frames, so by the time the test body runs, the
## physics space HAS seen this exact Area2D, just not where the test is
## about to put it.
func _setup() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var camp := Faction.new()
	camp.id = &"missed_frame_guard_enemy"
	defender.faction = camp

	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var tip := _spawn(graph, "Tip", Vector2(_SPACING, 0.0))
	graph.add_edge(pivot, tip)
	var hostile := _spawn(graph, "Hostile", Vector2(100000.0, 100000.0))

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, pivot)
	alloc.force_allocate(attacker, tip)
	attacker.core_location = pivot
	alloc.force_allocate(defender, hostile)
	defender.core_location = hostile

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = pivot
	plan.blade_nodes = [tip]
	return {"plan": plan, "hostile": hostile}


func test_a_same_frame_fortification_move_is_missed_by_the_query_and_the_guard_fires() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile

	# The move into whip_bound AND the addon attach happen HERE, in the same
	# call stack as the query below — `test_blade_whip_reach.gd`'s own
	# "`await get_tree().physics_frame` or this test silently passes nothing"
	# note is exactly this gap: a collider's *new position* only reaches the
	# broadphase [PhysicsDirectSpaceState2D.intersect_shape] reads on the next
	# physics tick, not the instant `global_position` is set. Well inside
	# whip_bound (chain length 150 * 1.10 margin + widest radius + edge
	# radius, comfortably past 165) — this test is about the FRAME, not the
	# geometry, so it moves somewhere close rather than onto a measured swing
	# path.
	hostile.global_position = Vector2(75.0, 0.0)
	# The addon's modifier transfer is synchronous (`child_entered_tree`, see
	# `.claude/rules/skill-node-addons.md`), so `swing_drag` reads nonzero the
	# instant this returns — no frame needed for THAT half.
	hostile.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
	assert_gt(float(hostile.get_local_value(&"swing_drag")), 0.0,
			"fixture: Fortification must actually author swing_drag before the "
			+ "physics half is even in question")

	# Deliberately NO `await get_tree().process_frame` / `physics_frame` here
	# — the query below runs in the exact same frame `hostile` moved in.
	var state := plan.build_blade_state()

	assert_null(state.obstacles,
			"fixture: pins the bug itself — the physics query silently misses "
			+ "a same-frame move into reach, so no field is attached at all")
	assert_push_warning("the physics query missed it",
			"the debug cross-check must name the node the query dropped")
