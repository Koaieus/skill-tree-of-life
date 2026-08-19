extends GutTest

## #483 — the forced-dealloc cascade reveals on the presentation clock.
##
## `BattleSystem.cascade_started` fires synchronously during `_apply_outcome`,
## before the killing hit's VFX is anywhere near the impact node. So AllocationVFX
## must not arm the ripple there: it snapshots, and starts the existing
## `layer_index * CASCADE_STEP` stagger from `Events.node_death_shown(impact)` —
## the moment the hit visually lands. Each cascaded node's tint/fill reveal, its
## shatter, and the aura's territory refresh all land on that same slot.
##
## Fixture: attacker core(0,0) — leaf(200,0) with range 100 and overkill ranged
## damage. Hostile owns a chain hcore(350,0) — t1(250,0) — t2(300,-100), so
## killing t1 (the cut vertex) islands t2. Cascade layers: [[t1], [t2]].

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _AURA_OVERLAY_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _add_node(graph: Graph, at: Vector2) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.position = at
	graph.add_skill_node(n)
	return n


func _visuals(node: SkillNode) -> Node:
	return node.get_node("Visuals/NodeVisualsComposite")


func _build() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _add_node(graph, Vector2(0, 0))
	var leaf := _add_node(graph, Vector2(200, 0))
	graph.add_edge(core, leaf)

	var t1 := _add_node(graph, Vector2(250, 0))
	var t2 := _add_node(graph, Vector2(300, -100))
	var hcore := _add_node(graph, Vector2(350, 0))
	graph.add_edge(hcore, t1)
	graph.add_edge(t1, t2)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.action_points.set_base_ratcheted(2.0)
	attacker.stat_board.action_points.current = 2.0
	graph.add_child(attacker)

	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.color = Color(0.1, 0.9, 0.3)
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	alloc.force_allocate(attacker, leaf)
	attacker.core_location = core
	alloc.force_allocate(hostile, hcore)
	alloc.force_allocate(hostile, t1)
	alloc.force_allocate(hostile, t2)
	hostile.core_location = hcore

	_set_stat(leaf, &"range", 100.0)
	_set_stat(leaf, &"ranged_damage", 9999.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	# Live AttackVFX so launch_attack actually reaches an await and hands control
	# back with the reveal still pending.
	var vfx := AttackVFX.new()
	add_child_autofree(vfx)
	bs.attack_vfx = vfx

	var alloc_vfx := AllocationVFX.new()
	alloc_vfx.allocation_system = alloc
	alloc_vfx.battle_system = bs
	add_child_autofree(alloc_vfx)
	await get_tree().process_frame

	return {"bs": bs, "alloc_vfx": alloc_vfx, "hostile": hostile,
			"t1": t1, "t2": t2, "hcore": hcore}


func _fire(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.t1)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	bs.launch_attack()


func test_cascade_is_not_armed_at_model_mutation_time() -> void:
	var ctx: Dictionary = await _build()
	var alloc_vfx: AllocationVFX = ctx.alloc_vfx
	var t2: SkillNode = ctx.t2
	var hostile: Entity = ctx.hostile
	var baseline := alloc_vfx.get_child_count()

	_fire(ctx)

	# The whole cascade already ran in the model.
	assert_null((ctx.t1 as SkillNode).owned_by, "impact is stripped synchronously")
	assert_null(t2.owned_by, "islanded neighbour is stripped synchronously")
	# But nothing has been shown yet: no shatter stage spawned, and the islanded
	# node still paints as owned territory.
	assert_eq(alloc_vfx.get_child_count(), baseline,
			"no shatter may spawn before the killing hit has visually landed")
	assert_true(t2.presentation_hold, "cascaded node withholds its paint")
	assert_eq(_visuals(t2).allocation_level, 1,
			"cascaded node's fill must not collapse ahead of the hit")
	assert_eq(_visuals(t2).entity_tint, hostile.color,
			"cascaded node keeps the defender's tint until its slot")


func test_ripple_starts_on_the_impact_reveal_and_keeps_its_stagger() -> void:
	var ctx: Dictionary = await _build()
	var alloc_vfx: AllocationVFX = ctx.alloc_vfx
	var t1: SkillNode = ctx.t1
	var t2: SkillNode = ctx.t2
	var baseline := alloc_vfx.get_child_count()

	_fire(ctx)

	# The killing hit lands — layer 0 fires immediately, layer 1 does not.
	Events.node_death_shown.emit(t1)
	assert_false(t1.presentation_hold, "the impact node reveals at slot 0")
	assert_eq(alloc_vfx.get_child_count(), baseline + 1,
			"slot 0 spawns exactly the impact node's shatter")
	assert_true(t2.presentation_hold,
			"layer 1 is still one CASCADE_STEP away — it must not reveal with layer 0")

	# One CASCADE_STEP later, layer 1 takes its slot: reveal and shatter together.
	await wait_seconds(AllocationVFX.CASCADE_STEP + 0.15)

	assert_false(t2.presentation_hold, "layer 1 reveals on its own stagger slot")
	assert_eq(_visuals(t2).allocation_level, 0,
			"the cascaded node's fill catches up at its slot, not before")
	assert_ne(_visuals(t2).entity_tint, (ctx.hostile as Entity).color,
			"and so does its tint — a node must never drop its fill but keep enemy colour")
	assert_eq(alloc_vfx.get_child_count(), baseline + 2,
			"slot 1 spawns the islanded node's shatter")


## The aura is the third subscriber on the same clock. `_refresh()` re-reads the
## whole ownership model, so what's being pinned here is WHEN it runs: not on
## the synchronous `force_deallocated`, but on each node's reveal.
func test_aura_holds_the_defenders_territory_until_the_reveal() -> void:
	var ctx: Dictionary = await _build()
	var aura: AuraOverlay = _AURA_OVERLAY_SCENE.instantiate()
	aura.graph = ctx.bs.graph
	aura.allocation_system = ctx.bs.allocation_system
	add_child_autofree(aura)
	await get_tree().process_frame

	var mat: ShaderMaterial = aura.material
	var before: int = mat.get_shader_parameter(&"circle_count")
	assert_eq(before, 5, "fixture: 2 attacker nodes + 3 defender nodes")

	_fire(ctx)
	assert_eq(mat.get_shader_parameter(&"circle_count"), before,
			"territory must not visibly retreat while the hit is still in flight")

	Events.node_death_shown.emit(ctx.t1)
	assert_eq(mat.get_shader_parameter(&"circle_count"), before - 1,
			"the impact node's reveal drops exactly its own circle")

	await wait_seconds(AllocationVFX.CASCADE_STEP + 0.15)
	assert_eq(mat.get_shader_parameter(&"circle_count"), before - 2,
			"the islanded node's circle drops on its own stagger slot")


## #485 — entity-level wound TOAST rides the same clock as the node reveal.
## `wound()` fires synchronously inside `_on_node_depleted`, at model-mutation
## time; the toast must not float until the impact hit's VFX lands.
func test_wound_toast_is_not_emitted_before_the_impact_reveal() -> void:
	var ctx: Dictionary = await _build()
	var hostile: Entity = ctx.hostile
	var t1: SkillNode = ctx.t1
	var seen: Array[int] = []
	Events.entity_wounded.connect(func(_e: Entity, amount: int) -> void: seen.append(amount))

	_fire(ctx)

	assert_eq(seen.size(), 0,
			"the cascade already wounded the defender in the model, but the TOAST must wait")

	Events.node_death_shown.emit(t1)

	assert_eq(seen.size(), 1, "the toast releases on the impact's reveal")
	assert_eq(seen[0], 2, "both cascaded nodes (t1, t2) wound the defender once each")


## #485 — the entity-death strip (`AllocationSystem.deallocate_all_owned`,
## triggered synchronously when this cascade's chip damage empties `health`)
## rides the SAME ripple as the battle cascade instead of collapsing
## unstaggered at t=0. Fixture: drop hostile's health to exactly the 2-node
## cascade's chip total so this cascade is the killing blow; hcore (outside
## the cascade set) is the death strip's only remaining node.
func test_death_strip_piggybacks_on_the_same_ripple_one_beat_later() -> void:
	var ctx: Dictionary = await _build()
	var alloc_vfx: AllocationVFX = ctx.alloc_vfx
	var hostile: Entity = ctx.hostile
	var t1: SkillNode = ctx.t1
	var t2: SkillNode = ctx.t2
	var hcore: SkillNode = ctx.hcore
	hostile.stat_board.health.set_current(2.0)
	var baseline := alloc_vfx.get_child_count()

	_fire(ctx)

	assert_true(hostile.is_dead, "the 2-node cascade's chip damage is exactly lethal")
	assert_null(hcore.owned_by, "the death strip already stripped the core in the model")
	assert_eq(alloc_vfx.get_child_count(), baseline,
			"nothing shatters before the killing hit has visually landed")
	assert_true(hcore.presentation_hold, "the death strip's own node also withholds its paint")

	Events.node_death_shown.emit(t1)
	assert_true(hcore.presentation_hold,
			"the death strip is one beat past layer 1 (t2) — it must not reveal with layer 0")

	# Layer 1 (t2) takes its slot at +1 CASCADE_STEP; the death strip (hcore)
	# is queued one CASCADE_STEP further still.
	await wait_seconds(AllocationVFX.CASCADE_STEP + 0.15)
	assert_true(hcore.presentation_hold,
			"the death strip must not reveal alongside layer 1 (t2) — it's one beat further")

	await wait_seconds(AllocationVFX.CASCADE_STEP + 0.15)
	assert_false(hcore.presentation_hold, "the death strip reveals on its own trailing slot")


func test_non_combat_cascade_still_arms_immediately() -> void:
	var ctx: Dictionary = await _build()
	var alloc_vfx: AllocationVFX = ctx.alloc_vfx
	var baseline := alloc_vfx.get_child_count()

	# Straight to the model, bypassing BattleSystem.launch_attack — what the
	# allocation/loot sandboxes do. Nothing will ever emit a reveal for these
	# nodes, so the ripple must arm right away, exactly as it did pre-#483.
	(ctx.t1 as SkillNode).take_damage(10000.0, null)

	assert_eq(alloc_vfx.get_child_count(), baseline + 2,
			"an unheld cascade arms both layers immediately")
	assert_false((ctx.t2 as SkillNode).presentation_hold,
			"nothing withholds paint outside an attack")
