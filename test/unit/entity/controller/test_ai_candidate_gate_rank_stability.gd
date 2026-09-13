extends GutTest

## #537 D5: "a two-tier gate that drops the true winner is worse than no
## gate at all." Coverage for the ranked-promotion contract itself —
## [method AiBladeRollout.top_k_indices] driven by
## [method AiCombatScorer.cheap_estimate] — plus the real
## [method AIController._gather_magic_candidates] integration, on a fixture
## deliberately built so a heuristic blind to target HP/kill would misrank.
##
## [b]Why magic, and why one caster / four targets[/b]: [method
## AiCombatScorer.cheap_estimate]'s [code]raw_damage[/code] input
## (spell_damage(source) x power) is CONSTANT across every target of the same
## (spell, source) pair — so a heuristic that ranked on raw power alone could
## not distinguish any of the four candidates below at all, and the fixture's
## whole point is that [method cheap_estimate] still can, via the HP-clamp +
## kill-bonus terms it shares with the real [method AiCombatScorer.score].
##
## [b]Discrimination, made concrete (not asserted on faith)[/b]:
## `test_a_heuristic_blind_to_kill_would_have_misranked` runs a deliberately
## naive "whichever was enumerated first" comparator through the SAME
## [method top_k_indices] at K=1 and asserts it picks a DECOY, not the true
## winner — proving this fixture is not vacuous before the next test asserts
## the real heuristic gets it right.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _SPARK_SPELL := preload("res://attack/spell/defs/spark.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _caster_entity: Entity
var _hostile: Entity
var _ai: AIController
var _source: SkillNode        ## the AI's casting leaf
var _decoys: Array[SkillNode] ## full-HP, never a kill on this raw_damage
var _true_winner: SkillNode   ## low-HP — the same raw_damage IS a kill here


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if faction != null:
		e.faction = faction
	return e


func _true_damage(target: SkillNode, amount: float) -> void:
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.amount = amount
	target.take_damage(amount, dmg)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	# AiCore - AiLeaf(source) - {Decoy0, Decoy1, Decoy2, TrueWinner}, star off
	# the source so every target is one hop from the one caster.
	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	core.name = "AiCore"
	_graph.add_skill_node(core)
	_source = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_source.name = "AiLeaf"
	_graph.add_skill_node(_source)
	_graph.add_edge(core, _source)

	_decoys = []
	for i in 3:
		var d := _SKILL_NODE_SCENE.instantiate() as SkillNode
		d.name = "Decoy%d" % i
		_graph.add_skill_node(d)
		_graph.add_edge(_source, d)
		_decoys.append(d)
	_true_winner = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_true_winner.name = "TrueWinner"
	_graph.add_skill_node(_true_winner)
	_graph.add_edge(_source, _true_winner)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_caster_entity = _make_entity("Caster")
	_graph.entities_container.add_child(_caster_entity)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_caster_entity.add_child(_ai)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.entities_container.add_child(_hostile)

	await get_tree().process_frame

	_alloc.force_allocate(_caster_entity, core)
	_caster_entity.core_location = core
	_alloc.force_allocate(_caster_entity, _source)
	for d in _decoys:
		_alloc.force_allocate(_hostile, d)
	_alloc.force_allocate(_hostile, _true_winner)
	_hostile.core_location = _decoys[0]

	_caster_entity.get_spellbook().learn(_SPARK_SPELL)

	# Every decoy sits at full HP (the shared raw_damage never kills one); the
	# true winner is chipped to a sliver so the SAME raw_damage kills it. TRUE
	# damage bypasses mitigation (.claude/rules/testing.md) so this is exact.
	_true_damage(_true_winner, _true_winner.get_current_hp() - 1.0)
	for d in _decoys:
		assert_gt(d.get_current_hp(), 1.0, "fixture guard: a decoy must not already be a near-kill")


func _raw_damage() -> float:
	return float(_source.get_local_value(&"spell_damage")) * _SPARK_SPELL.power


# ---------------------------------------------------------------------------
# The fixture is discriminating: a heuristic blind to HP/kill really does
# misrank it at K=1.
# ---------------------------------------------------------------------------

func test_a_heuristic_blind_to_kill_would_have_misranked() -> void:
	var candidates: Array[SkillNode] = _decoys.duplicate()
	candidates.append(_true_winner)
	var winner_index := candidates.size() - 1

	# The real heuristic: HP-clamped EV + kill bonus, exactly what
	# AiCombatScorer.score itself weighs (minus the ai_tier-scaled terms,
	# which are volume-cut concerns, not ranking ones — see cheap_estimate's
	# doc). Picks the true winner even at the strictest K.
	var raw := _raw_damage()
	var good := AiBladeRollout.top_k_indices(
			candidates,
			func(a: SkillNode, b: SkillNode) -> bool:
				return AiCombatScorer.cheap_estimate(a, raw) > AiCombatScorer.cheap_estimate(b, raw),
			1)
	assert_eq(good, [winner_index], "the real heuristic must promote the true winner at K=1")

	# The known-bad baseline: "whichever was enumerated first" — the naive
	# heuristic a two-tier gate would degrade to if it dropped HP/kill
	# entirely (raw_damage alone can't discriminate here at all, since it's
	# identical for every candidate from this one caster). Deliberately picks
	# a DECOY, proving the fixture is not vacuous.
	var bad := AiBladeRollout.top_k_indices(
			candidates,
			func(a: SkillNode, b: SkillNode) -> bool:
				return candidates.find(a) < candidates.find(b),
			1)
	assert_eq(bad, [0], "fixture guard: the naive baseline must pick a decoy, not the true winner")
	assert_ne(bad, good, "the two heuristics must actually disagree, or this proves nothing")


# ---------------------------------------------------------------------------
# The real gather: the true winner survives the production two-tier gate.
# ---------------------------------------------------------------------------

func test_the_true_winner_survives_the_real_two_tier_gate() -> void:
	var visible: Array[SkillNode] = _decoys.duplicate()
	visible.append(_true_winner)
	assert_gt(visible.size(), AIController._CANDIDATE_GATE_K,
			"fixture guard: candidate count must exceed K, or the gate never engages")

	var promoted := _ai._gather_magic_candidates(visible)
	assert_eq(promoted.size(), AIController._CANDIDATE_GATE_K,
			"exactly K candidates should be promoted out of %d" % visible.size())

	var found_winner := false
	for c in promoted:
		if c.target == _true_winner:
			found_winner = true
			assert_true(c.is_kill, "the promoted true-winner candidate must actually score as a kill")
	assert_true(found_winner,
			"the true winner (the only candidate this raw_damage can actually kill) " +
			"must survive the two-tier gate (#537 D5)")

	# And the real gate-accurate pick_best agrees it's the best of what got through.
	var best := AiCombatScorer.pick_best(promoted)
	assert_eq(best.target, _true_winner, "the promoted best must be the true winner")
