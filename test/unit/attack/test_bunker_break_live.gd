extends GutTest

## #781 — Bunker deflection through the REAL resolve loop, on a real graph,
## against a real physics-backed defender. `test_bunker_deflect.gd` pins the
## classification on hand-built [BladeState]s; this exercises the same claims
## through [method MeleeAttackPlan.build_blade_state] /
## [method MeleeAttackPlan.resolve_against], the seam a live swing actually
## runs. ADR 0005: a bunker never pops a vertex, it breaks the edge that
## carries the load — "matter" survives, "structure" fails.
##
## Geometry: pivot(0) - mid(1) - tip(2), a straight 3-node spine. `mid` is the
## only pivot-adjacent particle, so it is the swing's sole DRIVEN vertex; a
## [ClampAddon] on `mid` welds its two neighbours (pivot, tip) with a phantom
## brace, turning the whole spine into a rigid rod that cannot fold — the
## induced-truss case in miniature. Dropping that addon leaves the same three
## nodes a bare, floppy path. The bunker sits on the arc `tip` sweeps, so the
## contact point (tip, a vertex) and the failure point (the mid-tip edge, under
## a rigid spine) are deliberately not the same part — the ADR's hardest case.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")

const _SPACING := 150.0
## Fraction of a full turn round the tip's own arc where the plate sits —
## matches test_bunker_deflect.gd's `_field_on_arc` convention.
const _TURNS := 0.15

## A point on the FLOPPY fixture's own tip path (sample 95 of its free swing),
## where the plate is guaranteed a vertex contact. Kept as a constant rather
## than derived, because deriving it means simulating the swing to place the
## obstacle that changes the swing.
const _FLOPPY_PLATE := Vector2(-253.0, -204.5)

const _MID_IDX := 1
const _TIP_IDX := 2


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


## Builds the attacker's 3-node spine + defender's bunker on a fresh graph.
## `rigid`: weld `mid` with a real ClampAddon instance. `with_bunker`: attach a
## real BunkerAddon to the defender's node; when false the defender node is
## plain territory (acceptance 8's "no bunker" map).
## The FLOPPY fixture does NOT come through here — a floppy tip curls sharply
## inward instead of tracing the nominal radius, so its plate sits on a point
## read off its own trajectory (`_FLOPPY_PLATE`), the reference classification
## test's same trick. See `_setup_floppy_whip`.
func _setup(rigid: bool, with_bunker: bool) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var enemy_camp := Faction.new()
	enemy_camp.id = &"bunker_break_live_enemy"
	defender.faction = enemy_camp

	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var mid := _spawn(graph, "Mid", Vector2(_SPACING, 0.0))
	var tip := _spawn(graph, "Tip", Vector2(_SPACING * 2.0, 0.0))
	graph.add_edge(pivot, mid)
	graph.add_edge(mid, tip)

	var r := _SPACING * 2.0  # tip's distance from the pivot
	var bunker_pos := Vector2.from_angle(_TURNS * TAU) * r
	var bunker := _spawn(graph, "Bunker", bunker_pos)

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, pivot)
	alloc.force_allocate(attacker, mid)
	alloc.force_allocate(attacker, tip)
	attacker.core_location = pivot
	alloc.force_allocate(defender, bunker)
	defender.core_location = bunker

	if rigid:
		var clamp := _CLAMP_SCENE.instantiate() as SkillNodeAddon
		mid.add_child(clamp)
	if with_bunker:
		var bunker_addon := _BUNKER_SCENE.instantiate() as SkillNodeAddon
		bunker.add_child(bunker_addon)

	# The wielder's own baseline blade_damage is 0 with no CoreClass assigned
	# (test_severed_swing_live.gd hits the same fixture gap) — without this,
	# the contacting vertex would land for exactly 0 and prove nothing about
	# acceptance c/d's "the hit still lands, mitigated".
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 20.0
	tip.add_local_modifier(sharp)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = pivot
	plan.blade_nodes = [mid, tip]

	return {
		"graph": graph, "attacker": attacker, "defender": defender,
		"pivot": pivot, "mid": mid, "tip": tip, "bunker": bunker, "plan": plan,
	}


# ---------------------------------------------------------------- acceptance a

func test_a_bunker_in_reach_builds_one_obstacle_zone() -> void:
	var ctx: Dictionary = await _setup(true, true)
	var plan: MeleeAttackPlan = ctx.plan
	var state := plan.build_blade_state()
	assert_not_null(state.obstacles, "a bunker in reach must attach a field")
	assert_eq(state.obstacles.zone_radii.size(), 1, "exactly one zone for one bunker")


func test_no_bunker_means_no_field_object_at_all() -> void:
	var ctx: Dictionary = await _setup(true, false)
	var plan: MeleeAttackPlan = ctx.plan
	var state := plan.build_blade_state()
	assert_null(state.obstacles,
			"acceptance 8: no bunker means the object itself is null, not merely inert")


# ---------------------------------------------------------------- acceptance b, c

func test_a_rigid_blade_breaks_the_edge_never_the_vertex_and_still_damages_the_bunker() -> void:
	var ctx: Dictionary = await _setup(true, true)
	var plan: MeleeAttackPlan = ctx.plan
	var bunker: SkillNode = ctx.bunker
	var hp_before := bunker.get_current_hp()

	var outcome := plan.resolve_against(CombatWorld.live())

	# b. an edge Pop, recorded as a severance, never a vertex pop.
	var edge_pops: Array = []
	for pop in plan.last_pops.pops:
		if pop.particle_idx == -1:
			assert_gte(pop.edge_idx, 0, "an edge Pop must carry a real edge index")
			edge_pops.append(pop)
		else:
			fail_test("a bunker break must never mint a vertex Pop (ADR 0005): got particle_idx=%d"
					% pop.particle_idx)
	assert_eq(edge_pops.size(), 1, "exactly one edge break for one rigid contact")
	var broken_edge: int = edge_pops[0].edge_idx
	assert_true(plan.last_pops.severed_at.has(broken_edge),
			"the broken edge must be recorded in severed_at")
	assert_eq(plan.last_pops.vertex_pop_count(), 0,
			"a bunker never pops a vertex (ADR 0005)")

	var state := plan.build_blade_state()
	# The RESOLVED state (the one the loop actually severed) is reachable only
	# through the plan's own trajectory-producing run; build_blade_state()
	# above builds a FRESH state, so removed_edges lives on the state the loop
	# mutated, not this one. Assert through last_pops (the resolve loop's own
	# record) — its severed_at IS the resolved state's removed_edges by
	# construction (LiveGate._sever_edge writes both in the same call).
	assert_true(state != null, "fixture: a state must still build post-resolve")

	# c. the hit still lands, mitigated: the bunker takes damage.
	var hp_after := bunker.get_current_hp()
	assert_lt(hp_after, hp_before,
			"the contacting vertex's hit must still land on the bunker, mitigated")

	# f. structure is not matter: no popped_nodes for an edge break.
	assert_eq(outcome.popped_nodes, 0,
			"an edge break must not count as a popped node (particle_idx >= 0 filter)")


# ---------------------------------------------------------------- acceptance d

## Bare 4-node spine (pivot - a - b - tip), no clamps: `a` is the sole driven
## particle, and TWO free joints hang off it (a-b, b-tip) — the shortest chain
## with an actual fold to give, unlike the 3-node rigid fixture above (which
## has none to spare, only a driven-to-free single link). Mirrors
## test_bunker_deflect.gd's own `_arm(4)` floppy shape rather than reusing the
## rigid fixture's geometry, which a floppy tip never comes near (measured:
## the 3-node tip curls to within ~9px of the pivot under a full TAU sweep).
func _setup_floppy_whip() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var enemy_camp := Faction.new()
	enemy_camp.id = &"bunker_break_live_floppy_enemy"
	defender.faction = enemy_camp

	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var a := _spawn(graph, "A", Vector2(_SPACING, 0.0))
	var b := _spawn(graph, "B", Vector2(_SPACING * 2.0, 0.0))
	var tip := _spawn(graph, "Tip", Vector2(_SPACING * 3.0, 0.0))
	graph.add_edge(pivot, a)
	graph.add_edge(a, b)
	graph.add_edge(b, tip)

	# NOT the rigid fixture's arc formula: a floppy tip curls hard inward and
	# never comes within 39px of the nominal radius (measured off this exact
	# fixture). This is a point the free tip actually passes through, read off
	# its own trajectory — see the class docstring's note on the reference
	# classification test's same trick.
	var bunker := _spawn(graph, "Bunker", _FLOPPY_PLATE)

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for n in [pivot, a, b, tip]:
		alloc.force_allocate(attacker, n)
	attacker.core_location = pivot
	alloc.force_allocate(defender, bunker)
	defender.core_location = bunker

	var bunker_addon := _BUNKER_SCENE.instantiate() as SkillNodeAddon
	bunker.add_child(bunker_addon)

	# Deliberately blunter than the rigid fixture's +20: this test wants the
	# plate to be CHIPPED, not killed. At +20 the mitigated hit is 17.5 against
	# 10 node_health, and a dead defender core drags the whole death cascade
	# into a test about a blade that flops. At +5 it lands 2.15 — non-zero, so
	# the hit is real, and visibly mitigated (bunker's +5 armor / −5
	# min_damage_taken take a +5 blade under the floor entirely).
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 5.0
	tip.add_local_modifier(sharp)
	b.add_local_modifier(sharp)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = pivot
	plan.blade_nodes = [a, b, tip]

	return {"bunker": bunker, "plan": plan}


func test_a_floppy_blade_never_breaks_and_still_damages_the_bunker() -> void:
	var ctx: Dictionary = await _setup_floppy_whip()
	var plan: MeleeAttackPlan = ctx.plan
	var bunker: SkillNode = ctx.bunker
	var hp_before := bunker.get_current_hp()

	plan.resolve_against(CombatWorld.live())

	assert_eq(plan.last_pops.severed_at.size(), 0,
			"a floppy blade must flop around the plate, never break an edge")
	var edge_pops := 0
	for pop in plan.last_pops.pops:
		if pop.particle_idx == -1:
			edge_pops += 1
	assert_eq(edge_pops, 0, "no edge Pop for a floppy contact")

	assert_lt(bunker.get_current_hp(), hp_before,
			"the bunker still takes the mitigated hit even when nothing breaks")


# ---------------------------------------------------------------- acceptance e

func test_the_same_rigid_swing_reproduces_bit_identically() -> void:
	var ctx_a: Dictionary = await _setup(true, true)
	var ctx_b: Dictionary = await _setup(true, true)
	var plan_a: MeleeAttackPlan = ctx_a.plan
	var plan_b: MeleeAttackPlan = ctx_b.plan

	plan_a.resolve_against(CombatWorld.live())
	plan_b.resolve_against(CombatWorld.live())

	assert_eq(plan_a.last_trajectory.samples.size(), plan_b.last_trajectory.samples.size(),
			"fixture: both swings must run the same number of samples")
	for i in plan_a.last_trajectory.samples.size():
		assert_eq(plan_a.last_trajectory.samples[i], plan_b.last_trajectory.samples[i],
				"sample %d must match to the bit" % i)
	assert_eq(plan_a.last_pops.severed_at.keys(), plan_b.last_pops.severed_at.keys(),
			"the same edge must break on both runs")
	for k in plan_a.last_pops.severed_at.keys():
		assert_eq(plan_a.last_pops.severed_at[k], plan_b.last_pops.severed_at[k],
				"the same edge must break at the same time on both runs")
