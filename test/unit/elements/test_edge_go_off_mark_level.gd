extends GutTest

## An [EdgeGoOff]'s result names the level it arced at in
## [member GoOffResult.power], so the [BlastMark] the gather mints from it
## carries the hop count the board's arc draws. [member GoOffResult.reach]
## stays 0: it is a disc's px, and an arc has none.

var _w: TestWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


func _edge() -> EdgeGoOff:
	return ElementRoster.shared().by_id(&"lightning").bands[0].go_off as EdgeGoOff


func _line(n: int) -> Array[SkillNode]:
	var pairs: Array = []
	var pos := {}
	for i in n:
		pos[i] = Vector2(i * 3000.0, 0.0)
		if i + 1 < n:
			pairs.append([i, i + 1])
	return _w.build(pairs, pos)


func _read(charge: int, t: int) -> TerrainRead:
	var r := TerrainRead.new()
	r.charge = charge
	r.threshold = t
	r.cap = 1000
	return r


func test_the_result_names_its_level_as_power() -> void:
	var arc := _edge()
	assert_not_null(arc, "Lightning's Shocked band holds an EdgeGoOff")
	if arc == null:
		return
	var c := _line(7)[3]
	var t := 3
	var lv1 := _read(t + 1, t)
	var lv2 := _read(int(pow(2, arc.ladder_exponent)) * t + 1, t)
	assert_eq(arc.fire(c, lv1).power, arc.level_of(lv1), "a level-1 arc names level 1")
	assert_eq(arc.fire(c, lv2).power, arc.level_of(lv2), "a level-2 arc names level 2")
	assert_eq(arc.fire_level_in(null, c, lv1, _shape(1)).power, arc.level_of(lv1) + 1,
			"an added level names the whole level it reached")
	assert_eq(arc.fire(c, lv2).reach, 0.0, "an arc has no px reach")


## A cast shape of [param points] as the incoming party: level
## [method EdgeGoOff.level_for_points] of it.
func _shape(points: int) -> GoOffSource:
	return GoOffSource.shape(Element.new(), points)
