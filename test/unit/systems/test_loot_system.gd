extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## LootSystem (#68 XP reward + #69 SkillDust loot). On `Events.entity_died`:
##   * the killing-blow entity (attributed via TurnManager.current_entity at the
##     synchronous death) gains XP scaled by every node the attack REMOVED from
##     the victim, core included — never by its level — fed through the normal xp
##     pool (so it converts to SP / levels), with a per-node trickle paid off
##     BattleSystem's `cascade_started` as the attack goes;
##   * the victim's former core node becomes a relic carrying a SkillDustAddon
##     whose payload is a snapshot of the victim's modifiers; allocating that
##     relic pours the payload onto the collector's core.
##
## Death is triggered via the realistic core-overflow path (not bare die()), so
## the synchronous "snapshot-before-strip" ordering is actually exercised.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _loot: LootSystem
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _victim: Entity
var _killer: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	# Line: N0 (killer core) – N1 (victim core) – N2 (victim node).
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	# LootSystem listens to the pre-cleanup `entity_dying` phase, so its add order
	# relative to AllocationSystem (on `entity_died`) doesn't matter — the phase
	# split guarantees the snapshot reads still-owned nodes before the strip.
	_loot = LootSystem.new()
	_loot.turn_manager = _tm  # killer attribution source
	# XP tests set `xp_per_node_killed` / `entity_kill_bonus` explicitly; the
	# core loot draw keep-count follows `victim.entity_tier` (#300), so
	# keep-count tests pin that. The tier bonus (`tier_xp_base × tier²`) is
	# zeroed here — these tests pin the TERRITORY term; the tier term has its
	# own file (test_entity_tier_rewards.gd).
	_loot.tier_xp_base = 0.0
	add_child_autofree(_loot)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	# BattleSystem runs the forced-dealloc cascade (chip damage) off
	# skill_node_depleted — needed for the mid-cascade death path.
	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)
	# The removal ledger rides BattleSystem's cascade/attack signals. LootSystem
	# is already in the tree, so wire it the way game_root.tscn's NodePath does
	# and re-run the hookup.
	_loot.battle_system = _battle
	_battle.attack_launched.connect(_loot._on_attack_launched)
	_battle.cascade_started.connect(_loot._on_cascade_started)

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.faction = _PLAYER_FACTION  # #384/#386: HOSTILE to the victim's default npc faction
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED  # +10 STR/DEX/INT — the core-mod source
	_graph.add_child(_victim)

	await get_tree().process_frame  # _ready: navigators, health wiring, core_class.apply

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]

	var node_mods: Array[StatModifier] = [_mk_mod(&"armor", 3.0)]  # set X
	_nodes[2].modifiers = node_mods
	_alloc.force_allocate(_victim, _nodes[1])
	_alloc.force_allocate(_victim, _nodes[2])
	_victim.core_location = _nodes[1]


func _kill_victim() -> void:
	_tm.current_entity = _killer
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)  # overflow → health 0 → die()


# ── #68: XP reward ───────────────────────────────────────────────────────────

func test_killer_gains_xp_on_kill() -> void:
	# Victim holds N1 (core) + N2 → 2 nodes destroyed by the killing blow.
	_loot.xp_per_node_killed = 2.0
	_loot.entity_kill_bonus = 1.0  # isolate the node term
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before + 4.0,
			"kill XP = per_node * (held + core)")


func test_kill_xp_ignores_victim_level() -> void:
	# The rework: level is no longer an axis. D-19 already pins enemy level to
	# starting node count, so paying for both double-counted one fact.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_victim.level = 17
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 2.0,
			"a level-17 victim holding 2 nodes pays exactly the 2 nodes")


func test_kill_xp_scales_with_territory_held_at_death() -> void:
	# Strip N2 first: the same victim, one node smaller, pays proportionally less.
	_alloc.force_deallocate(_nodes[2])
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 1.0, "core-only victim pays for its core alone")


func test_entity_kill_bonus_multiplies_the_payout() -> void:
	# The premium that makes going for the throat worth more than grinding limbs.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 2.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 4.0, "2 nodes * 1 XP * 2.0 bonus")


func test_xp_award_routes_through_level_up() -> void:
	# Award >= xp cap (5) → fills the pool → the normal replenished cascade
	# levels the killer and mints 1 SP (proves we go through the pool, not a
	# raw set_current that would skip it).
	_loot.xp_per_node_killed = 5.0
	_loot.entity_kill_bonus = 1.0
	var lvl_before := _killer.level
	var sp_before := _killer.stat_board.skill_points.current
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 1, "kill XP filling the pool levels the killer")
	# #271: a level-up mints `sp_gain_on_levelup` (default 2), not a hardcoded 1.
	var sp_gain := float(_killer.stat_board.get_value(&"sp_gain_on_levelup"))
	assert_eq(_killer.stat_board.skill_points.current, sp_before + sp_gain,
			"level-up mints sp_gain_on_levelup SP")


func test_a_big_kill_cascades_through_several_levels() -> void:
	# The rework multiplied award SIZE by ~40x: at defaults, a first_level enemy
	# (20 nodes) pays 20 * 5 * 2 = 200 XP into a pool whose cap starts at 5. That
	# only works because the xp def is OVERFLOW mode — `on_pool_filled` re-enters
	# `set_current` with the excess and cascades. If that ever regresses to KEEP
	# or RESET, a 200 XP kill silently pays ONE level and bins the rest.
	_loot.xp_per_node_killed = 5.0
	_loot.entity_kill_bonus = 2.0
	var lvl_before := _killer.level
	# Victim holds 2 nodes → 2 * 5 * 2 = 20 XP. Caps run 5 then 10 (growth_flat 5),
	# consuming 15 across two level-ups; the remaining 5 sits in the new cap-15 pool.
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 2, "a 20 XP award cascades through both level-ups")
	assert_eq(_killer.stat_board.xp.current, 5.0, "the remainder carries in, nothing is binned")
	assert_eq(float(_killer.stat_board.xp.get_value()), 15.0, "cap grew once per level")


func test_self_death_grants_no_xp() -> void:
	# No entity holds the turn → no killer attribution → no reward.
	_tm.current_entity = null
	var before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no killer → no XP")


func test_ally_kill_grants_no_xp() -> void:
	# #384/#386: the HOSTILE gate on the kill-bonus path. Same faction as the
	# victim → ALLIED, so even a real killing blow earns nothing.
	_killer.faction = _NPC_FACTION
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before, "an ally kill pays no XP")
	assert_not_null(_find_dust(_nodes[1]), "SkillDust is a world drop — stays ungated")


func test_ally_node_kill_pays_no_trickle() -> void:
	# Same gate on the cascade trickle path (`_on_cascade_started`).
	_killer.faction = _NPC_FACTION
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _killer
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no XP for whittling an ally's territory")


func test_bystander_enemy_gains_no_xp_from_anothers_kill() -> void:
	# A third HOSTILE entity must not be credited just because it's also hostile
	# to the victim — only the entity holding the turn (the actual killer) is paid.
	var bystander: Entity = autofree(Entity.new())
	bystander.display_name = "Bystander"
	bystander.faction = _PLAYER_FACTION  # hostile to the npc-faction victim too
	bystander.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(bystander)
	await get_tree().process_frame

	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	var bystander_before: float = bystander.stat_board.xp.current
	_kill_victim()  # _tm.current_entity = _killer, not bystander
	assert_eq(bystander.stat_board.xp.current, bystander_before,
			"only the attributed killer is paid, not every hostile entity")


func test_destroying_a_node_pays_the_trickle() -> void:
	# #182: whittling a limb pays per node, without an entity dying. Riding the
	# cascade (not `skill_node_depleted`) is what makes the defender readable —
	# the strip clears `owned_by` in that same loop.
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _killer
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)  # leaf, victim survives
	assert_false(_victim.is_dead, "the victim is only losing a limb here")
	assert_eq(_killer.stat_board.xp.current, before + 3.0, "one destroyed node → one trickle")


func test_destroying_your_own_node_pays_nothing() -> void:
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _victim  # the victim is the one acting
	var before := _victim.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_victim.stat_board.xp.current, before, "no XP for destroying your own territory")


func test_node_kill_switch_suppresses_the_trickle() -> void:
	_loot.award_xp_on_node_kill = false
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _killer
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "trickle disabled → no XP")


# ── Per-side-effect kill-switches (sandbox modularity) ───────────────────────

func test_drop_skill_dust_off_suppresses_relic() -> void:
	_loot.drop_skill_dust_on_death = false
	_loot.xp_per_node_killed = 1.0  # sub-cap → no level-up reset, current is observable
	_loot.entity_kill_bonus = 1.0
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_null(_find_dust(_nodes[1]), "dust drop disabled → no relic on former core")
	# Other side-effects untouched: XP still awarded.
	assert_eq(_killer.stat_board.xp.current, before + 2.0, "XP reward still fires when only dust is off")


func test_award_xp_off_suppresses_xp() -> void:
	_loot.award_xp_on_kill = false
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before, "xp award disabled → no XP")
	# Other side-effects untouched: dust still drops.
	assert_not_null(_find_dust(_nodes[1]), "dust still drops when only XP is off")


# ── #69/#173: SkillDust loot drop (CORE-ONLY) ────────────────────────────────

func test_skilldust_dropped_on_former_core() -> void:
	_kill_victim()
	var dust := _find_dust(_nodes[1])  # victim's former core
	assert_not_null(dust, "former core should carry a SkillDustAddon relic")
	assert_false(dust.candidates.is_empty(), "dust holds the core-mod candidates")


func test_loot_draws_from_all_three_provenance_buckets() -> void:
	# #323 re-cut: provenance replaces "scales with level" as the lootability
	# axis. N2's armor (a node grant) MUST now appear — node mods are LENT by
	# the graph and still return to it on death (the strip is untouched), but a
	# DUPLICATED copy is now an honest loot candidate, not excluded outright.
	_victim.level = 5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var stat_ids: Array[StringName] = []
	for m in dust.candidates:
		stat_ids.append(m.stat_id)
	assert_true(&"armor" in stat_ids, "node-grant bucket is now part of the draw")
	assert_true(&"strength" in stat_ids or &"dexterity" in stat_ids
			or &"intelligence" in stat_ids, "class/register bucket is still drawn")
	var innate_ids: Array[StringName] = []
	for m in _victim.stat_board.intrinsic_modifiers:
		innate_ids.append((m as StatModifier).stat_id)
	var saw_innate := false
	for m in dust.candidates:
		if m.stat_id in innate_ids:
			saw_innate = true
			break
	assert_true(saw_innate, "board-innate bucket is drawn too")


func test_lootable_supply_is_the_union_of_all_three_buckets() -> void:
	# Supply = |node grants| + |class register| + |board innates|, expanded for
	# loot the same way each bucket's own reader would report it. Computed from
	# the fixture rather than a hardcoded literal, so it doesn't rot when the
	# shared default board's intrinsic set changes.
	var expected := _loot._expand_for_loot(_loot._node_grant_modifiers(_victim)).size() \
			+ _loot._expand_for_loot(_loot._core_modifiers(_victim)).size() \
			+ _loot._expand_for_loot(_loot._innate_modifiers(_victim)).size()
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), expected, "M = union of the three buckets")


func test_keep_count_is_victim_tier() -> void:
	# #300: N = victim.entity_tier (replaces the old level-scaled core_keep
	# formula), clamped to the TOTAL pool across all three buckets.
	_victim.entity_tier = 2
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, 2, "N = victim.entity_tier = 2")


func test_keep_count_never_saturates_the_supply() -> void:
	# A keep-count that reaches M turns pick-1-of-3-per-round into "take
	# everything" — the picker never pops. The draw must always leave at least
	# one on the table, so an absurdly high tier is still capped below M.
	_victim.entity_tier = 100
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_lt(dust.rounds, dust.candidates.size(),
			"N is capped below M so the choice survives")


func test_loot_and_xp_fire_on_mid_cascade_death() -> void:
	# Deplete N2 (a leaf) with health at 1 and dealloc_damage 1: the forced-dealloc
	# cascade's chip damage drops health to 0, so die() — and thus LootSystem —
	# fires RE-ENTRANTLY while BattleSystem is still iterating the cascade loop.
	# The rewards must still land (and not crash) on this real combat trigger.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_tm.current_entity = _killer
	var xp_before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_nodes[2].take_damage(10000.0, null)  # deplete N2 → cascade → chip kill
	assert_true(_victim.is_dead, "chip damage should kill the victim mid-cascade")
	# 1 (N2 destroyed, the trickle) + 1 (the kill: core only, N2 already gone).
	assert_eq(_killer.stat_board.xp.current, xp_before + 2.0, "XP awarded despite re-entrant death")
	assert_not_null(_find_dust(_nodes[1]), "SkillDust dropped on the former core mid-cascade")


func test_addon_tooltip_sections_surface_skilldust_payload() -> void:
	# The hover-tooltip content contract: a node aggregates its addons' tooltip
	# sections; SkillDust contributes its candidate list under a titled section.
	_victim.level = 3
	_kill_victim()
	var sections := _nodes[1].get_addon_tooltip_sections()
	assert_eq(sections.size(), 1, "one addon section (the SkillDust relic)")
	assert_eq(sections[0]["title"], "SkillDust loot", "section is titled")
	var dust := _find_dust(_nodes[1])
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), dust.candidates.size(), "section mirrors the candidates")
	assert_false(mods.is_empty(), "candidates are listed for the tooltip")


func test_pickup_auto_resolves_picked_core_mods_to_collector_core() -> void:
	# No HUD in this harness → each round auto-resolves (random 1 of up to 3).
	# Exactly `rounds` mods land on the collector's board AND its register
	# (#185/#323 — a looted grant is re-lootable through the register), not the
	# relic's core node.
	_victim.entity_tier = 2  # N = 2 rounds → a real choice
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, 2, "N = 2")
	_killer.stat_board.skill_points.grant(5)  # ensure SP to afford the allocation
	var reg_before := _killer.core_modifiers.size()
	# Killer allocates the neutral relic (adjacent to its N0 core).
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer can allocate the neutral relic node")
	assert_eq(_killer.core_modifiers.size(), reg_before + 2,
			"exactly N=2 rounds each grant one modifier into the collector's register")
	await get_tree().process_frame  # queue_free is deferred to frame end
	assert_null(_find_dust(_nodes[1]), "dust consumes itself once every round has resolved")


# ── #173: the pick-N-from-M handshake at claim time ──────────────────────────
# Exercise the branch a trivial core can't: a REAL choice (M > N) where
# SkillDustAddon actually emits `loot_pick_requested`.


func test_no_handler_auto_resolves_a_strict_subset() -> void:
	# Real NPC play: nobody claims the pick → SkillDustAddon auto-resolves a
	# RANDOM 1-of-3 each round. Exactly N rounds' worth of mods must land in the
	# collector's register (not the whole pool, not zero). XP is zeroed so a
	# level-up doesn't also mutate the board via mod_level_to_con mid-test.
	_loot.xp_per_node_killed = 0.0
	_victim.entity_tier = 2
	var reg_before := _killer.core_modifiers.size()
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, 2, "N rounds to run")
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer allocates the relic")
	assert_eq(_killer.core_modifiers.size(), reg_before + 2,
			"auto-resolve grants exactly N=2 rounds' worth of mods")


func test_claimed_request_suppresses_auto_resolve_until_picker_resolves() -> void:
	# A UI consumer sets `claim = LOCAL` synchronously → the addon must NOT
	# auto-resolve THAT ROUND. The round stays pending until the picker calls
	# resolve() — and the NEXT round's request doesn't fire until it does,
	# since `_grant_and_advance` (the resolver) is what drives `_advance_round`.
	_loot.xp_per_node_killed = 0.0
	_victim.entity_tier = 2
	var captured: Array[LootPickRequest] = []
	var handler := func(req: LootPickRequest) -> void:
		req.claim = LootPickRequest.Claim.LOCAL
		captured.append(req)
	Events.loot_pick_requested.connect(handler)

	var reg_before := _killer.core_modifiers.size()
	_kill_victim()
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer allocates the relic")
	assert_eq(captured.size(), 1, "only round 1's request reached the handler so far")
	assert_gt(captured[0].candidates.size(), 1,
		"a round offers a real choice — one survivor auto-grants instead")
	# Nothing granted yet — auto-resolve was suppressed, round 1 is pending.
	assert_eq(_killer.core_modifiers.size(), reg_before,
		"claimed → round 1 still pending, nothing granted yet")
	assert_false(captured[0].is_resolved(), "request awaits the player's pick")

	# Resolve round 1 → round 2's request fires (still connected to `handler`).
	captured[0].resolve([captured[0].candidates[0]])
	assert_eq(_killer.core_modifiers.size(), reg_before + 1,
		"round 1's pick landed in the register")
	assert_eq(captured.size(), 2, "resolving round 1 drove round 2's request")

	captured[1].resolve([captured[1].candidates[0]])
	assert_eq(_killer.core_modifiers.size(), reg_before + 2,
		"round 2's pick landed too — N=2 rounds total")
	Events.loot_pick_requested.disconnect(handler)


# ── #323: sequential would_cycle filtering closes the joint-cycle gap ────────

func test_sequential_would_cycle_filtering_closes_the_joint_cycle_gap() -> void:
	# Two candidates, each individually cycle-safe, but jointly cyclic:
	# strength reads dexterity; dexterity reads strength. A single up-front
	# filter (checked once against the board as it stood at draw time) would
	# let BOTH through — the second `add_modifier` would then hit the board's
	# own last-resort rejection. The per-round claim-time filter must not: once
	# round 1 binds the first, round 2's `would_cycle` check sees it on the
	# board and excludes the second before it's ever offered.
	var mod_a := StatModifier.new()
	mod_a.stat_id = &"strength"
	var f_a := LinearFormula.new()
	f_a.source_stat_id = &"dexterity"
	mod_a.formula = f_a

	var mod_b := StatModifier.new()
	mod_b.stat_id = &"dexterity"
	var f_b := LinearFormula.new()
	f_b.source_stat_id = &"strength"
	mod_b.formula = f_b

	# A free relic adjacent to the killer's core to allocate onto.
	var relic := _SKILL_NODE_SCENE.instantiate() as SkillNode
	relic.name = "Relic"
	_graph.skill_nodes_container.add_child(relic)
	_add_edge(_nodes[0], relic)

	var dust := SkillDustAddon.new()
	dust.candidates = [mod_a, mod_b]
	dust.weights = [1.0, 1.0]
	dust.rounds = 2
	relic.add_child(dust)

	var captured: Array[LootPickRequest] = []
	var handler := func(req: LootPickRequest) -> void:
		req.claim = LootPickRequest.Claim.LOCAL
		captured.append(req)
	Events.loot_pick_requested.connect(handler)

	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(relic, _killer)
	assert_true(ok, "killer allocates the relic")

	assert_eq(captured.size(), 1, "round 1 offers a real 2-way choice")
	assert_eq(captured[0].candidates.size(), 2, "both are individually cycle-safe at round 1")
	captured[0].resolve([mod_a])  # bind "strength reads dexterity" first

	assert_eq(_killer.core_modifiers.size(), 1, "round 1's pick landed")
	assert_true(_killer.core_modifiers.has(mod_a))
	assert_eq(captured.size(), 1, "round 2 never emitted a request — no cycle-safe survivor left")
	assert_false(_killer.core_modifiers.has(mod_b),
			"the jointly-cyclic candidate is excluded once round 1 is bound, never granted")

	Events.loot_pick_requested.disconnect(handler)


# ── #323: enemies loot from players too (symmetry, not gated by faction) ─────

func test_npc_loots_a_relic_dropped_by_a_player_victim() -> void:
	# "Do enemies loot from players?" — yes, already true by construction:
	# SkillDust loot goes to whoever ALLOCATES the relic (`carrier.owned_by`),
	# not the killer specifically, and nothing in the drop or claim path gates
	# on faction (only the XP reward does — see test_ally_kill_grants_no_xp).
	# Flip the usual fixture: the VICTIM is player-faction, the CLAIMANT is
	# npc-faction, same as an NPC scavenging a dead player's relic.
	_victim.faction = _PLAYER_FACTION
	_killer.faction = _NPC_FACTION
	_victim.entity_tier = 1
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_not_null(dust, "a player's death still drops a relic")

	var reg_before := _killer.core_modifiers.size()
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "an NPC entity can allocate a relic a player dropped")
	assert_gt(_killer.core_modifiers.size(), reg_before,
			"the NPC claimant receives the SkillDust payload like anyone else")


# ── D-27/#279: loots_as_unit pack expansion ───────────────────────────────────

func test_expand_for_loot_splits_a_false_pack_into_separate_candidates() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [_mk_mod(&"strength", 10.0), _mk_mod(&"dexterity", 10.0)]

	var expanded: Array[StatModifier] = [pack]
	expanded = _loot._expand_for_loot(expanded)

	assert_eq(expanded.size(), 2, "a false pack expands into one candidate per child")
	assert_false(expanded[0] is CompositeStatModifier, "expanded entries are the leaves, not the pack")


func test_expand_for_loot_keeps_a_true_pack_as_one_candidate() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = true
	pack.children = [_mk_mod(&"deallocation_points", 2.0), _mk_mod(&"skill_points", -1.0)]

	var expanded: Array[StatModifier] = [pack]
	expanded = _loot._expand_for_loot(expanded)

	assert_eq(expanded.size(), 1, "a true pack stays a single all-or-nothing candidate")
	assert_same(expanded[0], pack, "the whole pack is the candidate, unflattened")


func test_level_scaling_no_longer_excludes_a_mod_from_the_pool() -> void:
	# #323 re-cut: `_is_lootable`'s old `scales_with(&"level")` exclusion is
	# GONE — stealing a level-scaler is the intended roguelite loop now, not a
	# hazard to filter out. A `+1 STR per level` child inside a `false` pack
	# (expanded to a per-leaf candidate, same as any static sibling) survives
	# right alongside the static one.
	var scaled := _mk_mod(&"strength", 1.0)
	var f := LinearFormula.new()
	f.source_stat_id = &"level"
	scaled.formula = f
	var static_mod := _mk_mod(&"dexterity", 10.0)

	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [scaled, static_mod]

	var expanded: Array[StatModifier] = [pack]
	var out := _loot._expand_for_loot(expanded)

	assert_eq(out.size(), 2, "both children survive — no level filter anymore")
	var stat_ids: Array[StringName] = [out[0].stat_id, out[1].stat_id]
	assert_true(&"strength" in stat_ids, "the level-scaling child is now lootable")
	assert_true(&"dexterity" in stat_ids, "the static child stays lootable too")


# ── helpers ──────────────────────────────────────────────────────────────────

func _attr_sum(e: Entity) -> float:
	# All FIVE attributes — BalancedCore grants +10 to each since #271. Summing
	# only STR/DEX/INT would under-report whenever the random draw picks CON or
	# WIS, which reads as "fewer mods granted" rather than "wrong sum".
	var b := e.stat_board
	return (b.strength.value + b.dexterity.value + b.intelligence.value
			+ b.constitution.value + b.wisdom.value)


func _find_dust(node: SkillNode) -> SkillDustAddon:
	for a in node.get_addons():
		if a is SkillDustAddon:
			return a as SkillDustAddon
	return null


func _mk_mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
