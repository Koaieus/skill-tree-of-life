extends GutTest

## The claim half of #604: an NPC that kills something ACTUALLY collects the
## relic. Every other loot test drives the claim by calling
## `AllocationSystem.allocate()` by hand; this one lets an [AIController] decide
## for itself, and the allocation reaches the relic as the [AllocateCommand] the
## AI submits through the one [CommandApplier] — the path a real NPC turn takes,
## and the only one where [SkillDustAddon]'s host gate and its command chain are
## both live.
##
## What it pins is the whole sentence "kill the blocker, take their loot,
## expand": the AI is boxed in, shoots its way out, and — because nothing on
## this machine claims the pick requests — auto-resolves a random 1-of-N for
## each stat round AND the terminal spell round, all inside its own turn.
##
## Fixture is test_ai_controller_combat.gd's, plus a [LootSystem] (which those
## tests deliberately omit) and a victim carrying both loot payloads.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
## Not innate (spellbook_default.tres holds spark + lightning_bolt), so it
## survives `_exclude_permanently_known` and the terminal round has something
## real to offer.
const _LOOT_SPELL := preload("res://attack/spell/defs/leafblower.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _bs: BattleSystem
var _loot: LootSystem
var _idle: Entity
var _ai_entity: Entity
var _victim: Entity
var _nodes: Array[SkillNode] # N0 (AI core) - N1 (AI leaf) - N2 (victim core -> relic)


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.instant_mutation = true # decisions, not presentation timing
	add_child(_bs)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _bs
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	# The system under test on the loot side. Wired the way game_root.tscn's
	# NodePaths do it, including the applier — so the claim runs as a real
	# LootRoundCommand chain rather than the inline no-pipeline fallback.
	_loot = LootSystem.new()
	_loot.turn_manager = _tm
	_loot.command_applier = _applier
	_loot.xp_per_node_killed = 0.0
	_loot.entity_kill_bonus = 0.0
	_loot.tier_xp_base = 0.0
	add_child_autofree(_loot)
	_loot.battle_system = _bs
	_bs.attack_launched.connect(_loot._on_attack_launched)
	_bs.cascade_started.connect(_loot._on_cascade_started)

	# Idle entity so the clock parks somewhere after the AI ends its turn.
	_idle = _make_entity("Idle")
	_graph.entities_container.add_child(_idle)
	_idle.add_child(PlayerController.new())

	_ai_entity = _make_entity("Npc")
	_graph.entities_container.add_child(_ai_entity)
	var ai := AIController.new()
	ai.turn_delay = 0.0
	ai.command_applier_override = _applier
	ai.battle_system_override = _bs
	_ai_entity.add_child(ai)

	_victim = _make_entity("Victim", _PLAYER_FACTION)
	_victim.core_class = _BALANCED # +10 STR/DEX/INT — the stat-round candidates
	_victim.entity_tier = 2        # N = 2 stat rounds
	_graph.entities_container.add_child(_victim)

	await get_tree().process_frame

	_alloc.force_allocate(_ai_entity, _nodes[0])
	_ai_entity.core_location = _nodes[0]
	_alloc.force_allocate(_ai_entity, _nodes[1])
	_alloc.force_allocate(_victim, _nodes[2])
	_victim.core_location = _nodes[2]
	_victim.get_spellbook().learn(_LOOT_SPELL)

	_nodes[0].global_position = Vector2.ZERO
	_nodes[1].global_position = Vector2(100.0, 0.0)
	_nodes[2].global_position = Vector2(200.0, 0.0)

	# One shot from a kill: node HP down to 1 AND the entity's health pool down
	# to 1, so the first hit depletes the core node and the overflow carries
	# into the death the relic drops from. Node depletion alone is not a death
	# — the health pool absorbs it (same setup test_loot_system.gd uses).
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.amount = _nodes[2].get_current_hp() - 1.0
	_nodes[2].take_damage(dmg.amount, dmg)
	_victim.stat_board.health.set_current(1.0)
	_ai_entity.stat_board.skill_points.set_current(2)


func _spell_ids(e: Entity) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in e.get_spellbook().spells:
		out.append(s.id)
	return out


func test_an_ai_kill_ends_with_the_relic_claimed_and_both_payouts_taken() -> void:
	var mods_before := _ai_entity.core_modifiers.size()
	assert_false(_spell_ids(_ai_entity).has(_LOOT_SPELL.id), "fixture guard: not known yet")

	_tm.start_turn(_ai_entity)
	await get_tree().create_timer(0.4).timeout

	assert_true(_victim.is_dead, "the AI finished the kill")
	assert_eq(_nodes[2].owned_by, _ai_entity, "and allocated the relic it dropped")
	assert_eq(_ai_entity.core_modifiers.size(), mods_before + 2,
			"two stat rounds, each auto-resolved to a random 1 of the offer")
	assert_true(_spell_ids(_ai_entity).has(_LOOT_SPELL.id),
			"and the terminal spell round handed over a spell the victim knew")


func test_the_npc_claim_pops_no_picker_and_leaves_no_round_pending() -> void:
	# Nobody claims either request — the auto-resolve branch. The relic must
	# consume itself rather than parking a round forever waiting for a picker
	# that no NPC has.
	var stat_requests: Array[LootPickRequest] = []
	var spell_requests: Array[SpellLootRequest] = []
	var on_stat := func(r: LootPickRequest) -> void: stat_requests.append(r)
	var on_spell := func(r: SpellLootRequest) -> void: spell_requests.append(r)
	Events.loot_pick_requested.connect(on_stat)
	Events.spell_loot_requested.connect(on_spell)

	_tm.start_turn(_ai_entity)
	await get_tree().create_timer(0.4).timeout

	Events.loot_pick_requested.disconnect(on_stat)
	Events.spell_loot_requested.disconnect(on_spell)

	assert_gt(stat_requests.size() + spell_requests.size(), 0,
			"the offers were raised — an NPC is offered the same choice a player is")
	for r in stat_requests:
		assert_eq(r.claim, LootPickRequest.Claim.UNCLAIMED,
				"no HUD on this machine claims an NPC's pick")
	await get_tree().process_frame
	assert_eq(_applier.pending_count(), 0, "the round chain drained")
	assert_null(_find_dust(_nodes[2]), "and the relic consumed itself")


func _find_dust(node: SkillNode) -> SkillDustAddon:
	for a in node.get_addons():
		if a is SkillDustAddon:
			return a as SkillDustAddon
	return null
