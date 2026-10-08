extends GutTest

## [ScaleStacksEffect] + [ContentRanker] — Defile's twist: a node lands one
## corruption stack per rolled modifier, a spell grant and an addon count
## double, a blank node is immune. The scale is a per-LANDING fact multiplied
## onto the FOLDED stacks, so it neither compounds down a fan nor survives a 0.

const _CORRUPTION := preload("res://effects/status/corruption.tres")
const _TOXIN_ADDON := preload("res://skill_node/addons/defs/toxin_addon.tscn")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _rolled(node: SkillNode, count: int) -> void:
	var mods: Array[StatModifier] = []
	for i in count:
		var m := StatModifier.new()
		m.stat_id = &"armor"
		m.value = 1.0
		mods.append(m)
	node.modifiers = mods


func _grant(node: SkillNode) -> void:
	var g := SpellGrant.new()
	g.spell_def = SpellCatalog.SPARK
	var effects: Array[Effect] = [g]
	node.effects = effects


func _status_on(outcome: AttackOutcome, node: SkillNode) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for hit in outcome.hits:
		if hit.target == node and hit is StatusInstance:
			out.append(hit)
	return out


func test_content_counts_rolled_modifiers_grants_and_addons_by_weight() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	_rolled(n[0], 3)
	_grant(n[0])
	var addon: SkillNodeAddon = _TOXIN_ADDON.instantiate()
	assert_false(addon.get_entity_modifiers().is_empty(),
			"fixture: the addon carries its own modifiers, so a double count would show")
	n[0].add_child(addon)
	await get_tree().process_frame
	var r := ContentRanker.new()
	r.modifier_weight = 1.5
	r.grant_weight = 2.5
	r.addon_weight = 4.0
	assert_almost_eq(r.score(n[0], null), 3.0 * r.modifier_weight + 1.0 * r.grant_weight + 1.0 * r.addon_weight,
			0.0001, "3 rolled · w_mod + 1 grant · w_grant + 1 addon · w_addon; the addon's own modifiers are not counted")
	assert_eq(r.score(n[1], null), 0.0, "a blank node scores 0")


func test_a_zero_scale_lands_no_stacks_however_many_per_hit() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1])
	var n := graph.get_skill_nodes()
	for i in 2:
		var s := StatusInstance.new()
		s.def = _CORRUPTION
		s.power = 3.0
		s.target = n[i]
		s.stack_scale = 0.0 if i == 0 else 2.0
		OutcomeApplier.land_one(s, CombatWorld.live())
	assert_eq(n[0].get_combat().get_status_power(&"corruption"), 0.0, "a scale of 0 lands 0")
	assert_almost_eq(n[1].get_combat().get_status_power(&"corruption"), 6.0, 0.0001,
			"the scale multiplies the folded stacks")


func test_the_effect_writes_the_landing_scale_from_its_ranker_or_factor() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	_rolled(n[0], 2)
	var p := CastSpell.new()
	p.current_node = n[0]
	p.graph = graph
	var lctx := LandingContext.for_test(p, n[0])
	var eff := ScaleStacksEffect.new()
	eff.ranker = ContentRanker.new()
	eff.apply(lctx)
	assert_almost_eq(lctx.stack_scale, 2.0 * eff.ranker.modifier_weight, 0.0001, "the ranker's score")
	assert_eq(p.damage, CastSpell.new().damage, "the payload is untouched: nothing inherits")
	var flat := ScaleStacksEffect.new()
	flat.factor = 3.0
	var lctx2 := LandingContext.for_test(p, n[0])
	flat.apply(lctx2)
	assert_almost_eq(lctx2.stack_scale, 3.0, 0.0001, "no ranker: the factor")


## 0 (attacker) — 1 (target, content 1) — 2 (content 4) — 3 (blank).
func _defile_cast() -> Array:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [1, 2, 3])
	h.give_big_hp(defender)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	h.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	_rolled(n[1], 1)
	_rolled(n[2], 4)
	var spell: SpellDef = load("res://attack/spell/defs/defile.tres")
	assert_not_null(spell, "defile.tres is authored")
	return [graph, n, SpellResolver.resolve(spell, n[1], n[0], atk, graph) if spell != null else null]


func test_defile_scales_each_landing_by_its_own_content_not_its_parents() -> void:
	var r := _defile_cast()
	var n: Array = r[1]
	var outcome: AttackOutcome = r[2]
	assert_not_null(outcome)
	if outcome == null:
		return
	var near := _status_on(outcome, n[1])
	var rich := _status_on(outcome, n[2])
	assert_eq(near.size(), 1, "the target takes one corruption rider")
	assert_eq(rich.size(), 1, "the 2nd-hop node takes one corruption rider")
	if near.size() != 1 or rich.size() != 1:
		return
	assert_eq(near[0].def, _CORRUPTION)
	assert_gt(near[0].power, 0.0, "content 1 lands its folded stacks")
	assert_almost_eq(rich[0].power, near[0].power * 4.0, 0.0001,
			"content 4 lands 4× folded — not 4 × its parent's 1×")
	for s in _status_on(outcome, n[3]):
		assert_eq(s.power, 0.0, "a blank node is immune")


func test_a_defile_record_replays_to_the_same_stacks_on_a_fresh_world() -> void:
	var r := _defile_cast()
	var graph: Graph = r[0]
	var n: Array = r[1]
	var outcome: AttackOutcome = r[2]
	assert_not_null(outcome)
	if outcome == null:
		return
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, graph), graph)
	for hit in rebuilt.hits:
		OutcomeApplier.land_one(hit, CombatWorld.live())
	var rich := _status_on(outcome, n[2])
	assert_eq(rich.size(), 1)
	if rich.size() != 1:
		return
	assert_gt(n[2].get_combat().get_status_power(&"corruption"), 0.0, "the rich node is corrupted")
	assert_almost_eq(n[2].get_combat().get_status_power(&"corruption"), rich[0].power, 0.0001,
			"the live replay lands what the resolve landed")
	assert_eq(n[3].get_combat().get_status_power(&"corruption"), 0.0, "the blank node never is")
