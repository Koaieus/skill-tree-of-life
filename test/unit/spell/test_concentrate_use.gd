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
