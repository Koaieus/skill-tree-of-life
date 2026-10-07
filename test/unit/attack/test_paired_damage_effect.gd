extends GutTest

## [PairedDamageEffect]: a damage rider worth a fraction of its arrow's RAW
## amount, fixed at compile, mitigated by each landed node's own armour, and
## carrying the arrow's crit rather than drawing its own. Wrapped in a
## [SplashEffect] it is the Explosive arrow's blast.

## Pinned on every leaf; the arrow's compiled amount is what the blast's
## share is OF, read off the arrow rather than assumed.
const RAW := 10.0
const SEED := 4242

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", RAW)
	# Each hostile node its own armour, so "mitigated once, by its own" shows.
	VolleyBoardFixture.set_stat(_f.target, &"armor", 1.0)
	VolleyBoardFixture.set_stat(_f.cluster[0], &"armor", 2.0)
	VolleyBoardFixture.set_stat(_f.cluster[1], &"armor", 3.0)
	# No damage floor, so the armour difference is what the numbers show.
	for n in [_f.target, _f.cluster[0], _f.cluster[1]]:
		VolleyBoardFixture.set_stat(n, &"min_damage_taken", 0.0)
	await get_tree().process_frame


func _blast(fraction: float, r: float) -> AmmoType:
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = r
	var inner := PairedDamageEffect.new()
	inner.fraction = fraction
	var splash := SplashEffect.new()
	splash.inner = inner
	splash.ownership_filter = SkillNode.Ownership.HOSTILE
	splash.range_finder = finder
	var ammo := AmmoType.new()
	ammo.id = &"test_blast"
	ammo.on_hit_effects = [splash]
	return ammo


## [arrow, its riders…] off leaf_0 onto the target.
func _volley(ammo: AmmoType) -> Array[HitInstance]:
	var hits: Array[HitInstance] = []
	var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], _f.target, ammo)
	hits.append(arrow)
	hits.append_array(RangedDamageFormula.riders_for(arrow))
	return hits


func _land(hits: Array[HitInstance]) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	outcome.crit_stream = CritRoll.stream_for(SEED)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	return outcome


## [param raw] through [param node]'s own armour, once — rounded up at entry
## like every hit ([method NodeCombat.take_damage]).
func _mitigated(node: SkillNode, raw: float) -> float:
	return Mitigation.compute(HitPoints.whole(raw), float(node.get_local_value(&"armor")),
			float(node.get_local_value(&"min_damage_taken")))


func _blast_hits(hits: Array[HitInstance]) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for i in range(1, hits.size()):
		out.append(hits[i])
	return out


func test_ammo_type_accepts_a_paired_damage_rider() -> void:
	var ammo := AmmoType.new()
	ammo.on_hit_effects = [PairedDamageEffect.new()]
	assert_eq(ammo.on_hit_effects.size(), 1, "mode-agnostic, not refused as spell-only")


func test_a_spell_landing_with_no_paired_hit_emits_nothing() -> void:
	var landing := HitLanding.new()
	landing.attacker = _f.attacker
	landing.target = _f.target
	PairedDamageEffect.new().apply(landing)
	assert_eq(landing.hits.size(), 0, "a spell uses DamageEffect")


## Each (fraction, radius) on a fresh board, so no pass kills what the next
## one measures.
const _SWEEP := [[0.25, 60.0], [0.25, 200.0], [0.25, 400.0], [0.5, 60.0],
		[0.5, 200.0], [0.5, 400.0], [1.5, 60.0], [1.5, 200.0], [1.5, 400.0]]


func test_the_blast_deals_its_fraction_of_raw_to_every_hostile_node_in_reach_each_mitigated_by_its_own_armour(
		p = use_parameters(_SWEEP)) -> void:
	VolleyBoardFixture.set_stat(_f.leaves[0], &"crit_chance", 0.0)
	var fraction: float = p[0]
	var r: float = p[1]
	var ammo := _blast(fraction, r)
	var reach: Array[SkillNode] = [_f.target]
	for n in (ammo.on_hit_effects[0] as SplashEffect).range_finder.gather(_f.target, _f.graph.navigator):
		if n != _f.target and n.ownership_bit(_f.attacker) & SkillNode.Ownership.HOSTILE != 0:
			reach.append(n)
	var hits := _volley(ammo)
	var raw := hits[0].amount
	_land(hits)
	var blasts := _blast_hits(hits)
	var landed: Array[SkillNode] = []
	for hit in blasts:
		landed.append(hit.target)
		assert_almost_eq(hit.effective_amount, _mitigated(hit.target, fraction * raw), 0.001,
				"f=%s r=%s on %s" % [fraction, r, hit.target.name])
	assert_eq(landed.size(), reach.size(), "f=%s r=%s: one blast per hostile node in reach" % [fraction, r])
	for n in reach:
		assert_has(landed, n, "f=%s r=%s" % [fraction, r])


func test_the_widest_blast_reaches_the_whole_hostile_cluster() -> void:
	assert_eq(_blast_hits(_volley(_blast(0.5, 400.0))).size(), 3)


func test_a_gated_arrow_duds_every_blast_hit() -> void:
	var hits := _volley(_blast(0.5, 400.0))
	# The firing leaf lost before land: the arrow's gate vetoes it.
	_f.alloc.force_deallocate(_f.leaves[0])
	await get_tree().process_frame
	_land(hits)
	assert_true(hits[0].gated, "the arrow is a dud")
	for hit in _blast_hits(hits):
		assert_true(hit.gated, "%s dud with its arrow" % hit.target.name)
		assert_eq(hit.effective_amount, 0.0)


func test_a_crit_arrows_blast_hits_are_crits_with_its_multiplier() -> void:
	VolleyBoardFixture.set_stat(_f.leaves[0], &"crit_chance", 1.0)
	VolleyBoardFixture.set_stat(_f.leaves[1], &"crit_chance", 0.0)
	var hits := _volley(_blast(0.5, 400.0))
	# The blast reads a no-crit leaf: a crit on it can only be the arrow's copy.
	for hit in _blast_hits(hits):
		hit.read_node = _f.leaves[1]
	var raw := hits[0].amount
	_land(hits)
	assert_true(hits[0].is_crit, "the arrow crit")
	for hit in _blast_hits(hits):
		assert_true(hit.is_crit, "%s inherits the crit" % hit.target.name)
		assert_eq(hit.crit_multiplier, hits[0].crit_multiplier)
		assert_eq(hit.crit_tier, hits[0].crit_tier)
		assert_almost_eq(hit.effective_amount,
				_mitigated(hit.target, 0.5 * raw * hits[0].crit_multiplier), 0.001)


func test_the_blast_draws_nothing_from_the_crit_stream() -> void:
	VolleyBoardFixture.set_stat(_f.leaves[0], &"crit_chance", 0.5)
	var plain := AmmoType.new()
	plain.id = &"test_plain"
	var bare := _land(_volley(plain))
	var blasted := _land(_volley(_blast(0.5, 400.0)))
	assert_eq(blasted.crit_stream.state, bare.crit_stream.state,
			"same draw count with and without the splash")


func test_the_blast_replays_on_a_peer_with_its_amounts_and_crits_under_its_arrow() -> void:
	VolleyBoardFixture.set_stat(_f.leaves[0], &"crit_chance", 1.0)
	var outcome := _land(_volley(_blast(0.5, 400.0)))
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _f.graph)))
	var rebuilt := AttackRecord.rebuild(wired, _f.graph)
	assert_eq(rebuilt.hits.size(), outcome.hits.size())
	for i in outcome.hits.size():
		var a := outcome.hits[i]
		var b := rebuilt.hits[i]
		assert_almost_eq(b.effective_amount, a.effective_amount, 0.001, "hit %d amount" % i)
		assert_eq(b.is_crit, a.is_crit, "hit %d crit" % i)
		assert_eq(b.crit_tier, a.crit_tier, "hit %d tier" % i)
		assert_eq(b.target, a.target, "hit %d target" % i)
	var riders := ArrowVolleyCoordinator.riders_of(rebuilt.hits, 0, false)
	assert_eq(riders.size(), outcome.hits.size() - 1, "every blast hit rides its arrow")
