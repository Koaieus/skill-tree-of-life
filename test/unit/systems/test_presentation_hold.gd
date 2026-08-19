extends GutTest

## #491 — the recorded reveal timeline plays through [PresentationPlayer]
## instead of the old presentation-hold latch machinery this file used to
## pin (#482/#487). A hit node's MODEL state moves synchronously inside
## `launch_attack` (#474, untouched here), but its PAINT — entity tint,
## allocation fill, shown HP — lags on the player's own clock until the
## recorded event's `t` elapses.
##
## Two halves:
##   1. With a live AttackVFX, the visuals do NOT follow the model until the
##      timeline's own wall-clock time has elapsed (`presentation_player.play`).
##   2. With no VFX at all, `launch_attack` calls `play_instant` — the whole
##      timeline lands at once, so a hit node never keeps its pre-hit look
##      past the attack that set it. This is the direct replacement for the
##      old `_flush_presentation` fail-closed guarantee.
##
## Fixture mirrors test_battle_system_outcome_sync.gd: chain core(0,0) —
## leaf(200,0) attacker side, lone hostile core at (250,0), ranged mode so no
## physics scan is needed.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _visuals(node: SkillNode) -> Node:
	return node.get_node("Visuals/NodeVisualsComposite")


func after_each() -> void:
	RevealRecorder.player = null
	if RevealRecorder.is_recording:
		RevealRecorder.end()


func _build(with_live_vfx: bool) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	core.position = Vector2(0, 0)
	graph.add_skill_node(core)

	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = Vector2(200, 0)
	graph.add_skill_node(leaf)
	graph.add_edge(core, leaf)

	var target := _SKILL_NODE_SCENE.instantiate() as SkillNode
	target.position = Vector2(250, 0)
	graph.add_skill_node(target)

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
	alloc.force_allocate(hostile, target)
	hostile.core_location = target

	_set_stat(leaf, &"range", 100.0)
	_set_stat(leaf, &"ranged_damage", 9999.0)  # overkill: guarantees a lethal hit
	# `core` is ALSO a graph-theoretic leaf of this 2-node chain (both ends of
	# core—leaf have degree 1), and `range`'s 400.0 default reaches `target` at
	# distance 250 same as `leaf` does at 50 — so without this, every test
	# below secretly fires a 2-hit volley instead of the single hit its
	# assertions assume (#487). Zero it so only `leaf` fires;
	# `test_multi_hit_volley_reveals_one_arrow_at_a_time` below is the one
	# test that deliberately restores it to exercise the 2-hit case.
	_set_stat(core, &"range", 0.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	var player := PresentationPlayer.new()
	add_child_autofree(player)
	bs.presentation_player = player
	RevealRecorder.player = player

	if with_live_vfx:
		var vfx := AttackVFX.new()
		add_child_autofree(vfx)
		bs.attack_vfx = vfx

	return {"bs": bs, "hostile": hostile, "target": target, "player": player}


## Not awaited on purpose — `launch_attack` is a coroutine that runs
## synchronously up to its first await (the player's own clock, or the VFX).
## Everything this test asserts about the withheld paint is observable right
## after control returns.
func _fire(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	bs.launch_attack()


func test_visuals_withhold_until_the_timeline_reveals_them() -> void:
	var ctx: Dictionary = await _build(true)
	var target: SkillNode = ctx.target
	var hostile: Entity = ctx.hostile
	var visuals := _visuals(target)

	_fire(ctx)

	# Model: already fully applied and cascaded, per #474.
	assert_null(target.owned_by, "model ownership must move synchronously (#474)")
	var timeline: RevealTimeline = ctx.bs.last_reveal_timeline
	assert_not_null(timeline, "fixture: the attack must have recorded a timeline")

	# Paint: still the pre-hit look. This is the whole point of the reveal
	# clock — the projectile is still in the air.
	assert_eq(visuals.allocation_level, 1,
			"allocation fill must not follow the model while the hit is in flight")
	assert_eq(visuals.entity_tint, hostile.color,
			"entity tint must not follow the model while the hit is in flight")

	await wait_seconds(timeline.duration() + 0.1)

	assert_eq(visuals.allocation_level, 0,
			"allocation fill catches up once the timeline plays through")
	assert_ne(visuals.entity_tint, hostile.color, "entity tint catches up too")


func test_visuals_release_immediately_with_no_vfx_at_all() -> void:
	var ctx: Dictionary = await _build(false)
	var target: SkillNode = ctx.target
	var visuals := _visuals(target)

	# No AttackVFX mounted — `launch_attack` calls `play_instant` instead of
	# `play`, so the WHOLE timeline lands synchronously and `launch_attack`
	# (which has no await to reach on this path) returns with the paint
	# already caught up. Direct replacement for the old
	# `_flush_presentation` fail-closed guarantee.
	_fire(ctx)

	assert_eq(visuals.allocation_level, 0,
			"with no VFX the reveal degrades to immediate, same contract as before")
	assert_ne(visuals.entity_tint, (ctx.hostile as Entity).color,
			"entity tint also catches up immediately")


func test_heal_target_lags_until_the_timeline_reveals_it() -> void:
	# The model heals synchronously inside _apply_outcome (#474), but the
	# shown HP waits for the recorded reveal to play through.
	var ctx: Dictionary = await _build(true)
	var target: SkillNode = ctx.target
	var bs: BattleSystem = ctx.bs
	var player: PresentationPlayer = ctx.player

	target.take_damage(5.0, null)
	assert_true(target.get_current_hp() < target.get_max_hp(),
			"fixture: target must be below full HP for a real heal")
	var pre_heal_shown := player.shown_hp(target)

	var heal := HealInstance.new()
	heal.target = target
	heal.amount = 999.0
	heal.arrival_time = 0.2
	var outcome := AttackOutcome.new()
	outcome.hits.append(heal)

	bs._apply_outcome(outcome)
	var timeline: RevealTimeline = bs.last_reveal_timeline
	player.play(timeline)

	assert_almost_eq(player.shown_hp(target), pre_heal_shown, 0.01,
			"the heal target's shown hp must lag until the reveal")
	assert_true(heal.effective_amount > 0.0 and heal.effective_amount <= 5.0,
			"heal_damage stamps the post-clamp effective amount")

	await wait_seconds(timeline.duration() + 0.1)

	assert_almost_eq(player.shown_hp(target), target.get_current_hp(), 0.01,
			"the reveal catches shown hp up to the model")


## #487: this is the reported bug, pinned. Two firing positions (both `core`
## and `leaf` reach `target` — see `_build`'s comment) means TWO hits on the
## SAME node in one outcome — the shown HP must step down ONE arrow at a
## time, on each hit's own recorded `arrival_time`, not jump straight to the
## fully-applied total. Non-lethal per-shot damage so the node survives both
## hits and the intermediate step is observable.
func test_multi_hit_volley_reveals_one_arrow_at_a_time() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	core.position = Vector2(0, 0)
	graph.add_skill_node(core)

	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = Vector2(200, 0)
	graph.add_skill_node(leaf)
	graph.add_edge(core, leaf)

	var target := _SKILL_NODE_SCENE.instantiate() as SkillNode
	target.position = Vector2(250, 0)
	graph.add_skill_node(target)

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
	alloc.force_allocate(hostile, target)
	hostile.core_location = target

	# `core`'s range stays at its 400.0 default (reaches target at 250); `leaf`
	# explicitly reaches too (50 <= 100) — both fire, in navigator leaf order.
	_set_stat(leaf, &"range", 100.0)
	_set_stat(leaf, &"ranged_damage", 3.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	var player := PresentationPlayer.new()
	add_child_autofree(player)
	bs.presentation_player = player
	RevealRecorder.player = player

	# A live AttackVFX so launch_attack plays the timeline on the wall clock
	# instead of `play_instant` — a null attack_vfx would land everything in
	# one frame, before this test ever gets to assert the mid-volley state.
	var vfx := AttackVFX.new()
	add_child_autofree(vfx)
	bs.attack_vfx = vfx

	var pre_hit_hp := target.get_current_hp()
	assert_true(pre_hit_hp > 6.0, "fixture: target must survive two 3-damage hits")

	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(target)
	assert_eq(plan.get_reaching_firing_positions().size(), 2,
			"fixture: both core and leaf must reach target for this to be a real volley")
	# resolve() is pure (no side effects on plan/world) — pin that the two
	# shots actually get DIFFERENT arrival times (launch stagger + distance,
	# #487/#480), not just different reveal slots. A coordinator/timeline that
	# revealed both at once would still pass a same-frame assertion; this is
	# what proves the two reveals are staggered in time at all.
	var pre_outcome := plan.resolve()
	assert_eq(pre_outcome.hits.size(), 2, "fixture: two shots, two hits")
	var t0: float = (pre_outcome.hits[0] as DamageInstance).arrival_time
	var t1: float = (pre_outcome.hits[1] as DamageInstance).arrival_time
	assert_ne(t0, t1, "the two shots must not be recorded to arrive at the same instant")
	bs.launch_attack()  # not awaited — see `_fire`'s docstring above

	# Model: both hits already landed (#474).
	assert_almost_eq(target.get_current_hp(), pre_hit_hp - 6.0, 0.01,
			"the model takes both hits synchronously, same as always")
	assert_almost_eq(player.shown_hp(target), pre_hit_hp, 0.01,
			"nothing has been revealed yet — shown HP is still the pre-hit value")

	# First arrow's reveal lands.
	await wait_seconds(minf(t0, t1) + 0.05)
	assert_almost_eq(player.shown_hp(target), pre_hit_hp - 3.0, 0.01,
			"shown HP steps down by exactly the first arrow's damage, not both hits' worth")

	# Second arrow's reveal lands.
	await wait_seconds(absf(t1 - t0) + 0.05)
	assert_almost_eq(player.shown_hp(target), target.get_current_hp(), 0.01,
			"shown HP now matches the model exactly")
