extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## LootSystem's spellbook draft (#204, widened post-#204 — see loot_system.gd's
## "#204: Spellbook loot draft" comment) — the killer draft-picks a spell off
## the victim's FULL spellbook (core, innate, AND territory-sourced), on the
## same pre-cleanup `Events.entity_dying` phase as the SkillDust drop (#173).
## Fixture mirrors test_loot_system.gd: a line graph, killer + victim
## entities, death triggered via the realistic core-overflow path.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")

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
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	# N0 (killer core) – N1 (victim core) – N2 (victim territory)
	# N0 (killer core) – N3 (killer territory)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])
	_add_edge(_nodes[0], _nodes[3])

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	_loot = LootSystem.new()
	_loot.turn_manager = _tm
	_loot.xp_per_node_killed = 0.0
	_loot.drop_skill_dust_on_death = false  # isolate the spell draft
	add_child_autofree(_loot)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED
	_graph.add_child(_victim)

	await get_tree().process_frame  # _ready: navigators, health wiring, core_class.apply

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]
	_alloc.force_allocate(_killer, _nodes[3])

	_alloc.force_allocate(_victim, _nodes[1])
	_alloc.force_allocate(_victim, _nodes[2])
	_victim.core_location = _nodes[1]


func _kill_victim() -> void:
	_tm.current_entity = _killer
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)  # overflow → health 0 → die()


func _mk_spell(spell_name: String) -> SpellDef:
	var s := SpellDef.new()
	s.name = spell_name
	return s


## Innate: null is a permanent pseudo-source in `_sources` — remove_spell
## refuses to remove it, so it can never be ref-counted away (see
## entity/spell_book.gd's add_spell/permanent_spells docs).
func _grant_innate(book: SpellBook, spell: SpellDef) -> void:
	book.add_spell(spell, null)


## Territory/core-sourced: ref-counted against `source_node`.
func _grant_from(book: SpellBook, spell: SpellDef, source_node: SkillNode) -> void:
	book.add_spell(spell, source_node)


# ── Acceptance #1: core AND territory spells offered, capped at 3 ───────────

func test_offers_core_and_territory_spells_capped_at_three() -> void:
	_victim.spellbook = SpellBook.new()
	var core_a := _mk_spell("CoreA")
	var core_b := _mk_spell("CoreB")
	var territory := _mk_spell("Territory")
	_grant_from(_victim.spellbook, core_a, _victim.core_location)
	_grant_from(_victim.spellbook, core_b, _victim.core_location)
	_grant_from(_victim.spellbook, territory, _nodes[2])  # territory-sourced — lootable

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)

	_kill_victim()

	assert_eq(captured.size(), 1, "one spell draft fired")
	assert_eq(captured[0].candidates.size(), 3, "all 3 known spells offered")
	assert_true(captured[0].candidates.has(core_a))
	assert_true(captured[0].candidates.has(core_b))
	assert_true(captured[0].candidates.has(territory), "territory-sourced spell is lootable")
	Events.spell_loot_requested.disconnect(handler)


func test_offer_capped_at_three_when_victim_knows_more() -> void:
	_victim.spellbook = SpellBook.new()
	var spells: Array[SpellDef] = []
	for i in 4:
		var s := _mk_spell("Spell%d" % i)
		spells.append(s)
		_grant_from(_victim.spellbook, s, _nodes[2])

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)

	_kill_victim()

	assert_eq(captured.size(), 1)
	assert_eq(captured[0].candidates.size(), 3, "offer capped at 3 even with 4 known spells")
	Events.spell_loot_requested.disconnect(handler)


# ── Acceptance #2: chosen spell lands on killer's core, survives dealloc ────

func test_chosen_spell_lands_on_killer_core_and_survives_unrelated_dealloc() -> void:
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("Fireball")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)

	_kill_victim()
	assert_eq(captured.size(), 1)
	captured[0].resolve([spell])
	Events.spell_loot_requested.disconnect(handler)

	assert_true(_killer.spellbook != null and spell in _killer.spellbook.spells,
			"chosen spell landed in the killer's spellbook")
	assert_true(_killer.core_location in _killer.spellbook._sources.get(spell, []),
			"sourced by the killer's core node")

	# Deallocating an unrelated node (N3, killer's territory) must not strip it —
	# the grant lives on the killer's CORE, not on N3.
	_alloc.force_deallocate(_nodes[3])
	assert_true(spell in _killer.spellbook.spells, "core-sourced spell survives unrelated dealloc")


# ── Acceptance #3: NPC / headless auto-resolves, never hangs ────────────────

func test_headless_kill_auto_resolves_a_random_pick() -> void:
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("Bolt")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	# No handler connected at all — the emitter must auto-resolve, not hang.
	_kill_victim()

	assert_true(_killer.spellbook != null and spell in _killer.spellbook.spells,
			"auto-resolve granted the only candidate")


# ── Acceptance #4: kill-switch neuters the path ──────────────────────────────

func test_kill_switch_off_neuters_spell_loot() -> void:
	_loot.award_spell_loot_on_death = false
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("Bolt")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	var fired := false
	var handler := func(_req: SpellLootRequest) -> void: fired = true
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_false(fired, "kill-switch off → no request emitted")
	assert_true(_killer.spellbook == null or not (spell in _killer.spellbook.spells),
			"kill-switch off → nothing learned")


# ── Acceptance #5: snapshot at entity_dying, before the strip ───────────────

func test_core_spell_still_offered_at_entity_dying_despite_imminent_strip() -> void:
	# The spell is sourced by the victim's core — AllocationSystem's `entity_died`
	# strip (which runs AFTER entity_dying) would otherwise revoke it. Proves the
	# draw reads the pre-strip world.
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("LastGasp")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_eq(captured.size(), 1, "draft fired before the strip removed the spell")
	assert_true(captured[0].candidates.has(spell))


# ── Acceptance #6: idempotent resolve ────────────────────────────────────────

func test_resolve_is_idempotent_cannot_double_learn() -> void:
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("Bolt")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	captured[0].resolve([spell])
	captured[0].resolve([spell])  # second call must be a no-op

	assert_eq(_killer.spellbook.source_count(spell), 1,
			"double-resolve doesn't double-grant (still 1 source: the killer's core)")


# ── Acceptance #7: known-filter ──────────────────────────────────────────────

func test_permanently_known_spell_excluded_territory_known_offered() -> void:
	_victim.spellbook = SpellBook.new()
	var known_spell := _mk_spell("AlreadyKnown")
	var new_spell := _mk_spell("NewOne")
	_grant_from(_victim.spellbook, known_spell, _victim.core_location)
	_grant_from(_victim.spellbook, new_spell, _victim.core_location)

	# Killer already knows `known_spell` PERMANENTLY (core-sourced) — must be excluded.
	_killer.spellbook = SpellBook.new()
	_grant_from(_killer.spellbook, known_spell, _killer.core_location)

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_eq(captured.size(), 1)
	assert_false(captured[0].candidates.has(known_spell), "permanently-known spell excluded")
	assert_true(captured[0].candidates.has(new_spell), "genuinely new spell still offered")


func test_territory_known_spell_stays_offerable_as_upgrade() -> void:
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("Upgrade")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	# Killer knows the same spell but only via a TERRITORY node — not permanent —
	# so it should still be offered (a permanent upgrade over the temporary hold).
	_killer.spellbook = SpellBook.new()
	_grant_from(_killer.spellbook, spell, _nodes[3])

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_eq(captured.size(), 1)
	assert_true(captured[0].candidates.has(spell), "territory-known spell stays offerable")


# ── Acceptance #8: empty candidates after filter → no request ───────────────

func test_empty_candidates_after_filter_emits_no_request() -> void:
	_victim.spellbook = SpellBook.new()
	var spell := _mk_spell("OnlyOne")
	_grant_from(_victim.spellbook, spell, _victim.core_location)

	_killer.spellbook = SpellBook.new()
	_grant_from(_killer.spellbook, spell, _killer.core_location)  # killer already knows it

	var fired := false
	var handler := func(_req: SpellLootRequest) -> void: fired = true
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_false(fired, "nothing left after the known-filter → no request emitted")


func test_no_spellbook_emits_no_request() -> void:
	# Victim never had a spellbook at all — trivially empty candidates.
	var fired := false
	var handler := func(_req: SpellLootRequest) -> void: fired = true
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_false(fired, "no spellbook → no request emitted")


# ── Acceptance #9: innate lootable ───────────────────────────────────────────

func test_innate_spell_is_offered_as_a_candidate() -> void:
	_victim.spellbook = SpellBook.new()
	var innate := _mk_spell("Innate")
	_grant_innate(_victim.spellbook, innate)
	assert_true(_victim.spellbook.source_count(innate) >= 1, "innate is tracked as a (permanent) source")
	assert_true(innate in _victim.spellbook.spells, "innate is present in spells")

	var captured: Array[SpellLootRequest] = []
	var handler := func(req: SpellLootRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.spell_loot_requested.connect(handler)
	_kill_victim()
	Events.spell_loot_requested.disconnect(handler)

	assert_eq(captured.size(), 1)
	assert_true(captured[0].candidates.has(innate), "innate spell is offered")


# ── helpers ──────────────────────────────────────────────────────────────────

func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
