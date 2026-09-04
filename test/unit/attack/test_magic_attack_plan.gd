extends GutTest

## MagicAttackPlan: cost/reach/legality against a real Graph + Entity
## fixture. Chain Source - InRange - OutOfRange; a HopRangeFinder(max_hops=1)
## gates targeting reach, so InRange (1 hop) is a legal click target and
## OutOfRange (2 hops) is silently rejected.
##
## [b]Re-pointed for #728.[/b] There is no source-selection click any more: the
## reach of every eligible caster is unioned up front and one left-click on a
## target both commits it and stamps the auto-picked source. Every legality
## assertion below is unchanged — `validate()` still demands a source, still
## gates on min_degree — what changed is that the plan derives the source
## rather than being handed one, so the click tests assert that derivation.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SPELL_TEST_HELPER := preload("res://test/unit/spell/spell_test_helper.gd")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _source: SkillNode
var _in_range_target: SkillNode
var _out_of_range_target: SkillNode
var _spell: SpellDef


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_source = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_in_range_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_out_of_range_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_source)
	_graph.add_skill_node(_in_range_target)
	_graph.add_skill_node(_out_of_range_target)
	_graph.add_edge(_source, _in_range_target)
	_graph.add_edge(_in_range_target, _out_of_range_target)  # 2 hops from source

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)

	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _source)
	_alloc.force_allocate(_hostile, _in_range_target)
	_alloc.force_allocate(_hostile, _out_of_range_target)

	autofree(_attacker)
	autofree(_hostile)

	var targeting := NodeTargeting.new()
	targeting.ownership_filter = SkillNode.Ownership.HOSTILE
	var finder := HopRangeFinder.new()
	finder.max_hops = 1
	targeting.range_finder = finder

	var h: RefCounted = _SPELL_TEST_HELPER.new()
	_spell = SpellDef.new()
	_spell.name = "TestBolt"
	_spell.mana_cost = 5
	_spell.min_degree = 0
	_spell.power = 1.0
	_spell.targeting = targeting
	_spell.propagation = h.make_config(h.fan_all(), h.owner_enemy(), h.sum_reducer(), {max_hops = 0})
	_spell.on_hit_effects = [DamageEffect.new()] as Array[OnHitEffect]


func _plan() -> MagicAttackPlan:
	var p := MagicAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	p.spell = _spell
	return p


# ── Reach (click-driven, real HopRangeFinder over the mirrored graph) ──────

func test_one_click_on_an_in_range_hostile_sets_target_and_stamps_the_source() -> void:
	var p := _plan()
	p._on_node_left_clicked(_in_range_target)
	assert_eq(p.target, _in_range_target, "the clicked node IS the target — no source step first")
	assert_eq(p.source, _source, "and its caster is auto-picked from the union")


func test_click_out_of_range_hostile_is_rejected() -> void:
	var p := _plan()
	p._on_node_left_clicked(_out_of_range_target)
	assert_null(p.target)
	assert_null(p.source, "a rejected click stamps no source either")


## The old "a source click must land on an owned node" guard is gone with the
## source click. Its intent survives here: an owned node is not a TARGET of a
## Hostile-filtered spell, so clicking one commits nothing.
func test_clicking_an_owned_node_targets_nothing_for_a_hostile_spell() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	assert_null(p.target)
	assert_null(p.source)


## Right-click is gated on the target now, not the source — a null source is
## the resting state post-#728, so the old guard would have made pop() a
## permanent no-op.
func test_right_click_clears_both_after_a_pick_and_no_ops_before_one() -> void:
	var p := _plan()
	assert_false(p.pop(), "nothing committed yet, nothing to pop")
	p._on_node_left_clicked(_in_range_target)
	assert_true(p.pop())
	assert_null(p.target)
	assert_null(p.source)


# ── Legality ────────────────────────────────────────────────────────────

func test_validate_requires_source() -> void:
	var p := _plan()
	assert_has(p.validate(), &'No source selected')


func test_validate_requires_target() -> void:
	var p := _plan()
	p.source = _source
	assert_has(p.validate(), &'No target selected')


func test_validate_gates_on_min_degree() -> void:
	_spell.min_degree = 5
	var p := _plan()
	p.source = _source
	p.target = _in_range_target
	assert_has(p.validate(), &'Source node degree too low for spell')


func test_validate_passes_with_source_and_reachable_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_in_range_target)
	assert_eq(p.validate(), [] as Array[String])
	assert_true(p.is_valid())


# ── Cost + resolution ────────────────────────────────────────────────────

func test_resolve_transfers_mana_cost_and_hits_the_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_source)
	p._on_node_left_clicked(_in_range_target)
	var outcome := p.resolve()
	assert_eq(outcome.mana_cost, 5)
	assert_eq(outcome.hits.size(), 1)
	assert_eq(outcome.hits[0].target, _in_range_target)


func test_resolve_on_invalid_plan_returns_default_outcome() -> void:
	var p := _plan()
	var outcome := p.resolve()
	assert_eq(outcome.mana_cost, 0)
	assert_true(outcome.hits.is_empty())


# ── Caster highlighting: the sources the reach is measured FROM ────────────
#
# #728 published the union's reach and its targets but never its casters, so a
# spell whose `min_degree` strands the frontier leaf looked identical to one
# that does not — same authored hops, quietly one hop less of them. These
# assert the role, not the pixels; the overlay maps it to a colour.

func test_an_eligible_caster_paints_as_caster_before_anything_is_committed() -> void:
	var p := _plan()
	assert_eq(p.get_node_role(_source), HighlightProvider.HighlightRole.CASTER,
			"the owned node the spell would launch from")
	assert_eq(p.get_node_role(_in_range_target), HighlightProvider.HighlightRole.IN_RANGE,
			"targets keep their own role — the two sets are shown together")
	assert_eq(p.get_node_role(_out_of_range_target), HighlightProvider.HighlightRole.NONE)


func test_committing_a_target_collapses_the_casters_to_the_one_picked() -> void:
	var p := _plan()
	p._on_node_left_clicked(_in_range_target)
	assert_eq(p.get_node_role(_source), HighlightProvider.HighlightRole.ORIGIN,
			"the stamped source is the cast about to happen, not a candidate")
	assert_eq(p.get_node_role(_in_range_target), HighlightProvider.HighlightRole.HOSTILE_TARGET)


func test_a_node_below_min_degree_is_not_painted_as_a_caster() -> void:
	# The Lightning-Bolt case: `_source` is a degree-1 leaf of its own (single-
	# node) territory, so raising the bar strands the only caster there is.
	_spell.min_degree = 2
	var p := _plan()
	assert_eq(p.get_node_role(_source), HighlightProvider.HighlightRole.NONE,
			"nothing to cast from, and the highlight says so")


func test_a_node_that_is_both_caster_and_legal_target_paints_as_the_target() -> void:
	# `healing_beam.tres` is `Any` on purpose ([NodeTargeting]), so an owned
	# node really can be both. One node gets one ring, and the target role has
	# to win or a self-heal loses its click affordance.
	(_spell.targeting as NodeTargeting).ownership_filter = SkillNode.Ownership.MINE | SkillNode.Ownership.HOSTILE
	var p := _plan()
	assert_true(p.union().is_source(_source), "precondition: it is still a caster")
	assert_eq(p.get_node_role(_source), HighlightProvider.HighlightRole.IN_RANGE,
			"targetable wins over castable-from")
