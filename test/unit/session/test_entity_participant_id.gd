extends GutTest

## #564 — the Entity -> Participant correlation `LootPickRegistry.is_remote_collector`
## needs. [method GameRoot.apply_roster] is a static, side-effect-only function
## (see its own docstring), so this covers the seam directly with no live
## GameRoot/scene, the same way `test/unit/scenes/test_game_root_roster.gd`
## covers the camp/controller assignments it makes alongside this one.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")


func _participant(id: int, kind: Participant.Kind, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	return p


func test_participant_id_is_set_for_a_roster_seated_entity() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(7, Participant.Kind.HUMAN, _CAMP_1))
	var ent: Entity = autofree(Entity.new())

	GameRoot.apply_roster({7: ent}, roster)

	assert_eq(ent.participant_id, 7)


func test_participant_id_is_set_for_an_ai_seated_entity_too() -> void:
	# is_remote_collector's own AI check needs the correlation to exist for
	# AI seats as well — it's the kind check downstream that excludes them,
	# not a hole in the assignment.
	var roster := ParticipantRoster.new()
	roster.add(_participant(3, Participant.Kind.AI, _CAMP_1))
	var ent: Entity = autofree(Entity.new())

	GameRoot.apply_roster({3: ent}, roster)

	assert_eq(ent.participant_id, 3)


func test_participant_id_stays_unset_for_an_entity_no_participant_seats() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_1))
	# Entity 99 has no matching participant row.
	var untouched: Entity = autofree(Entity.new())

	GameRoot.apply_roster({99: untouched}, roster)

	assert_eq(untouched.participant_id, 0)


func test_participant_id_stays_unset_when_participant_has_no_camp() -> void:
	# apply_roster skips a camp-less participant entirely (see its own
	# docstring) — participant_id must not be set in that skip either.
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, null))
	var ent: Entity = autofree(Entity.new())

	GameRoot.apply_roster({1: ent}, roster)

	assert_eq(ent.participant_id, 0)


func test_a_fresh_entity_defaults_to_unset() -> void:
	var ent: Entity = autofree(Entity.new())
	assert_eq(ent.participant_id, 0)
