extends GutTest

## [HitGather] fires a band's [GoOff] at its read, on the gather's world (a
## cast's shadow included), under the head's target mask, each copy on its
## head's crit; two hits of one beat read the pre-beat store and their spends
## sum. Fired here through Burning's [DiscGoOff] on Fire's band (power = Heat's
## excess over T, 1 Heat per other node reached), its knobs read off the def.
## Stage one alone unless a test lands the beat.

const _RAW := 4.0
## Each node's anchor sits this far below it: outside any disc.
const _FAR := 20000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _disc() -> DiscGoOff:
	return _fire().bands[0].go_off as DiscGoOff


## A node at [param pos], linked to its own far anchor (degree 1, so T > 0).
func _at(id: StringName, pos := Vector2.ZERO) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = pos
	var anchor := _w.add_node(StringName("%s_anchor" % id))
	anchor.global_position = pos + Vector2(0.0, _FAR)
	_w.link(n, anchor)
	return n


## The disc's reach at [param power] around [param n].
func _reach(n: SkillNode, power: int) -> float:
	return _disc().disc_radius(power, n.radius)


func _t(n: SkillNode, world: CombatWorld = null) -> int:
	return (world if world != null else CombatWorld.live()).combat_for(n).terrain_threshold()


## [param n]'s Heat on [param world] (live when null).
func _heat(n: SkillNode, world: CombatWorld = null) -> int:
	return (world if world != null else CombatWorld.live()).combat_for(n).terrain_t()


## Raise [param n]'s Heat on [param world] (live when null) to its T + [param excess].
func _prime(n: SkillNode, excess: int, world: CombatWorld = null) -> void:
	var slice := (world if world != null else CombatWorld.live()).combat_for(n)
	slice.add_terrain(_fire(), _t(n, world) + excess - _heat(n, world))


## A node whose hitbox sits [param edge] px from [param centre]'s centre, due east.
func _east_of(centre: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = centre.global_position + Vector2(edge + n.radius, 0.0)
	return n


## A TRUE damage head of [param _RAW] from Blue on [param at], beat 0.
func _head(at: SkillNode) -> DamageInstance:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	d.structural_key = 0.0
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	return d


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


# --- the read: the pre-beat store, the spends summed -----------------------------

func test_two_hits_of_one_beat_read_the_pre_beat_store_and_their_spends_sum() -> void:
	var n := _at(&"N")
	var m := _east_of(n, &"M", _reach(n, 1) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	_prime(n, 1)
	var p := _head(n)
	var q := _head(n)
	var copies := _gather([p, q] as Array[HitInstance])
	for h: HitInstance in [p, q]:
		var mark := _mark(copies, h, n)
		assert_not_null(mark, "each hit goes off")
		if mark != null:
			assert_eq(mark.power, 1, "each reads the pre-beat excess")
	assert_eq(_heat(n), _t(n) + 1 - 2, "the two spends (1 per node reached, each) sum")


func test_the_go_off_reads_and_spends_the_gathers_world_a_casts_shadow_included() -> void:
	var n := _at(&"N")
	var m := _east_of(n, &"M", _reach(n, 1) * 0.5)
	_w.allocate(_red, [n, m])
	await get_tree().process_frame
	_prime(n, 1)
	var shadow := CombatWorld.shadow()
	_prime(n, 3, shadow)
	assert_eq([_heat(n), _heat(n, shadow)], [_t(n) + 1, _t(n) + 3], "fixture: the shadow holds more than live")
	var x := _head(n)
	var mark := _mark(_gather([x] as Array[HitInstance], shadow), x, n)
	assert_not_null(mark, "the go-off fires on the shadow")
	if mark != null:
		assert_eq(mark.power, 3, "it reads the shadow's store")
	assert_eq(_heat(n, shadow), _t(n) + 3 - 1, "it spends off the shadow")
	assert_eq(_heat(n), _t(n) + 1, "the live store is untouched")
	shadow.free_shadow()


# --- what a go-off's copy lands on -----------------------------------------------

func test_the_heads_target_mask_picks_which_reached_nodes_take_a_copy() -> void:
	var n := _at(&"N")
	var edge := _reach(n, 3) * 0.5
	var m := _east_of(n, &"M", edge)
	var k := _w.add_node(&"K")
	k.global_position = n.global_position - Vector2(edge + k.radius, 0.0)
	_w.allocate(_red, [n, m])
	_w.allocate(_blue, [k])
	await get_tree().process_frame
	_prime(n, 3)
	var x := _head(n)
	x.target_mask = SkillNode.Ownership.HOSTILE
	var copies := _gather([x] as Array[HitInstance])
	assert_eq(_marks_on(copies, x, m).size(), 1, "Red's M is hostile to Blue: it takes the copy")
	assert_eq(_marks_on(copies, x, k).size(), 0, "Blue's own K is reached by shape but the mask excludes it")
	for c in copies:
		if c.target == m:
			assert_eq(c.land_mask, SkillNode.Ownership.HOSTILE, "a copy rechecks the head's mask at land")
			assert_eq(c.target_mask, 0, "a copy is no head: it carries no target mask")


func test_a_head_with_no_target_mask_filters_nothing() -> void:
	var n := _at(&"N")
	var k := _east_of(n, &"K", _reach(n, 3) * 0.5)
	_w.allocate(_red, [n])
	_w.allocate(_blue, [k])
	await get_tree().process_frame
	_prime(n, 3)
	var x := _head(n)
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


# --- acceptance 2(d): a copy lands on its head's crit ----------------------------

func test_a_copy_lands_on_its_heads_crit() -> void:
	var n := _at(&"N")
	_east_of(n, &"M", _reach(n, 2) * 0.5)
	_w.allocate(_red, [n])
	await get_tree().process_frame
	_prime(n, 2)
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
