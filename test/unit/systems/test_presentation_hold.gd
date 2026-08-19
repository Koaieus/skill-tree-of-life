extends GutTest

## #482 — the presentation hold. A hit node's MODEL state moves synchronously
## inside `launch_attack` (that is #474 and is untouched here), but its PAINT —
## entity tint and allocation fill — is withheld until the hit's VFX actually
## lands, announced by `Events.damage_shown` / `Events.node_death_shown`.
##
## Two halves, and the second is the one that matters most:
##   1. With a live AttackVFX the visuals do NOT follow the model — they wait.
##   2. With no VFX at all the latch must still let go by the time
##      `launch_attack` returns (`BattleSystem._flush_presentation`), or a hit
##      node would keep its pre-hit look forever. The hold fails CLOSED.
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
	# core—leaf have degree 1), and `range`'s 400.0 default (stats_system/defs/
	# range.tres) reaches `target` at distance 250 same as `leaf` does at 50 —
	# so without this, every test below secretly fires a 2-hit volley instead
	# of the single hit its assertions assume (#487). Zero it so only `leaf`
	# fires; `test_multi_hit_volley_reveals_one_arrow_at_a_time` below is the
	# one test that deliberately restores it to exercise the 2-hit case.
	_set_stat(core, &"range", 0.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	if with_live_vfx:
		var vfx := AttackVFX.new()
		add_child_autofree(vfx)
		bs.attack_vfx = vfx

	return {"bs": bs, "hostile": hostile, "target": target}


## Not awaited on purpose — `launch_attack` is a coroutine that runs
## synchronously up to its first await (the VFX). Everything this test asserts
## about the withheld paint is observable right after control returns.
func _fire(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	bs.launch_attack()


func test_visuals_withhold_until_damage_shown() -> void:
	var ctx: Dictionary = await _build(true)
	var target: SkillNode = ctx.target
	var hostile: Entity = ctx.hostile
	var visuals := _visuals(target)

	_fire(ctx)

	# Model: already fully applied and cascaded, per #474.
	assert_null(target.owned_by, "model ownership must move synchronously (#474)")
	assert_true(target.presentation_hold, "the target's paint must be withheld")

	# Paint: still the pre-hit look. This is the whole point of #482 — the
	# projectile is still in the air.
	assert_eq(visuals.allocation_level, 1,
			"allocation fill must not follow the model while the hit is in flight")
	assert_eq(visuals.entity_tint, hostile.color,
			"entity tint must not follow the model while the hit is in flight")

	# The hit lands, on the coordinator's arrival schedule.
	Events.damage_shown.emit(target, 9999.0)
	Events.node_death_shown.emit(target)

	assert_false(target.presentation_hold, "the reveal releases the hold")
	assert_eq(visuals.allocation_level, 0, "allocation fill catches up on reveal")
	assert_ne(visuals.entity_tint, hostile.color, "entity tint catches up on reveal")


func test_hold_is_released_even_with_no_vfx_at_all() -> void:
	var ctx: Dictionary = await _build(false)
	var target: SkillNode = ctx.target
	var visuals := _visuals(target)

	# No AttackVFX → no coordinator → nothing ever emits damage_shown on its
	# own. `_flush_presentation` emits it, so `launch_attack` (which has no
	# await to reach on this path) returns with the paint already caught up.
	_fire(ctx)

	assert_false(target.presentation_hold,
			"a hit node must never keep its latch past the attack that set it")
	assert_eq(visuals.allocation_level, 0,
			"with no VFX the reveal degrades to immediate, as before #482")


func test_flush_emits_the_presentation_events_it_owes() -> void:
	var ctx: Dictionary = await _build(false)
	var target: SkillNode = ctx.target
	watch_signals(Events)

	_fire(ctx)

	assert_signal_emitted(Events, "damage_shown",
			"the flush stands in for the coordinator that never ran")
	assert_signal_emitted(Events, "node_death_shown",
			"a hit that killed the node owes a death reveal too")
	assert_eq(get_signal_parameters(Events, "node_death_shown"), [target])


func test_heal_target_is_held_until_heal_shown() -> void:
	# #481/#482: a heal target's paint is withheld the same way a hit's is — the
	# model heals synchronously inside _apply_outcome, but the HP-bar rise and
	# the heal number wait for the VFX, released by Events.heal_shown.
	var ctx: Dictionary = await _build(true)
	var target: SkillNode = ctx.target
	var bs: BattleSystem = ctx.bs

	# Damage the target so the heal actually restores HP (and clamps against max).
	target.take_damage(5.0, null)
	assert_true(target.get_current_hp() < target.get_max_hp(),
			"fixture: target must be below full HP for a real heal")

	var heal := HealInstance.new()
	heal.target = target
	heal.amount = 999.0
	var outcome := AttackOutcome.new()
	outcome.hits.append(heal)

	bs._apply_outcome(outcome)

	assert_true(target.presentation_hold,
			"the heal target's paint must be withheld until the reveal")
	assert_true(heal.effective_amount > 0.0 and heal.effective_amount <= 5.0,
			"heal_damage stamps the post-clamp effective amount (#481/#482)")

	Events.heal_shown.emit(target, heal.effective_amount)

	assert_false(target.presentation_hold, "the heal reveal releases the hold")


func test_flush_emits_heal_shown_for_heal_targets() -> void:
	# #481/#482: with no coordinator the flush stands in for the heal reveal too, so
	# the latch can never outlive the attack that set it.
	var ctx: Dictionary = await _build(false)
	var target: SkillNode = ctx.target
	var bs: BattleSystem = ctx.bs

	target.take_damage(5.0, null)
	var heal := HealInstance.new()
	heal.target = target
	heal.amount = 999.0
	var outcome := AttackOutcome.new()
	outcome.hits.append(heal)
	watch_signals(Events)

	bs._apply_outcome(outcome)
	bs._flush_presentation(outcome)

	assert_signal_emitted(Events, "heal_shown",
			"the flush stands in for the coordinator that never ran")
	assert_false(target.presentation_hold,
			"a heal node must never keep its latch past the attack that set it")


## #487: this is the reported bug, pinned. Two firing positions (both `core`
## and `leaf` reach `target` — see `_build`'s comment) means TWO hits on the
## SAME node in one outcome, so `presentation_hold` must be a refcount: the
## first hit's reveal only steps the shown HP, and the paint/owner catch-up
## (and the target's own death announcement) must wait for the SECOND.
## Non-lethal per-shot damage so the node survives both hits and the
## intermediate step is observable — a lethal fixture would make the "still
## held after hit 1" assertion indistinguishable from "already fully dead".
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

	# A live AttackVFX so launch_attack awaits instead of flushing same-frame
	# (a null attack_vfx skips straight to `_flush_presentation`, which would
	# release both holds before this test ever gets to assert the mid-volley
	# state — see `_build`'s `with_live_vfx` param above).
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
	bs.launch_attack()  # not awaited — see `_fire`'s docstring above

	# Model: both hits already landed (#474).
	assert_almost_eq(target.get_current_hp(), pre_hit_hp - 6.0, 0.01,
			"the model takes both hits synchronously, same as always")
	assert_true(target.presentation_hold, "both hits' paint is withheld")
	assert_almost_eq(target.get_shown_hp(), pre_hit_hp, 0.01,
			"nothing has been revealed yet — shown HP is still the pre-hit value")

	# First arrow's reveal lands.
	Events.damage_shown.emit(target, 3.0)
	assert_true(target.presentation_hold,
			"one hold released, one still pending — the OLD boolean latch would fail this")
	assert_almost_eq(target.get_shown_hp(), pre_hit_hp - 3.0, 0.01,
			"shown HP steps down by exactly the first arrow's damage, not both hits' worth")

	# Second arrow's reveal lands.
	Events.damage_shown.emit(target, 3.0)
	assert_false(target.presentation_hold, "the second hit's reveal is what fully releases")
	assert_almost_eq(target.get_shown_hp(), target.get_current_hp(), 0.01,
			"shown HP now matches the model exactly")
