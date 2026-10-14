extends GutTest

## A heal SPELL (the healing beam's shape: one [HealEffect]) landing on a
## charged node with a DETONATE explosive load blasts a share of its heal —
## never damage — onto the nodes in reach its own mask admits. A spell
## landing rides its own heal the way an arrow's landing rides its arrow, so
## the shrapnel pairs a [PairedHealInstance]. Geometry is derived from the
## shipped explosive knobs, never literals.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _EXPLOSIVE: StatusDef = preload("res://effects/status/explosive.tres")
const _ANY := 15
const _FRIENDLY := SkillNode.Ownership.MINE | SkillNode.Ownership.ALLY
const _LOAD := 3
const _CHARGES := 2
const FAR := Vector2(-100000, 0)

var h: SpellTestHelper


func before_each() -> void:
	h = H.new()


func _spread() -> ExplosiveSpread:
	return _EXPLOSIVE.spread as ExplosiveSpread


func _heal_spell(mask: int) -> SpellDef:
	var spell := h.make_spell(h.make_config(h.no_spread(), null, null), [HealEffect.new()] as Array[OnHitEffect])
	var targeting := NodeTargeting.new()
	targeting.ownership_filter = mask
	spell.targeting = targeting
	return spell


## Node 0 = the caster's far home, 1 = the charged friendly landing, 2 = a
## friendly in reach, 3 = a hostile in reach, both adjacent to 1.
func _board() -> Dictionary:
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self,
			{0: FAR, 1: Vector2.ZERO, 2: Vector2(100, 0), 3: Vector2(-100, 0)})
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(atk)
	h.give_big_hp(def)
	h.assign_owner(graph, atk, [0, 1, 2])
	h.assign_owner(graph, def, [3])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var power := DetonateEffect.power_of(_LOAD, _CHARGES, _spread().resonance)
	var reach := _spread().radius_for(n[1].radius, power)
	assert_between(reach, 101.0, 90000.0, "fixture: the blast reaches nodes 2 and 3, never 0")
	n[1].get_combat().apply_status(_EXPLOSIVE, float(_CHARGES))
	graph.navigator.reconcile()
	return {graph = graph, atk = atk, n = n}


func _cast(b: Dictionary, spell: SpellDef) -> AttackOutcome:
	var n: Array = b.n
	var inf := Infusion.for_cast(spell, {&"explosive": _LOAD})
	assert_eq(inf.detonate_load(spell), _LOAD, "fixture: the explosive load detonates")
	return SpellResolver.resolve(spell, n[1], n[0], b.atk, b.graph, null, inf)


## [primary heal on node 1, the blast heals].
func _heals(outcome: AttackOutcome, centre: SkillNode) -> Array:
	var primary: HealInstance = null
	var blasts: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit is PairedHealInstance:
			blasts.append(hit)
		elif hit is HealInstance and hit.target == centre:
			primary = hit
	assert_not_null(primary, "the spell heals the node it lands on")
	return [primary, blasts]


func test_a_heal_spell_under_an_ally_mask_blasts_a_heal_onto_friendlies_only() -> void:
	var b := _board()
	var n: Array = b.n
	var got := _heals(_cast(b, _heal_spell(_FRIENDLY)), n[1])
	var primary: HealInstance = got[0]
	var blasts: Array[HitInstance] = got[1]
	assert_eq(blasts.map(func(x): return x.target), [n[2]], "one blast heal, on the friendly in reach")
	for hit in blasts:
		assert_almost_eq(hit.amount, PairedDamageEffect.new().fraction * primary.amount, 0.0001,
				"the blast heals the fraction of the spell's raw heal")
		assert_eq(hit.paired, primary, "the blast rides the spell's heal")


func test_a_heal_spell_under_an_any_mask_blasts_heals_and_deals_no_damage() -> void:
	var b := _board()
	var outcome := _cast(b, _heal_spell(_ANY))
	var blasts: Array = _heals(outcome, b.n[1])[1]
	assert_false(blasts.is_empty(), "the healing beam's own mask mints blast heals")
	for hit in outcome.hits:
		assert_false(hit is DamageInstance, "a heal's blast never damages: %s" % hit)
