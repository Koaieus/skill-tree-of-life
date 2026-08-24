extends GutTest

## #475 — real faction camps, authored from a [ParticipantRoster] rather than
## derived from "is this entity named player". Covers [method
## GameRoot.apply_roster] (the roster → entity seam) directly: it needs no
## live GameRoot, systems, or lobby UI, only entities and a roster built in
## the test, matching the issue's "test-driven, same as #459" acceptance.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _CAMP_3 := preload("res://entity/factions/camp_3.tres")
const _CAMP_4 := preload("res://entity/factions/camp_4.tres")


func _make_participant(id: int, kind: Participant.Kind, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	return p


func test_two_local_humans_on_one_camp_are_allied_and_human_controlled() -> void:
	var roster := ParticipantRoster.new()
	var p1 := _make_participant(1, Participant.Kind.HUMAN, _CAMP_1)
	var p2 := _make_participant(2, Participant.Kind.HUMAN, _CAMP_1)
	roster.add(p1)
	roster.add(p2)

	var e1: Entity = autofree(Entity.new())
	var e2: Entity = autofree(Entity.new())
	var entities_by_id := {1: e1, 2: e2}

	GameRoot.apply_roster(entities_by_id, roster)

	assert_eq(e1.faction.id, _CAMP_1.id)
	assert_eq(e2.faction.id, _CAMP_1.id)
	assert_true(e1.is_human_controlled)
	assert_true(e2.is_human_controlled)
	assert_eq(e1.attitude_to(e2), Entity.Attitude.ALLIED,
			"same-camp humans must read allied — this is the 'cannot damage each other' gate")
	assert_eq(e2.attitude_to(e1), Entity.Attitude.ALLIED)


func test_four_participants_on_four_camps_are_mutually_hostile() -> void:
	var roster := ParticipantRoster.new()
	var camps := [_CAMP_1, _CAMP_2, _CAMP_3, _CAMP_4]
	var entities_by_id := {}
	for i in 4:
		var participant := _make_participant(i, Participant.Kind.HUMAN, camps[i])
		roster.add(participant)
		entities_by_id[i] = autofree(Entity.new()) as Entity

	GameRoot.apply_roster(entities_by_id, roster)

	assert_eq(roster.camps().size(), 4, "each participant authored a distinct camp")
	for i in 4:
		for j in 4:
			if i == j:
				continue
			var a: Entity = entities_by_id[i]
			var b: Entity = entities_by_id[j]
			assert_eq(a.attitude_to(b), Entity.Attitude.HOSTILE,
					"camp %d vs camp %d must be hostile" % [i, j])


func test_ai_participant_is_not_human_controlled() -> void:
	var roster := ParticipantRoster.new()
	var ai := _make_participant(1, Participant.Kind.AI, _CAMP_2)
	roster.add(ai)
	var ent: Entity = autofree(Entity.new())
	var entities_by_id := {1: ent}

	GameRoot.apply_roster(entities_by_id, roster)

	assert_false(ent.is_human_controlled)
	assert_eq(ent.faction.id, _CAMP_2.id)


func test_remote_human_is_human_controlled() -> void:
	var roster := ParticipantRoster.new()
	var remote := _make_participant(1, Participant.Kind.HUMAN, _CAMP_3)
	roster.add(remote)
	var ent: Entity = autofree(Entity.new())
	var entities_by_id := {1: ent}

	GameRoot.apply_roster(entities_by_id, roster)

	assert_true(ent.is_human_controlled)


func test_participant_with_no_matching_entity_is_skipped() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_make_participant(1, Participant.Kind.HUMAN, _CAMP_1))

	# No entity for id 1 — must not error, and must not touch other entries.
	var untouched: Entity = autofree(Entity.new())
	var default_faction := untouched.faction
	GameRoot.apply_roster({99: untouched}, roster)

	assert_eq(untouched.faction, default_faction)


func test_participant_with_no_camp_leaves_entity_untouched() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_make_participant(1, Participant.Kind.HUMAN, null))
	var ent: Entity = autofree(Entity.new())
	var default_faction := ent.faction

	GameRoot.apply_roster({1: ent}, roster)

	assert_eq(ent.faction, default_faction, "no camp authored — faction must not be overwritten")
	assert_false(ent.is_human_controlled, "skipped entirely, so the controller flag stays default too")
