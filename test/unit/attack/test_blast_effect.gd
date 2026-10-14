extends GutTest

## [BlastEffect]: a [SplashEffect] preset that never lands on its centre and
## inherits its landing's target mask — so an arrow's blast hits only what an
## arrow may hit, a spell's only what its targeting may. Its reach is its
## finder's. Wrapped [PairedDamageEffect] shrapnel reads the landing's stored
## raw amount, so it works on a spell landing (no paired hit) too.

const RAW := 10.0
const FRACTION := 0.5
## Reaches hostile_a (150 px off the target) and both near friendly leaves,
## never hostile_b nor the far hostile node.
const REACH := 200.0

var _f: VolleyBoardFixture
var _far: SkillNode


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", RAW)
	_far = _f.add_node(&"far_hostile", Vector2(1100, 0), _f.hostile)
	await get_tree().process_frame


func _euclid(r: float) -> EuclideanRangeFinder:
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = r
	return finder


func _blast(finder: RangeFinder) -> BlastEffect:
	var shrapnel := PairedDamageEffect.new()
	shrapnel.fraction = FRACTION
	var blast := BlastEffect.new()
	blast.inners = [shrapnel] as Array[OnHitEffect]
	blast.range_finder = finder
	return blast


## The arrow off leaf_0 onto the target, then its riders.
func _arrow_hits(blast: BlastEffect) -> Array[HitInstance]:
	var ammo := AmmoType.new()
	ammo.id = &"test_blast"
	ammo.on_hit_effects = [blast]
	var hits: Array[HitInstance] = []
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], _f.target, ammo)
	hits.append(arrow)
	hits.append_array(RangedDamageFormula.riders_for(arrow))
	return hits


func _spell_landing(mask: int) -> LandingContext:
	var cast := PropagationContext.new()
	cast.caster = _f.attacker
	cast.graph = _f.graph
	cast.outcome = AttackOutcome.new()
	cast.target_mask = mask
	var payload := CastSpell.new()
	payload.current_node = _f.target
	payload.source = _f.leaves[0]
	payload.damage = RAW
	return LandingContext.for_test(payload, _f.target, cast)


func _targets(hits: Array) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for h in hits:
		out.append(h.target)
	return out


func test_a_blast_preset_skips_the_centre_and_inherits_the_mask() -> void:
	var blast := BlastEffect.new()
	assert_false(blast.hits_centre, "the centre already took the main hit")
	assert_eq(blast.ownership_filter, 0, "0 = inherit the landing's mask")


func test_an_arrow_blast_hits_hostiles_in_reach_only_for_its_fraction_of_raw() -> void:
	var hits := _arrow_hits(_blast(_euclid(REACH)))
	var arrow := hits[0] as DamageInstance
	var shrapnel := hits.slice(1)
	var targets := _targets(shrapnel)
	assert_eq(targets, [_f.cluster[0]] as Array[SkillNode],
			"the hostile in reach; never the centre, a friendly leaf, or past the reach")
	for h in shrapnel:
		assert_almost_eq((h as DamageInstance).amount, FRACTION * arrow.amount, 0.0001,
				"each extra hit is the fraction of the arrow's raw")
		assert_eq(h.paired, arrow, "carries the arrow as paired, so a dud arrow duds it")
		assert_eq(h.land_mask, SkillNode.Ownership.HOSTILE, "rechecks the arrow's mask at land")


func test_a_spell_blast_emits_shrapnel_on_a_hostile_mask() -> void:
	var lctx := _spell_landing(SkillNode.Ownership.HOSTILE)
	_blast(_euclid(REACH)).apply(lctx)
	assert_eq(_targets(lctx.hits), [_f.cluster[0]] as Array[SkillNode],
			"a spell landing carries its targeting's mask; no paired hit needed")
	for h in lctx.hits:
		assert_almost_eq((h as DamageInstance).amount, FRACTION * RAW, 0.0001)
		assert_null(h.paired, "a spell gates nothing")


func test_a_spell_blast_reaches_friendlies_iff_its_mask_includes_them() -> void:
	var hostile_only := _targets(_spell_landing(SkillNode.Ownership.HOSTILE).hits)
	var lctx := _spell_landing(15)
	_blast(_euclid(REACH)).apply(lctx)
	var any := _targets(lctx.hits)
	assert_false(hostile_only.has(_f.leaves[0]))
	assert_true(any.has(_f.leaves[0]), "an Any spell's blast reaches its own node")
	assert_true(any.has(_f.cluster[0]))
	assert_false(any.has(_f.target), "never the centre")
	assert_false(any.has(_far), "never past the reach")


func test_distinct_reaches_gather_separately_and_a_shared_finder_once() -> void:
	var landing := _spell_landing(SkillNode.Ownership.HOSTILE)
	var near := _euclid(100.0)
	_blast(near).apply(landing)
	_blast(_euclid(REACH)).apply(landing)
	assert_eq(landing.gather_cache.size(), 2, "two reaches, two sweeps")
	_blast(near).apply(landing)
	assert_eq(landing.gather_cache.size(), 2, "the same finder shares its entry")
