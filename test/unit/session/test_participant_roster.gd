extends GutTest

var roster: ParticipantRoster


func before_each() -> void:
	roster = ParticipantRoster.new()


func _make(id: int, kind: Participant.Kind = Participant.Kind.LOCAL_HUMAN) -> Participant:
	var p := Participant.new()
	p.id = id
	p.display_name = "P%d" % id
	p.kind = kind
	return p


func test_add_emits_joined_then_roster_changed_in_order() -> void:
	var events: Array[String] = []
	roster.participant_joined.connect(func(_p): events.append("joined"))
	roster.roster_changed.connect(func(): events.append("changed"))

	roster.add(_make(1))

	assert_eq(events, ["joined", "changed"])


func test_remove_emits_left_then_roster_changed_in_order() -> void:
	roster.add(_make(1))
	var events: Array[String] = []
	roster.participant_left.connect(func(_p): events.append("left"))
	roster.roster_changed.connect(func(): events.append("changed"))

	roster.remove(1)

	assert_eq(events, ["left", "changed"])


func test_notify_changed_emits_participant_changed() -> void:
	roster.add(_make(1))
	var seen: Array[Participant] = []
	roster.participant_changed.connect(func(p): seen.append(p))

	roster.notify_changed(1)

	assert_eq(seen.size(), 1)
	assert_eq(seen[0].id, 1)


func test_remove_unknown_id_is_a_no_op() -> void:
	roster.add(_make(1))
	var fired := [false]
	roster.participant_left.connect(func(_p): fired[0] = true)

	roster.remove(999)

	assert_false(fired[0])
	assert_eq(roster.all().size(), 1)


func test_by_id_finds_correct_participant() -> void:
	roster.add(_make(1))
	roster.add(_make(2))
	roster.add(_make(3))

	var found := roster.by_id(2)

	assert_not_null(found)
	assert_eq(found.display_name, "P2")
	assert_null(roster.by_id(42))


func test_local_humans_filters_by_kind() -> void:
	roster.add(_make(1, Participant.Kind.LOCAL_HUMAN))
	roster.add(_make(2, Participant.Kind.AI))
	roster.add(_make(3, Participant.Kind.LOCAL_HUMAN))

	var humans := roster.local_humans()

	assert_eq(humans.size(), 2)
	assert_eq(humans[0].id, 1)
	assert_eq(humans[1].id, 3)


func test_camps_deduplicates_shared_faction() -> void:
	var faction := Faction.new()
	faction.id = &"player"
	var a := _make(1)
	a.camp = faction
	var b := _make(2)
	b.camp = faction

	roster.add(a)
	roster.add(b)

	assert_eq(roster.camps().size(), 1)
