extends GutTest

## The Ice shape row (#1813): a [ConcentrateUse] spends the shape load as a hop
## cut priced per hop on the [LoadBag]; the concentrate row is told apart from
## a Cold ride row on the same element by its use, so a refusing shape row
## never refuses the ride, and its innate is never planted as Cold.

const _COLD: StatusDef = preload("res://effects/status/cold.tres")


func _ice_identity() -> Identity:
	return ElementRoster.shared().by_id(&"ice").identity


## A test spell walking [param hops] hops, ingest 1:1, with [param rows].
func _spell(hops: float, rows: Array[AspectIntake]) -> SpellDef:
	var spell := SpellDef.new()
	var prop := PropagationConfig.new()
	prop.max_hops = hops
	spell.propagation = prop
	spell.intakes = rows
	return spell


func _concentrate_row(gain: int, cost: int, innate := 0, bonus := -1.0) -> AspectIntake:
	var row := AspectIntake.new()
	row.identity = _ice_identity()
	row.affinity_gain = gain
	row.affinity_cost = cost
	row.innate = innate
	var use := ConcentrateUse.new()
	if bonus >= 0.0:
		use.bonus_per_hop = bonus
	row.use = use
	return row


func _cold_ride_row(gain: int) -> AspectIntake:
	var row := AspectIntake.new()
	row.identity = _ice_identity()
	row.plants = _COLD
	row.affinity_gain = gain
	return row


func _shaped(spell: SpellDef, points: int, ride := 0) -> Infusion:
	var inf := Infusion.innate(spell)
	inf.set_shape(&"ice", points)
	inf.set_ride(&"ice", ride)
	return inf


func _cold_riders(bag: LoadBag) -> Array:
	return bag.riders.filter(func(r: OnHitEffect) -> bool:
		return r is ApplyStatusEffect and (r as ApplyStatusEffect).def == _COLD)


# --- the use and the bag ---------------------------------------------------

func test_spend_writes_the_hop_cut_and_bonus_and_adds_no_rider() -> void:
	var use := ConcentrateUse.new()
	use.bonus_per_hop = 0.75
	var bag := LoadBag.new()
	use.spend(null, null, 3, bag)
	assert_eq(bag.hop_cut, 3, "1 load per hop")
	assert_eq(bag.bonus_per_hop, 0.75)
	assert_eq(bag.riders.size(), 0, "a concentrate plants nothing")


func test_the_bag_prices_the_cut_against_the_walk() -> void:
	var bag := LoadBag.new()
	ConcentrateUse.shared_default().spend(null, null, 3, bag)
	var b := ConcentrateUse.shared_default().bonus_per_hop
	assert_eq(bag.hops_removed(6.0), 3)
	assert_almost_eq(bag.multiplier(6.0), 1.0 + b * 3, 1e-6, "×2.5 at the default")
	ConcentrateUse.shared_default().spend(null, null, 9, bag)
	assert_eq(bag.hops_removed(6.0), 6, "surplus Ice beyond the hops is wasted")
	assert_almost_eq(bag.multiplier(6.0), 1.0 + b * 6, 1e-6)
	assert_eq(bag.hops_removed(0.0), 0, "nothing to cut on a 0-hop walk")
	assert_eq(bag.hops_removed(INF), 0, "nothing to cut on an unbounded walk")
	assert_eq(bag.multiplier(INF), 1.0)
	assert_eq(LoadBag.new().multiplier(6.0), 1.0, "no concentrate: exactly 1")


# --- acceptance 2: the rate ------------------------------------------------

func test_a_dearer_row_cuts_one_hop_per_two_points() -> void:
	var spell := _spell(6.0, [_concentrate_row(1, 2)] as Array[AspectIntake])
	assert_eq(_shaped(spell, 2).bag(spell).hop_cut, 1, "2 points at 1:2 cut 1 hop")
	assert_eq(_shaped(spell, 1).bag(spell).hop_cut, 0, "1 point at 1:2 cuts none")


func test_a_row_of_gain_zero_refuses_and_the_cast_is_unchanged() -> void:
	var spell := _spell(6.0, [_concentrate_row(0, 1)] as Array[AspectIntake])
	assert_lte(Infusion.rate_of(spell, &"ice", Infusion.RowKind.CONCENTRATE), 0.0)
	var bag := _shaped(spell, 3).bag(spell)
	assert_eq(bag.hop_cut, 0)
	assert_eq(bag.multiplier(6.0), 1.0)


func test_an_authored_bonus_prices_the_cut() -> void:
	var spell := _spell(6.0, [_concentrate_row(1, 1, 0, 1.0)] as Array[AspectIntake])
	assert_almost_eq(_shaped(spell, 3).bag(spell).multiplier(6.0), 4.0, 1e-6, "×4 at 3 with bonus 1.0")


func test_no_row_concentrates_at_the_shared_default() -> void:
	var spell := _spell(6.0, [] as Array[AspectIntake])
	assert_true(Infusion.use_of(spell, &"ice", Infusion.RowKind.CONCENTRATE) is ConcentrateUse)
	var bag := _shaped(spell, 3).bag(spell)
	assert_eq(bag.hop_cut, 3, "1:1 unlisted")
	assert_eq(bag.bonus_per_hop, ConcentrateUse.shared_default().bonus_per_hop)


func test_a_fire_shape_suppresses_the_authored_ice_shape() -> void:
	var spell := _spell(6.0, [_concentrate_row(1, 1, 2)] as Array[AspectIntake])
	assert_eq(Infusion.innate(spell).shape_of(spell), &"ice", "innate > 0: Ice is the shape default")
	assert_eq(Infusion.innate(spell).bag(spell).hop_cut, 2, "the innate cut")
	var inf := Infusion.innate(spell)
	inf.set_shape(&"fire", 2)
	assert_eq(inf.shape_of(spell), &"fire")
	assert_eq(inf.bag(spell).hop_cut, 0, "a forged Fire shape replaces the Ice row")


# --- acceptance 2b: two kinds of Ice row -----------------------------------

func _assert_split(rows: Array[AspectIntake], ride_row: AspectIntake) -> void:
	var spell := _spell(6.0, rows)
	assert_eq(Infusion.rate_of(spell, &"ice"), 1.0, "the ride reads the Cold ride row")
	assert_lte(Infusion.rate_of(spell, &"ice", Infusion.RowKind.CONCENTRATE), 0.0,
			"the shape reads the refusing concentrate row")
	assert_eq(Infusion.intake_of(spell, &"ice"), ride_row)
	var inf := Infusion.innate(spell)
	assert_eq(inf.load_of(spell).get(&"ice", 0), 0, "the concentrate's innate is no Cold load")
	assert_eq(_cold_riders(inf.bag(spell)).size(), 0, "no Cold rider")


func test_two_ice_rows_split_by_use_concentrate_last() -> void:
	var ride := _cold_ride_row(1)
	_assert_split([ride, _concentrate_row(0, 1, 2)] as Array[AspectIntake], ride)


func test_two_ice_rows_split_by_use_concentrate_first() -> void:
	var ride := _cold_ride_row(1)
	_assert_split([_concentrate_row(0, 1, 2), ride] as Array[AspectIntake], ride)


func test_a_refusing_ride_row_beside_a_dear_concentrate_row() -> void:
	var spell := _spell(6.0, [_cold_ride_row(0), _concentrate_row(1, 2)] as Array[AspectIntake])
	assert_lte(Infusion.rate_of(spell, &"ice"), 0.0, "the ride refuses")
	assert_eq(Infusion.rate_of(spell, &"ice", Infusion.RowKind.CONCENTRATE), 0.5)


func test_no_ice_row_reads_one_on_both_kinds() -> void:
	var spell := _spell(6.0, [] as Array[AspectIntake])
	assert_eq(Infusion.rate_of(spell, &"ice"), 1.0)
	assert_eq(Infusion.rate_of(spell, &"ice", Infusion.RowKind.CONCENTRATE), 1.0)


func test_a_concentrate_row_is_no_ride_row() -> void:
	var spell := _spell(6.0, [_concentrate_row(0, 1)] as Array[AspectIntake])
	assert_false(Infusion.is_ride_row(spell.intakes[0]))
	assert_true(Infusion.is_concentrate_row(spell.intakes[0]))
	assert_eq(Infusion.innate_ride_of(spell), &"", "a shape row is no innate Cold ride")


# --- acceptance 6b: a refused shape still rides ----------------------------

func test_a_spell_refusing_the_shape_still_takes_a_cold_ride() -> void:
	var spell := _spell(0.0, [_concentrate_row(0, 1)] as Array[AspectIntake])
	var ridden := _shaped(spell, 0, 2)
	var cold := _cold_riders(ridden.bag(spell))
	assert_eq(cold.size(), 1, "one Cold rider")
	assert_eq((cold[0] as ApplyStatusEffect).power, 2.0, "at 1:1 unlisted")
	var both := _shaped(spell, 2, 2)
	var bag := both.bag(spell)
	assert_eq(bag.hop_cut, 0, "the shape is refused")
	assert_eq(bag.multiplier(spell.propagation.max_hops), 1.0, "the walk and seed are the plain cast's")
	cold = _cold_riders(bag)
	assert_eq(cold.size(), 1)
	assert_eq((cold[0] as ApplyStatusEffect).power, 2.0, "the Cold rider is still 2")


# --- the resolver: acceptance 1, 3, 4 --------------------------------------
# A chain n0 (the caster's) — n1 … n8 (the target's); the cast seeds n1 and a
# 6-hop walk lands n1 … n7, one landing per node (an Ice shape is no channel).

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _POISON: StatusDef = preload("res://effects/status/poison.tres")
const _POISON_ID: Identity = preload("res://identity/defs/poison.tres")


func _chain() -> Dictionary:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [0])
	helper.assign_owner(graph, def, [1, 2, 3, 4, 5, 6, 7, 8])
	var n: Array[SkillNode] = []
	n.assign(graph.get_skill_nodes())
	return {graph = graph, atk = atk, n = n}


## A plain-damage 6-hop walk (no hop progression: the multiplier is on the cast,
## so every landing is exactly ×m) with [param rows].
func _walk_spell(rows: Array[AspectIntake] = []) -> SpellDef:
	var helper := H.new()
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 6})
	var spell := helper.make_spell(config, [DamageEffect.new()] as Array[OnHitEffect], 10.0)
	spell.intakes = rows
	return spell


func _cast(b: Dictionary, spell: SpellDef, inf: Infusion) -> AttackOutcome:
	return SpellResolver.resolve(spell, b.n[1], b.n[0], b.atk, b.graph, null, inf)


func _dmg_on(out: AttackOutcome, node: SkillNode) -> float:
	var sum := 0.0
	for h in out.hits:
		if h is DamageInstance and h.target == node:
			sum += h.amount
	return sum


func _statuses_on(out: AttackOutcome, node: SkillNode, def: StatusDef) -> Array:
	return out.hits.filter(func(h: HitInstance) -> bool:
		return h is StatusInstance and h.target == node and (h as StatusInstance).def == def)


func _walk(out: AttackOutcome) -> Array:
	return out.timeline.map(func(ev: PropagationEvent) -> Array: return [ev.beat, ev.target])


func _assert_concentrated(b: Dictionary, spell: SpellDef, points: int, hops_left: int, m: float) -> void:
	var plain := _cast(b, spell, Infusion.innate(spell))
	var out := _cast(b, spell, _shaped(spell, points))
	for i in range(1, 8):
		var node: SkillNode = b.n[i]
		var hop := i - 1
		assert_gt(_dmg_on(plain, node), 0.0, "fixture: the plain walk lands hop %d" % hop)
		if hop <= hops_left:
			assert_almost_eq(_dmg_on(out, node), _dmg_on(plain, node) * m, 1e-4,
					"%d points: hop %d lands ×%.2f" % [points, hop, m])
		else:
			assert_eq(_dmg_on(out, node), 0.0, "%d points: nothing past hop %d" % [points, hops_left])
	assert_eq(_walk(out).size(), hops_left + 1, "%d points: walks %d hops" % [points, hops_left])


func test_1_a_cut_walks_shorter_and_every_landing_left_pays_up() -> void:
	var b := _chain()
	var spell := _walk_spell()
	var bonus := ConcentrateUse.shared_default().bonus_per_hop
	_assert_concentrated(b, spell, 3, 3, 1.0 + bonus * 3)
	_assert_concentrated(b, spell, 6, 0, 1.0 + bonus * 6)
	_assert_concentrated(b, spell, 9, 0, 1.0 + bonus * 6)
	assert_eq(spell.propagation.max_hops, 6.0, "the def's max_hops is never written")


func test_1_an_authored_bonus_of_one_lands_x4_at_three() -> void:
	var b := _chain()
	var spell := _walk_spell([_concentrate_row(1, 1, 0, 1.0)] as Array[AspectIntake])
	_assert_concentrated(b, spell, 3, 3, 4.0)


func _poison_row() -> AspectIntake:
	var row := AspectIntake.new()
	row.identity = _POISON_ID
	row.plants = _POISON
	return row


func test_3_aspect_riders_scale_ceil_and_terrain_riders_land_at_cast_value() -> void:
	var b := _chain()
	var spell := _walk_spell([_poison_row()] as Array[AspectIntake])
	var bonus := ConcentrateUse.shared_default().bonus_per_hop
	var m := 1.0 + bonus * 3
	var inf := _shaped(spell, 3, 2)
	inf.points[&"poison"] = 3
	var out := _cast(b, spell, inf)
	var seed: SkillNode = b.n[1]
	var poison := _statuses_on(out, seed, _POISON)
	assert_eq(poison.size(), 1, "one landing on an unprimed seed")
	if poison.size() == 1:
		assert_eq(poison[0].power, ceilf(3.0 * m), "Poison 3 at ×2.5 lands 8 (ceil)")
	var cold := _statuses_on(out, seed, _COLD)
	assert_eq(cold.size(), 1, "the Cold ride lands once; the concentrate plants none")
	if cold.size() == 1:
		assert_eq(cold[0].power, 2.0, "the Cold ride lands at its cast value")
	var shape_only := _cast(b, spell, _shaped(spell, 3))
	assert_eq(_statuses_on(shape_only, seed, _COLD).size(), 0, "the concentrate itself plants no Cold")


func test_4_no_shape_or_a_fire_or_lightning_shape_leaves_hops_and_seed_plain() -> void:
	var b := _chain()
	var spell := _walk_spell()
	var plain := _cast(b, spell, Infusion.innate(spell))
	var seed: SkillNode = b.n[1]
	for shape: StringName in [&"", &"fire", &"lightning"]:
		var inf := Infusion.innate(spell)
		if shape != &"":
			inf.set_shape(shape, 3)
		var out := _cast(b, spell, inf)
		assert_eq(_walk(out), _walk(plain), "%s: same walk" % shape)
		var head := _seed_head(out, seed)
		assert_not_null(head, "%s: a seed head" % shape)
		if head != null:
			assert_eq(head.amount, _seed_head(plain, seed).amount, "%s: the seed is the plain one" % shape)
			assert_eq(head.hops_removed, 0, "%s: no cut on the head" % shape)


func _seed_head(out: AttackOutcome, seed: SkillNode) -> HitInstance:
	for ev: PropagationEvent in out.timeline:
		if ev.beat != 0:
			continue
		for h: HitInstance in ev.hits:
			if h.is_head and h.target == seed:
				return h
	return null


# --- the carry: the seed head's cut reaches Admits' second read -------------

## Records every arrival a node's second read is handed; breaks nothing.
class _Spy extends Admits:
	var seen: Array = []  # [node, is_copy, hops_removed]

	func read_in(_world: CombatWorld, node: SkillNode, _after: TerrainRead,
			arrivals: Array[Arrival]) -> AdmitsAnswer:
		for a in arrivals:
			seen.append([node, a.is_copy, a.hops_removed])
		return null


var _was_admits: Array = []


func after_each() -> void:
	var ice := ElementRoster.shared().by_id(&"ice")
	for i in _was_admits.size():
		ice.bands[i].admits = _was_admits[i]
	_was_admits = []
	CombatWorld.reset_live()


func _spy() -> _Spy:
	var spy := _Spy.new()
	var ice := ElementRoster.shared().by_id(&"ice")
	for band in ice.bands:
		_was_admits.append(band.admits)
		if band.admits != null:
			band.admits = spy
	return spy


func _seen_at(spy: _Spy, node: SkillNode) -> Array:
	return spy.seen.filter(func(r: Array) -> bool: return r[0] == node)


func test_the_seed_heads_cut_reaches_the_second_read_and_no_copy_or_later_head_carries_it() -> void:
	CombatWorld.reset_live()
	var w := TestWorld.create(self)
	var red := w.add_entity("Red")
	var blue := w.add_entity("Blue")
	await get_tree().process_frame
	H.new().give_big_hp(blue)
	var fire := ElementRoster.shared().by_id(&"fire")
	var radius := 0.0
	# src — a (Frozen) — b (Frozen) — c ; src — s (Burning) ; f (Frozen) 3 radii off s.
	var src := w.add_node(&"src", Vector2(-20000, 0))
	var a := w.add_node(&"a", Vector2(0, 0))
	var nb := w.add_node(&"b", Vector2(20000, 0))
	var c := w.add_node(&"c", Vector2(40000, 0))
	var s := w.add_node(&"s", Vector2(0, 40000))
	radius = s.radius
	var f := w.add_node(&"f", Vector2(3.0 * radius, 40000))
	w.link(src, a)
	w.link(a, nb)
	w.link(nb, c)
	w.link(src, s)
	w.allocate(red, [src])
	w.allocate(blue, [a, nb, c, s, f])
	await get_tree().process_frame
	var live := CombatWorld.live()
	for n: SkillNode in [a, nb, f]:
		var slice := live.combat_for(n) as NodeCombat
		slice.add_terrain(fire, -(slice.terrain_threshold() + 1) - slice.terrain_t())
	var sc := live.combat_for(s) as NodeCombat
	sc.add_terrain(fire, sc.terrain_threshold() + 1 - sc.terrain_t())
	var spy := _spy()
	var spell := _walk_spell()

	SpellResolver.resolve_against(spell, a, src, red, w.graph, live, null, _shaped(spell, 3))
	assert_eq(_seen_at(spy, a), [[a, false, 3]], "the seed head of a 3-cut cast reads 3")
	assert_eq(_seen_at(spy, nb), [[nb, false, 0]], "a later hop's head reads 0")

	spy.seen.clear()
	SpellResolver.resolve_against(spell, s, src, red, w.graph, live, null, _shaped(spell, 6))
	var at_f := _seen_at(spy, f)
	assert_false(at_f.is_empty(), "fixture: the Burning seed's disc copies onto the Frozen node")
	for r: Array in at_f:
		assert_eq(r, [f, true, 0], "a copy carries the ×m payload, never the cut")

	spy.seen.clear()
	(live.combat_for(s) as NodeCombat).add_terrain(fire, -sc.terrain_t() - sc.terrain_threshold() - 1)
	SpellResolver.resolve_against(spell, s, src, red, w.graph, live, null, _shaped(spell, 6))
	assert_eq(_seen_at(spy, s), [[s, false, 6]], "the seed head of a 6-cut cast reads 6")
