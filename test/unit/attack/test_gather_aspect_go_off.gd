extends GutTest

## #1799 (Unit F-a): [HitGather] fires an [member Aspect.go_off] at its read,
## beside the element bands and never behind their band test (Explosive has no
## terrain axis, so no band). Here a [DiscGoOff] the test authors on the
## Explosive [Aspect]; nothing on master authors one. The go-off's spend
## commits on the holder's Explosive row with the generation's other spends,
## summed, clamped at 0; its mark takes the disc's reach and power; it reads
## the gather's world, a cast's shadow included. Generation 0 reads the
## pre-beat store, a copy's generation the store the one before it left
## (ADR 0091 §1; acceptance 2f's rule). Stage one alone unless a test lands
## the beat.

const _RAW := 4.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _aspect: Aspect
var _was: GoOff
var _disc: DiscGoOff


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame
	_aspect = AspectRoster.shared().by_id(&"explosive")
	_was = _aspect.go_off
	_disc = DiscGoOff.new()
	_aspect.go_off = _disc


func after_each() -> void:
	_aspect.go_off = _was
	CombatWorld.reset_live()


func _def() -> StatusDef:
	return StatusRoster.shared().by_concept(&"explosive")


func _spread() -> ExplosiveSpread:
	return _def().spread as ExplosiveSpread


func _charge(holder: Object, n: int) -> void:
	holder.get_combat().apply_status(_def(), float(n))


## The Explosive charges on [param n]'s slice of [param world] (live when null).
func _held(n: SkillNode, world: CombatWorld = null) -> int:
	var w := world if world != null else CombatWorld.live()
	return int(w.combat_for(n).get_status_power(&"explosive"))


## A node whose hitbox sits [param edge] px from [param centre]'s centre, due east.
func _east_of(centre: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = centre.global_position + Vector2(edge + n.radius, 0.0)
	return n


## A TRUE damage head of [param _RAW] from Blue on [param at], beat 0.
func _head(at: SkillNode, load := 0) -> DamageInstance:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	d.structural_key = 0.0
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.hit_load = load
	return d


func _status(def: StatusDef, power: float, at: SkillNode) -> StatusInstance:
	var s := StatusInstance.new()
	s.target = at
	s.attacker = _blue
	s.schedule_index = 0
	s.def = def
	s.power = power
	s.raw = true
	return s


## Stage one over [param hits] on [param world] (live when null): the entries it
## pushed.
func _gather(hits: Array[HitInstance], world: CombatWorld = null) -> Array[HitInstance]:
	var all: Array[HitInstance] = hits.duplicate()
	HitGather.stage_one(hits.duplicate(), world if world != null else CombatWorld.live(), HitQueue.over(all))
	return all.slice(hits.size())


## The marks [param head]'s copies on [param at] carry.
func _marks_on(copies: Array[HitInstance], head: HitInstance, at: SkillNode) -> Array:
	var out: Array = []
	for c in copies:
		if c.paired == head and c.target == at and c.blast_mark != null and not out.has(c.blast_mark):
			out.append(c.blast_mark)
	return out


## The mark of [param head]'s go-off centred on [param centre], or null.
func _mark(copies: Array[HitInstance], head: HitInstance, centre: SkillNode) -> BlastMark:
	for c in copies:
		if c.paired == head and c.blast_mark != null and c.blast_mark.centre == centre:
			return c.blast_mark
	return null


# --- generations: 2f's rule on the aspect's disc --------------------------------

func test_a_copy_sets_a_node_off_again_reading_the_store_the_generation_before_left() -> void:
	var a := _w.add_node(&"A", Vector2.ZERO)
	var reach_5 := _spread().radius_for(a.radius, 5)
	var reach_3 := _spread().radius_for(a.radius, 3)
	# A at power 5 reaches B; B at power 3 (or 2) never reaches A.
	var b := _east_of(a, &"B", (reach_5 + reach_3) * 0.5)
	# C sits inside B's power-2 disc and far past A's.
	var c := _east_of(b, &"C", _spread().radius_for(b.radius, 2) * 0.5)
	_w.allocate(_red, [a, b, c])
	await get_tree().process_frame
	_charge(a, 5)
	_charge(b, 3)
	_disc.lands_on_own_node = false  # go-off zero's shape: every entry is a reached node's
	var x := _head(a)
	var y := _head(b)
	var copies := _gather([x, y] as Array[HitInstance])
	var res := _spread().resonance
	var on_a := _mark(copies, x, a)
	var y_on_b := _mark(copies, y, b)
	var x_on_b := _mark(copies, x, b)
	assert_not_null(on_a, "X's go-off on A fires (no band: the aspect's read)")
	assert_not_null(y_on_b, "Y's go-off on B fires")
	assert_not_null(x_on_b, "X's copy sets B off again, for X's hit")
	if on_a == null or y_on_b == null or x_on_b == null:
		return
	assert_eq([on_a.generation, y_on_b.generation, x_on_b.generation], [0, 0, 1],
			"the beat's own go-offs fire at generation 0, the copy's at 1")
	assert_eq(on_a.power, DiscGoOff.power_of(0, 5, res), "A reads its pre-beat charges")
	assert_eq(y_on_b.power, DiscGoOff.power_of(0, 3, res), "Y on B reads the pre-beat 3")
	assert_eq(x_on_b.power, DiscGoOff.power_of(0, 2, res),
			"X's copy on B reads the 2 generation 0 left, never the pre-beat 3")
	assert_almost_eq(on_a.reach, _disc.radius_at(a, on_a.power), 0.0001, "the mark's reach is the disc's radius")
	assert_almost_eq(x_on_b.reach, _disc.radius_at(b, x_on_b.power), 0.0001,
			"at the power it read in generation 1")
	assert_same(on_a.go_off, _aspect.identity, "the mark names the aspect's go-off")
	assert_eq(_marks_on(copies, x, b), [on_a], "X's entry on B carries A's mark")
	assert_eq(_marks_on(copies, x, c), [x_on_b], "X's entry on C carries B's generation-1 mark")
	assert_eq(_marks_on(copies, y, c), [y_on_b], "Y's entry on C carries B's generation-0 mark")
	assert_true(_marks_on(copies, y, a).is_empty(), "B's disc never reaches A")
	assert_eq(_held(a), 5 - DiscGoOff.spend_of(0, 5), "A spends once")
	assert_eq(_held(b), 3 - DiscGoOff.spend_of(0, 3) - DiscGoOff.spend_of(0, 2), "B spends in each generation")


# --- the spend: summed, clamped, off the holder ---------------------------------

func test_two_hits_of_one_beat_read_the_pre_beat_store_and_spend_summed_clamped_at_zero() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var m := _east_of(n, &"M", _spread().radius_for(n.radius, 1) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	_charge(n, 1)
	var p := _head(n)
	var q := _head(n)
	var copies := _gather([p, q] as Array[HitInstance])
	for h: HitInstance in [p, q]:
		var mark := _mark(copies, h, n)
		assert_not_null(mark, "each hit goes off")
		if mark != null:
			assert_eq(mark.power, DiscGoOff.power_of(0, 1, _spread().resonance), "each reads the pre-beat charge")
	assert_eq(_held(n), 0, "the two spends sum and clamp at 0")


func test_a_core_with_no_charges_spends_off_its_owners_entity_rows() -> void:
	var core := _w.add_node(&"Core", Vector2.ZERO)
	var m := _east_of(core, &"M", _spread().radius_for(core.radius, 1) * 0.5)
	_w.allocate(_red, [core, m])
	await get_tree().process_frame
	assert_true(CombatWorld.live().combat_for(core).is_core(), "fixture: Core is red's core")
	_charge(_red, 2)
	var x := _head(core, 3)
	var mark := _mark(_gather([x] as Array[HitInstance]), x, core)
	assert_not_null(mark, "the core goes off on its owner's charges")
	if mark != null:
		assert_eq(mark.power, DiscGoOff.power_of(3, 2, _spread().resonance), "power reads the entity's rows")
	var left := CombatWorld.live().combat_for_entity(_red).get_status_power(&"explosive")
	assert_almost_eq(left, 2.0 - DiscGoOff.spend_of(3, 2), 0.0001, "and the spend comes off them")


func test_the_go_off_reads_and_spends_the_gathers_world_a_casts_shadow_included() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var m := _east_of(n, &"M", _spread().radius_for(n.radius, 1) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	_charge(n, 2)
	var shadow := CombatWorld.shadow()
	shadow.combat_for(n).adjust_status_power(_def(), 2.0)
	assert_eq([_held(n), _held(n, shadow)], [2, 4], "fixture: the shadow holds more than live")
	var x := _head(n)
	var mark := _mark(_gather([x] as Array[HitInstance], shadow), x, n)
	assert_not_null(mark, "the go-off fires on the shadow")
	if mark != null:
		assert_eq(mark.power, DiscGoOff.power_of(0, 4, _spread().resonance), "it reads the shadow's store")
	assert_eq(_held(n, shadow), 4 - DiscGoOff.spend_of(0, 4), "it spends off the shadow")
	assert_eq(_held(n), 2, "the live store is untouched")
	shadow.free_shadow()


# --- what sets it off ------------------------------------------------------------

func test_the_heads_target_mask_picks_which_reached_nodes_take_a_copy() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var edge := _spread().radius_for(n.radius, 3) * 0.5
	var m := _east_of(n, &"M", edge)
	var k := _w.add_node(&"K")
	k.global_position = n.global_position - Vector2(edge + k.radius, 0.0)
	_w.allocate(_red, [n, m])
	_w.allocate(_blue, [k])
	await get_tree().process_frame
	var x := _head(n, 3)
	x.target_mask = SkillNode.Ownership.HOSTILE
	var copies := _gather([x] as Array[HitInstance])
	assert_eq(_marks_on(copies, x, m).size(), 1, "Red's M is hostile to Blue: it takes the copy")
	assert_eq(_marks_on(copies, x, k).size(), 0, "Blue's own K is reached by shape but the mask excludes it")
	for c in copies:
		if c.target == m:
			assert_eq(c.land_mask, SkillNode.Ownership.HOSTILE, "a copy rechecks the head's mask at land")
			assert_eq(c.target_mask, 0, "a copy is no head: it carries no target mask")


func test_a_head_with_no_target_mask_filters_nothing() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var k := _east_of(n, &"K", _spread().radius_for(n.radius, 3) * 0.5)
	_w.allocate(_red, [n])
	_w.allocate(_blue, [k])
	await get_tree().process_frame
	var x := _head(n, 3)
	var copies := _gather([x] as Array[HitInstance])
	assert_eq(_marks_on(copies, x, k).size(), 1, "mask 0 is no filter, as land_mask's 0 is no recheck")


func test_place_stamps_the_landings_target_mask_on_the_head() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var x := _head(n)
	x.is_head = false
	var hits: Array[HitInstance] = [x]
	var landing := HitLanding.riding(x, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	landing.place()
	assert_true(x.is_head, "fixture: the span's first hit is the head")
	assert_eq(x.target_mask, SkillNode.Ownership.HOSTILE, "the head carries its landing's mask")


func test_a_loaded_hit_sets_off_a_clean_node_and_spends_nothing() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	var m := _east_of(n, &"M", _spread().radius_for(n.radius, 3) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	var x := _head(n, 3)
	var copies := _gather([x] as Array[HitInstance])
	var mark := _mark(copies, x, n)
	assert_not_null(mark, "power is the load alone: a clean node still goes off")
	if mark != null:
		assert_eq(mark.power, DiscGoOff.power_of(3, 0, _spread().resonance), "at the load's power")
	assert_eq(_marks_on(copies, x, m).size(), 1, "M takes the copy")
	assert_eq(_held(n), 0, "spend_of a clean node is 0: no row appears")


func test_a_hit_planting_the_aspects_own_row_does_not_set_it_off() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	_east_of(n, &"M", _spread().radius_for(n.radius, 2) * 0.5)
	_w.allocate(_red, [n])
	await get_tree().process_frame
	_charge(n, 2)
	var x := _head(n)
	var copies := _gather([x, _status(_def(), 2.0, n)] as Array[HitInstance])
	assert_true(copies.is_empty(), "a planting hit makes no copy (go-off zero's PlantUse skip)")
	assert_eq(_held(n), 2, "and spends nothing")


# --- acceptance 2(d): a copy lands on its head's crit ----------------------------

func test_a_copy_lands_on_its_heads_crit() -> void:
	var n := _w.add_node(&"N", Vector2.ZERO)
	_east_of(n, &"M", _spread().radius_for(n.radius, 2) * 0.5)
	_w.allocate(_red, [n])
	await get_tree().process_frame
	_charge(n, 2)
	var x := _head(n)
	x.is_crit = true
	x.crit_tier = 2
	x.crit_multiplier = 3.0
	x.crit_decided = true
	var all: Array[HitInstance] = [x]
	await OutcomeApplier.drain(HitQueue.over(all), CombatWorld.live(), BeatClock.instant_clock(), null,
			RandomNumberGenerator.new())
	var copies := all.slice(1).filter(func(h: HitInstance) -> bool: return h.paired == x)
	assert_false(copies.is_empty(), "the go-off sends a copy")
	for c: HitInstance in copies:
		assert_eq([c.crit_tier, c.crit_multiplier], [x.crit_tier, x.crit_multiplier],
				"the copy carries the head's crit, never its own roll")
