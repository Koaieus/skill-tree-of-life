extends GutTest
## Tooltip V2 engine accessors (#294): SkillNode identity + degree, StatBoard
## sparse enumeration, SkillNodeAddon identity surface. See #159/#294.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _XP_ANCHOR_KEYSTONE := preload("res://entity/keystone/instances/xp_anchor_keystone.tres")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const _SPIKE_RING_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")
const _SKILL_DUST_SCENE := preload("res://skill_node/addons/skill_dust_addon.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _make_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.add_skill_node(sn)
	return sn


func _spawn(core: SkillNode, owned: Array[SkillNode]) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	return ent


# ── SkillNode.get_display_name ──────────────────────────────────────────────

func test_display_name_empty_for_plain_node() -> void:
	var sn := _make_node("Plain")
	assert_eq(sn.get_display_name(), "")


func test_display_name_reads_keystone_display_name() -> void:
	var sn := _make_node("Stamped")
	_XP_ANCHOR_KEYSTONE.stamp(sn)
	assert_eq(sn.get_display_name(), "XP Anchor")


# ── SkillNode degree accessors ──────────────────────────────────────────────

## Hub with 5 neighbours; the entity owns the hub plus 2 of them.
func test_graph_degree_and_entity_degree() -> void:
	var hub := _make_node("Hub")
	var leaves: Array[SkillNode] = []
	for i in 5:
		var leaf := _make_node("Leaf%d" % i)
		_graph.add_edge(hub, leaf)
		leaves.append(leaf)

	assert_eq(hub.get_graph_degree(_graph), 5, "true vertex degree, ownership-agnostic")

	var ent: Entity = await _spawn(hub, [hub, leaves[0], leaves[1]])
	assert_eq(hub.get_entity_degree(_graph, ent), 2,
		"only neighbours owned by the same entity count")
	assert_lte(hub.get_entity_degree(_graph, ent), hub.get_graph_degree(_graph))


func test_degree_accessors_null_safe() -> void:
	var sn := _make_node("Lonely")
	assert_eq(sn.get_graph_degree(null), 0)
	assert_eq(sn.get_entity_degree(null, null), 0)
	assert_eq(sn.get_entity_degree(_graph, null), 0)


# ── StatBoard.get_dynamic_stat_ids ──────────────────────────────────────────

func test_dynamic_stat_ids_reports_only_sparse_extras() -> void:
	var board := StatBoard.new()
	assert_eq(board.get_dynamic_stat_ids(), [] as Array[StringName],
		"a fresh sparse board has no dynamic stats")

	board._ensure_stat(&"armor")
	board._ensure_stat(&"min_damage_taken")

	var ids := board.get_dynamic_stat_ids()
	assert_eq(ids.size(), 2)
	assert_true(ids.has(&"armor"))
	assert_true(ids.has(&"min_damage_taken"))


func test_dynamic_stat_ids_order_is_stable_across_calls() -> void:
	var board := StatBoard.new()
	board._ensure_stat(&"armor")
	board._ensure_stat(&"min_damage_taken")
	board._ensure_stat(&"node_healing")

	var first := board.get_dynamic_stat_ids()
	var second := board.get_dynamic_stat_ids()
	assert_eq(first, second)


func test_dynamic_stat_ids_does_not_create_a_stat() -> void:
	var sn := _make_node("Sparse")
	sn._init_node_board()
	# `stake_level` and `addon_slots` are node-OWNED, so they arrive baked as
	# typed NodeStatBoard fields rather than minted into _extra_stats — a fresh
	# board reports NO dynamic stats, and get_stat_ids() is what enumerates
	# everything live. The read-only promise below is about ENUMERATION: listing
	# ids must never create more stats.
	var no_dynamic: Array[StringName] = []
	assert_eq(sn.node_board.get_dynamic_stat_ids(), no_dynamic)
	var baked: Array[StringName] = [&"addon_slots", &"stake_level"]
	assert_eq(sn.node_board.get_stat_ids(), baked,
		"a UI enumerating the board must still see the baked node-only stats")
	assert_null(sn.node_board.get_stat(&"armor"),
		"enumeration must be read-only — no side-effect stat creation")


# ── SkillNodeAddon tooltip identity (the Bunker/Fortification bug fix) ──────

func _attach(node: SkillNode, scene: PackedScene) -> SkillNodeAddon:
	var addon := scene.instantiate() as SkillNodeAddon
	node.add_child(addon)
	return addon


func test_bunker_addon_tooltip_section_regression() -> void:
	var sn := _make_node("BunkerHost")
	_attach(sn, _BUNKER_SCENE)

	var sections := sn.get_addon_tooltip_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0]["title"], "Bunker")
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), 1)
	assert_eq(String(mods[0].stat_id), "armor")
	assert_eq(mods[0].operation, StatModifier.Operation.ADD_BONUS)
	assert_almost_eq(float(mods[0].value), 5.0, 0.001)


func test_fortification_addon_tooltip_section_regression() -> void:
	var sn := _make_node("FortHost")
	_attach(sn, _FORTIFICATION_SCENE)

	var sections := sn.get_addon_tooltip_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0]["title"], "Fortification")
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), 1)
	assert_eq(String(mods[0].stat_id), "node_health")
	assert_almost_eq(float(mods[0].value), 15.0, 0.001)


func test_spike_ring_keeps_its_authored_title_and_payload() -> void:
	var sn := _make_node("SpikeHost")
	# The blade_damage contribution is authored on `local_modifiers` in the
	# addon's own scene — _on_addon_added reads get_local_modifiers()
	# synchronously on add_child, so it must already be there.
	var addon := _SPIKE_RING_SCENE.instantiate() as SpikeRingAddon
	sn.add_child(addon)

	var sections := sn.get_addon_tooltip_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0]["title"], "Spikes")
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), 1)
	assert_eq(String(mods[0].stat_id), "blade_damage")


func test_skill_dust_keeps_its_authored_title_and_payload() -> void:
	var sn := _make_node("DustHost")
	var addon := _attach(sn, _SKILL_DUST_SCENE) as SkillDustAddon
	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.value = 2.0
	addon.candidates = [mod]

	var sections := sn.get_addon_tooltip_sections()
	assert_eq(sections.size(), 1)
	assert_eq(sections[0]["title"], "SkillDust loot")
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), 1)
	assert_eq(mods[0], mod)


func test_clamp_addon_default_title_and_description() -> void:
	var addon := _CLAMP_SCENE.instantiate() as SkillNodeAddon
	autofree(addon)
	assert_eq(addon.get_tooltip_title(), "Clamp")
	assert_false(addon.description.is_empty(), "Clamp's description must be authored")


func test_default_tooltip_modifiers_is_local_plus_entity_modifiers() -> void:
	var addon := SkillNodeAddon.new()
	autofree(addon)
	var local_mod := StatModifier.new()
	local_mod.stat_id = &"armor"
	var entity_mod := StatModifier.new()
	entity_mod.stat_id = &"strength"
	addon.local_modifiers = [local_mod]
	addon.entity_modifiers = [entity_mod]

	var mods := addon.get_tooltip_modifiers()
	assert_eq(mods.size(), 2)
	assert_true(mods.has(local_mod))
	assert_true(mods.has(entity_mod))
