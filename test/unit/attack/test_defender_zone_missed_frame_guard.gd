extends GutTest

## #814 / #1136 — a defender the physics space has not seen yet.
##
## [method BladeDefenderZones.query] answers "who carries `swing_drag` /
## `deflection` in reach?" with [method
## PhysicsDirectSpaceState2D.intersect_shape], and an `Area2D` whose collision
## bit just changed is not visible to that query until a physics frame has run
## past it (`.claude/rules/melee-fixtures.md`'s "two extra teeth"). Before
## #814 this failed completely silently in release AND debug; #814 added a
## debug-only cross-check that at least warned. #1136: the cross-check's own
## walk is now promoted to a same-frame FALLBACK — `SkillNode._sync_collision`
## / `_sync_defender_bit` stamp [method BladeDefenderZones.mark_broadphase_dirty]
## the instant either write happens, and [method BladeDefenderZones.query]
## walks the graph instead of trusting the stale physics query while that
## stamp is current. Release and debug now resolve identically in the same-
## frame window.
##
## Two cases pinned here:
## 1. Same frame as the attach, no `physics_frame` await: the walk fallback
##    finds the defender and the debug cross-check does NOT fire (there is
##    nothing for it to catch — the fallback IS the result).
## 2. One `physics_frame` later: the stamp is stale, `query()` takes the
##    physics path, and finds the same zone.
##
## [b]Case 1's "found" assert alone pins nothing.[/b] In this headless GUT
## environment the raw physics `intersect_shape` already sees a same-frame
## `_sync_defender_bit` layer-bit toggle (and a same-frame radius write) with
## no fallback at all — verified by stripping both `mark_broadphase_dirty`
## call sites and by isolating each writer in a scratch probe; only a pure
## same-frame *position* move reproducibly misses, and a position write is not
## one of the two stamp writers this fix names. So case 1's `assert_not_null`
## would pass identically without the fix here. What actually pins the fix is
## the stamp assertion right after the attach: it goes RED the moment either
## `mark_broadphase_dirty` call site is removed (the stamp never advances past
## -1), proving the fallback BRANCH is what ran — not proving the branch was
## necessary to find this particular fixture's defender.

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


## The attacker's own pivot-tip blade, plus a hostile node parked WITHIN whip
## reach from the start — #1136's fix only concerns the collision-bit /
## radius writes (`mark_broadphase_dirty`'s two callers), never a same-frame
## position move, so the fixture settles the position through the normal two
## physics frames and only the addon attach happens same-frame as the query.
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
	# Comfortably inside whip_bound (chain length 150 * 1.10 margin + widest
	# radius + edge radius, past 165) — this fixture is about the FRAME, not
	# the geometry.
	var hostile := _spawn(graph, "Hostile", Vector2(75.0, 0.0))

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


func test_a_same_frame_fortification_attach_is_found_by_the_walk_fallback() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile

	# The addon's modifier transfer is synchronous (`child_entered_tree`, see
	# `.claude/rules/skill-node-addons.md`), so `swing_drag` reads nonzero the
	# instant this returns, and `_sync_defender_bit` stamps the dirty frame
	# the same instant.
	hostile.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
	assert_gt(float(hostile.get_local_value(&"swing_drag")), 0.0,
			"fixture: Fortification must actually author swing_drag before the "
			+ "physics half is even in question")
	# The red this test can actually observe (see the class doc): strip either
	# `mark_broadphase_dirty` call site and this goes red because the stamp
	# never leaves -1 — proving the attach took the fallback branch, since the
	# "found" assert below passes either way in this environment.
	assert_eq(BladeDefenderZones._dirty_frame, Engine.get_physics_frames(),
			"fixture: the attach must have stamped THIS physics frame")

	# Deliberately NO `await get_tree().physics_frame` here — the query below
	# runs in the exact same frame the addon attached in, inside the dirty
	# window `mark_broadphase_dirty` just opened.
	var state := plan.build_blade_state()

	assert_not_null(state.obstacles,
			"the walk fallback must find the same-frame defender the physics "
			+ "query cannot see yet")
	if state.obstacles != null:
		assert_true(state.obstacles.zone_defenders.has(hostile),
				"the fallback's zone must be the same Hostile node that just "
				+ "attached the addon")
	assert_push_warning_count(0,
			"the debug cross-check must not fire on the fallback path — "
			+ "there is nothing for it to catch when the walk IS the result")


func test_one_physics_frame_later_the_physics_path_takes_over_and_agrees() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile

	hostile.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
	var dirty_frame_at_attach: int = BladeDefenderZones._dirty_frame

	await get_tree().physics_frame

	assert_gt(Engine.get_physics_frames(), dirty_frame_at_attach,
			"fixture: a physics frame must actually have advanced past the "
			+ "attach for the stamp to go stale")

	var state := plan.build_blade_state()

	assert_gt(Engine.get_physics_frames(), BladeDefenderZones._dirty_frame,
			"the stamp is now stale — query() must have taken the physics "
			+ "path, not the walk fallback")
	assert_not_null(state.obstacles,
			"the physics path must find the same defender the fallback did "
			+ "a frame earlier")
	if state.obstacles != null:
		assert_true(state.obstacles.zone_defenders.has(hostile),
				"physics path and fallback must agree on which node defends")
