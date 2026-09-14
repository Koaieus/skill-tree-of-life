extends GutTest

## #867 — an unallocated node never interacts with an incoming blade, and a
## defender that loses its allocation MID-SWING stops mattering from that moment.
##
## #864 closed the never-allocated half at the query
## ([method BladeDefenderZones.query] gates on `is_allocated()`, pinned by
## `test_defender_zones_ignore_unallocated.gd`) and left the live half open: the
## zone set is built once before the first sample, so a wall or plate the swing
## itself disowned kept dragging and deflecting for the rest of that swing.
##
## [b]The two bullets of #867's spec, in order.[/b]
##
## 1. One test for all THREE defensive addons at once. Spike (pop),
##    Fortification (`swing_drag`) and Bunker (`deflection`) each answer
##    ownership at a different site — [method BladePopResolver.LiveGate.admit],
##    and #864's gate in the zone query — so the contract "an unallocated node
##    does nothing to a blade" was three scattered assertions and no single
##    statement of it. `test_an_unowned_node_carrying_all_three_addons_does_nothing`
##    is that statement.
##
## 2. A plate the swing KILLS must stop deflecting from the kill onward. The
##    observable is a DIFFERENCE between two runs of one fixture that differ only
##    in `blade_damage` — a number the solver never reads. So the two swings are
##    physically the same swing right up to the sample the plate dies on, and any
##    divergence after it is the retirement and nothing else. On master the two
##    trajectories are bit-identical for the whole swing, which is the bug stated
##    as an equation.
##
##    A geometric assertion was tried first and is wrong: the plate deflects for
##    the substeps BEFORE its death, which throws the blade off the free arc it
##    was placed on, so "did a vertex end up inside the dead plate's disc" is
##    answered by where the perturbed whip went rather than by whether the plate
##    was retired. `test_a_plate_that_survives_deflects_for_the_whole_swing`
##    keeps the geometric claim where it IS exact — a live plate holds every
##    vertex out of its own disc, all swing.
##
## Geometry is `test_bunker_break_live.gd`'s FLOPPY fixture verbatim
## (pivot - a - b - tip at 150 px, no clamp), including its `_FLOPPY_PLATE`
## constant — a floppy tip curls hard inward and never traces the nominal
## radius, so the plate has to sit on a point read off the swing's own
## trajectory. See `.claude/rules/melee-fixtures.md`.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _SPACING := 150.0

## The point on the floppy fixture's own free tip path that
## `test_bunker_break_live.gd` measured (sample 95). Kept in both files rather
## than derived: deriving it means simulating the swing to place the obstacle
## that changes the swing.
const _FLOPPY_PLATE := Vector2(-253.0, -204.5)

## Far enough off the swing that the defender's camp is never touched — it
## exists only so the plate is a LEAF of real territory rather than a core,
## which keeps the cascade a plain forced-dealloc instead of entity death.
const _CAMP := Vector2(0.0, 2000.0)


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


func _sharpen(node: SkillNode, amount: float) -> void:
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = amount
	node.add_local_modifier(sharp)


## The floppy 4-node spine plus one defender node at [constant _FLOPPY_PLATE].
##
## `addons` are instantiated onto that node. `allocate_defender` false leaves it
## unowned — bullet 1's case. `blade_damage` is the coefficient put on the two
## outer blade vertices: large enough and the plate dies on the contact that
## reaches it, small enough and it survives the whole swing.
func _setup(addons: Array[PackedScene], allocate_defender: bool,
		blade_damage: float) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var enemy_camp := Faction.new()
	enemy_camp.id = &"defender_dies_mid_swing_enemy"
	defender.faction = enemy_camp

	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var a := _spawn(graph, "A", Vector2(_SPACING, 0.0))
	var b := _spawn(graph, "B", Vector2(_SPACING * 2.0, 0.0))
	var tip := _spawn(graph, "Tip", Vector2(_SPACING * 3.0, 0.0))
	graph.add_edge(pivot, a)
	graph.add_edge(a, b)
	graph.add_edge(b, tip)

	var camp := _spawn(graph, "Camp", _CAMP)
	var plate := _spawn(graph, "Plate", _FLOPPY_PLATE)
	graph.add_edge(camp, plate)

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	# The LIVE forced-dealloc cascade's entry point. A depleted node reaches it
	# through `Events.skill_node_depleted`, so without a BattleSystem mounted the
	# plate would die and stay allocated — `test_bunker_break_live.gd` gets away
	# without one only because it never asks about ownership afterwards.
	var turns: TurnManager = autofree(TurnManager.new())
	add_child(turns)
	turns.current_entity = attacker
	var battle: BattleSystem = autofree(BattleSystem.new())
	battle.turn_manager = turns
	battle.allocation_system = alloc
	battle.graph = graph
	add_child(battle)

	for n in [pivot, a, b, tip]:
		alloc.force_allocate(attacker, n)
	attacker.core_location = pivot
	alloc.force_allocate(defender, camp)
	defender.core_location = camp
	if allocate_defender:
		alloc.force_allocate(defender, plate)

	for scene in addons:
		plate.add_child(scene.instantiate() as SkillNodeAddon)

	# The wielder's own baseline blade_damage is 0 with no CoreClass assigned
	# (test_severed_swing_live.gd and test_bunker_break_live.gd hit the same
	# fixture gap), so without this every contact lands for exactly 0.
	_sharpen(b, blade_damage)
	_sharpen(tip, blade_damage)

	# The addon is what mints the defender collision bit, so the physics frames
	# have to come AFTER the attach — see `.claude/rules/melee-fixtures.md`.
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = pivot
	plan.blade_nodes = [a, b, tip]

	return {
		"graph": graph, "attacker": attacker, "defender": defender,
		"pivot": pivot, "a": a, "b": b, "tip": tip,
		"plate": plate, "camp": camp, "plan": plan,
	}


## The closest any blade vertex got to [param center] over the whole resolved
## trajectory. Deflection's whole job is to keep this above the plate's contact
## reach; nothing else in the sim pushes a vertex off its arc.
func _closest_approach(traj: BladeTrajectory, center: Vector2) -> float:
	var best := INF
	for sample: PackedVector2Array in traj.samples:
		for p in sample:
			best = minf(best, p.distance_to(center))
	return best


# --------------------------------------------------------------- spec bullet 1

func test_an_unowned_node_carrying_all_three_addons_does_nothing() -> void:
	var ctx: Dictionary = await _setup(
			[_SPIKE_SCENE, _FORTIFICATION_SCENE, _BUNKER_SCENE], false, 200.0)
	var plan: MeleeAttackPlan = ctx.plan
	var plate: SkillNode = ctx.plate

	# Fixture teeth: the node really does carry all three, and really is unowned.
	assert_false(plate.is_allocated(), "fixture: the carrier must be unowned")
	assert_gt(float(plate.get_local_value(&"swing_drag")), 0.0,
			"fixture: Fortification must author swing_drag")
	assert_true(bool(plate.get_local_value(&"deflection")),
			"fixture: Bunker must author deflection")
	assert_gt(float(plate.get_local_value(&"spikes")), 0.0,
			"fixture: SpikeRing must author spikes")

	var state := plan.build_blade_state()
	assert_null(state.obstacles,
			"#867 bullet 1: an unowned wall/plate contributes no zone at all")

	var hp_before := plate.get_current_hp()
	var outcome := plan.resolve_against(CombatWorld.live())

	assert_eq(plan.last_pops.vertex_pop_count(), 0,
			"#867 bullet 1: an unowned spike ring pops nothing")
	assert_eq(plan.last_pops.severed_at.size(), 0,
			"#867 bullet 1: an unowned bunker breaks nothing")
	assert_eq(plate.get_current_hp(), hp_before,
			"#867 bullet 1: an unowned node takes no damage either (#502's no-dud)")
	# A contact still MINTS a DamageInstance — the gate refuses at land time, so
	# the tell is `hp_before == hp_after` rather than the absence of the hit
	# (test_severed_swing_live.gd reads a landing the same way).
	for hit in outcome.hits:
		if hit.target != plate:
			continue
		assert_eq(hit.hp_before, hit.hp_after,
				"#867 bullet 1: a contact on an unowned node must land nothing")
	# And the swing is geometrically untouched: the tip runs straight through
	# where the unowned plate sits.
	assert_lt(_closest_approach(plan.last_trajectory, _FLOPPY_PLATE), plate.radius,
			"#867 bullet 1: an unowned plate deflects nothing — the arc runs through it")


# --------------------------------------------------------------- spec bullet 2

## The control. Same fixture, same geometry, a plate too tough to die: it must
## hold every vertex out of its own disc for the whole swing. Without this the
## dying-plate assertion below could pass on a swing that simply never arrived.
func test_a_plate_that_survives_deflects_for_the_whole_swing() -> void:
	var ctx: Dictionary = await _setup([_BUNKER_SCENE], true, 1.0)
	var plan: MeleeAttackPlan = ctx.plan
	var plate: SkillNode = ctx.plate

	var state := plan.build_blade_state()
	assert_not_null(state.obstacles, "fixture: an owned bunker attaches a field")
	assert_eq(state.obstacles.zone_radii.size(), 1, "fixture: exactly one zone")

	plan.resolve_against(CombatWorld.live())

	assert_true(plate.is_allocated(),
			"fixture: this plate must SURVIVE the swing (blade_damage is 1.0)")
	assert_gte(_closest_approach(plan.last_trajectory, _FLOPPY_PLATE), plate.radius,
			"a live plate holds every vertex out of its own disc all swing")


## The sample the plate's HP hit zero on, from the outcome's own timeline.
## `structural_key` is the hit's fraction of [constant
## MeleeAttackPlan.SWING_DURATION] (`test_severed_swing_live.gd` reads it the
## same way); -1 if nothing killed it.
func _death_sample(outcome: AttackOutcome, plate: SkillNode, dt: float) -> int:
	for hit in outcome.hits:
		if hit.target != plate or hit.hp_after > 0.0 or hit.hp_before <= 0.0:
			continue
		return int(round(hit.structural_key * MeleeAttackPlan.SWING_DURATION / dt))
	return -1


## #867 bullet 2, RED on master: the plate is killed by the contact that reaches
## it, the cascade disowns it there and then — and the rest of the swing must
## behave as if it had never been a plate at all.
##
## Two runs of the same fixture, differing only in `blade_damage`. The solver
## never reads that number, so the swings are identical until the plate dies;
## master then keeps deflecting on both and the two trajectories stay
## bit-identical to the last sample.
func test_a_plate_killed_mid_swing_stops_deflecting_from_that_moment() -> void:
	# ONE fixture, two passes. Two fixtures would not do: they would share the
	# test's single World2D, so each swing's physics query would find BOTH
	# plates (`.claude/rules/melee-fixtures.md`, reason 3's cousin).
	var ctx: Dictionary = await _setup([_BUNKER_SCENE], true, 1.0)
	var plan: MeleeAttackPlan = ctx.plan
	var plate: SkillNode = ctx.plate

	var state := plan.build_blade_state()
	assert_not_null(state.obstacles, "fixture: an owned bunker attaches a field")
	assert_eq(state.obstacles.zone_radii.size(), 1, "fixture: exactly one zone")

	# Pass B, the control: a blunt blade, so the plate survives and deflects all
	# swing. On a SHADOW, which is the authority's own compute path
	# (`.claude/rules/attack-timeline.md`) and leaves the live plate untouched
	# for pass A.
	var world_b := CombatWorld.shadow()
	plan.resolve_against(world_b)
	var b := plan.last_trajectory
	assert_true(world_b.combat_for(plate).is_allocated(),
			"fixture: the control's plate must survive the whole swing")
	world_b.free_shadow()

	# Pass A: the identical swing with a lethal coefficient. `blade_damage` feeds
	# `BladeState.vertex_damage`, which only the damage path reads — never the
	# solver — so A and B are the same physics until the plate dies. The
	# `first_divergence >= death` assertion below is what holds that premise.
	_sharpen(ctx.b, 200.0)
	_sharpen(ctx.tip, 200.0)
	var world_a := CombatWorld.shadow()
	var killed := plan.resolve_against(world_a)
	var a := plan.last_trajectory
	var death := _death_sample(killed, plate, a.sample_dt)
	assert_false(world_a.combat_for(plate).is_allocated(),
			"fixture: the depletion cascade must have disowned the plate")
	world_a.free_shadow()

	assert_eq(a.samples.size(), b.samples.size(),
			"fixture: both swings must run the same number of samples")
	assert_gt(death, 0, "fixture: the killing hit must be somewhere mid-swing")

	var first_divergence := -1
	for i in a.samples.size():
		if a.samples[i] != b.samples[i]:
			first_divergence = i
			break

	assert_gt(first_divergence, 0,
			"#867 bullet 2: a disowned plate must stop deflecting — on master "
			+ "these two swings are bit-identical to the last sample")
	assert_gte(first_divergence, death,
			"#867 bullet 2: and only FROM the kill — nothing before it may move, "
			+ "since blade_damage is not an input to the solver")
