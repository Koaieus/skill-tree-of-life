extends GutTest

## [SeatPolicy] — the per-machine half of a run's setup. Pure logic here (no
## level, no scene): the four run shapes as a truth table over the two
## questions the policy answers, plus the vision rule.
##
## The live-level counterparts are `test/unit/scenes/test_hot_seat_handover.gd`
## (couch coop) and `test_seat_vision.gd` (couch versus, seated peer).

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _BLOCKER := preload("res://entity/factions/blocker.tres")


func _entity(id: int, human: bool, camp: Faction) -> Entity:
	var e := Entity.new()
	e.entity_id = id
	e.is_human_controlled = human
	e.faction = camp
	autofree(e)
	return e


func _participant(id: int, kind: Participant.Kind, camp: Faction, peer_id: int = 0) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	p.peer_id = peer_id
	return p


# --- The couch/seat axis --------------------------------------------------

func test_a_couch_drives_every_human_and_follows_the_turn() -> void:
	var policy := SeatPolicy.couch()
	assert_true(policy.follows_active_turn(), "a shared screen re-points on handover")
	assert_true(policy.seats(_entity(1, true, _CAMP_1)))
	assert_true(policy.seats(_entity(2, true, _CAMP_2)),
			"couch versus is still a couch — the rival at the same keyboard is mine to drive")
	assert_false(policy.seats(_entity(3, false, _NPC)), "an AI is nobody's seat")
	assert_false(policy.seats(null))


func test_a_seat_drives_one_hero_and_stays_pinned() -> void:
	var policy := SeatPolicy.seat(7)
	assert_false(policy.follows_active_turn(), "behind a wire the local view is mine")
	assert_true(policy.seats(_entity(7, true, _CAMP_1)))
	assert_false(policy.seats(_entity(8, true, _CAMP_1)),
			"my ally is not my seat, however friendly")


## `entity_id` is 0 until an entity enters `entities_container`, and 0 is the
## spectator seat — an unminted entity must not accidentally match it.
func test_an_unminted_entity_never_matches_a_seat() -> void:
	assert_false(SeatPolicy.seat(0).seats(_entity(0, true, _CAMP_1)))
	assert_false(SeatPolicy.seat(5).seats(_entity(0, true, _CAMP_1)))


# --- from_roster: the four run shapes -------------------------------------

func test_single_player_is_a_couch() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(0, Participant.Kind.HUMAN, _CAMP_1))
	roster.add(_participant(1, Participant.Kind.AI, _NPC))
	var hero := _entity(10, true, _CAMP_1)
	var policy := SeatPolicy.from_roster({0: hero, 1: _entity(11, false, _NPC)}, roster)
	assert_eq(policy.seating, SeatPolicy.Seating.COUCH)


func test_hot_seat_is_a_couch_in_coop_and_in_versus() -> void:
	for camps in [[_CAMP_1, _CAMP_1], [_CAMP_1, _CAMP_2]]:
		var roster := ParticipantRoster.new()
		roster.add(_participant(0, Participant.Kind.HUMAN, camps[0]))
		roster.add(_participant(1, Participant.Kind.HUMAN, camps[1]))
		var entities := {0: _entity(10, true, camps[0]), 1: _entity(11, true, camps[1])}
		var policy := SeatPolicy.from_roster(entities, roster)
		assert_eq(policy.seating, SeatPolicy.Seating.COUCH,
				"coop and versus differ by camp, never by seating")
		assert_true(policy.seats(entities[1]))


func test_a_remote_human_makes_this_machine_a_seat() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(0, Participant.Kind.HUMAN, _CAMP_1))
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_2, 2))
	var mine := _entity(10, true, _CAMP_1)
	var theirs := _entity(11, true, _CAMP_2)
	var policy := SeatPolicy.from_roster({0: mine, 1: theirs}, roster)

	assert_eq(policy.seating, SeatPolicy.Seating.SEAT)
	assert_false(policy.follows_active_turn(),
			"the remote player's turn must not swing my HUD onto their hero")
	assert_true(policy.seats(mine))
	assert_false(policy.seats(theirs))


func test_a_peer_with_no_hero_of_its_own_is_a_pinned_spectator() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(0, Participant.Kind.HUMAN, _CAMP_1, 2))
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_2, 3))
	var policy := SeatPolicy.from_roster({0: _entity(10, true, _CAMP_1)}, roster)

	assert_eq(policy.seating, SeatPolicy.Seating.SEAT)
	assert_false(policy.seats(_entity(10, true, _CAMP_1)),
			"a spectator claims nobody's hero")


func test_no_roster_falls_back_to_a_couch() -> void:
	assert_eq(SeatPolicy.from_roster({}, null).seating, SeatPolicy.Seating.COUCH)
	assert_eq(SeatPolicy.from_roster({}, ParticipantRoster.new()).seating,
			SeatPolicy.Seating.COUCH,
			"an AI-only showcase is a couch with nothing to drive")


# --- The vision rule ------------------------------------------------------

func test_coop_shares_camp_vision() -> void:
	var p1 := _entity(1, true, _CAMP_1)
	var p2 := _entity(2, true, _CAMP_1)
	var group := SeatPolicy.vision_group(p1, [p1, p2])
	assert_eq(group, [p1, p2] as Array[Entity])
	assert_eq(SeatPolicy.vision_group(p2, [p1, p2]), group,
			"both sides of a coop handover must produce the SAME array — "
			+ "order included, or the equality skip misses and the fog flashes")


func test_versus_does_not_share_vision() -> void:
	var p1 := _entity(1, true, _CAMP_1)
	var p2 := _entity(2, true, _CAMP_2)
	assert_eq(SeatPolicy.vision_group(p1, [p1, p2]), [p1] as Array[Entity])
	assert_eq(SeatPolicy.vision_group(p2, [p1, p2]), [p2] as Array[Entity],
			"a hot-seat rival's fog is their own, and swaps on handover")


## The point of keying on `is_human_controlled` rather than camp alone: an AI
## ally sitting on a human camp does not reveal for it.
func test_an_ai_ally_on_my_camp_does_not_see_for_me() -> void:
	var hero := _entity(1, true, _CAMP_1)
	var ai_ally := _entity(2, false, _CAMP_1)
	assert_eq(SeatPolicy.vision_group(hero, [hero, ai_ally]), [hero] as Array[Entity])


func test_ai_and_blockers_never_share_vision_with_each_other() -> void:
	var ai_a := _entity(1, false, _NPC)
	var ai_b := _entity(2, false, _NPC)
	var blocker := _entity(3, false, _BLOCKER)
	# Bound as the hero (a self-driven showcase), an AI still sees only itself.
	assert_eq(SeatPolicy.vision_group(ai_a, [ai_a, ai_b, blocker]), [ai_a] as Array[Entity])
	assert_eq(SeatPolicy.vision_group(blocker, [ai_a, ai_b, blocker]), [blocker] as Array[Entity])


## A teammate on another machine is `is_human_controlled` on mine too
## (apply_roster reads [member Participant.kind], which says HUMAN wherever that
## human sits) — which is why online coop shares vision without the rule ever
## consulting `peer_id`.
func test_the_vision_rule_is_independent_of_seating() -> void:
	var mine := _entity(1, true, _CAMP_1)
	var remote_ally := _entity(2, true, _CAMP_1)
	var group := SeatPolicy.vision_group(mine, [mine, remote_ally])
	assert_eq(group, [mine, remote_ally] as Array[Entity],
			"an ally on another machine reveals for me exactly as a couch partner does")


func test_the_hero_is_always_a_viewer() -> void:
	var hero := _entity(1, true, _CAMP_1)
	assert_eq(SeatPolicy.vision_group(hero, []), [hero] as Array[Entity],
			"a hero not yet in the entities group must still see")
	var factionless := _entity(2, true, null)
	assert_eq(SeatPolicy.vision_group(factionless, []), [factionless] as Array[Entity])
	assert_eq(SeatPolicy.vision_group(null, []), [] as Array[Entity])


# --- #562: the roster crossed a wire --------------------------------------

## The defect behind #562, as pure data: a roster the HOST authored, decoded by
## the CLIENT, must seat the client on its own hero. Under the old enum's
## local/remote human split the payload said "A is local" no matter who
## read it — a relation frozen into a fact, and wrong for exactly one of the two
## readers. With [enum Participant.Kind] collapsed to `{ HUMAN, AI }` there is
## no such claim on the wire: local-ness is derived from `peer_id`, so the SAME
## payload seats each peer on its own hero.
func _wire_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	roster.add(_participant(0, Participant.Kind.HUMAN, _CAMP_1, 1))
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_2, 2))
	return ParticipantRoster.from_dict(roster.to_dict())


func test_the_hosts_roster_seats_the_client_on_its_own_hero() -> void:
	var decoded := _wire_roster()
	var host_hero := _entity(10, true, _CAMP_1)
	var client_hero := _entity(11, true, _CAMP_2)
	var entities := {0: host_hero, 1: client_hero}

	var on_client := SeatPolicy.from_roster(entities, decoded, 2)
	assert_eq(on_client.seating, SeatPolicy.Seating.SEAT)
	assert_true(on_client.seats(client_hero),
			"the client plays its own hero, not the spectator seat")
	assert_false(on_client.seats(host_hero))

	var on_host := SeatPolicy.from_roster(entities, decoded, 1)
	assert_eq(on_host.seating, SeatPolicy.Seating.SEAT)
	assert_true(on_host.seats(host_hero), "the symmetric read of the same payload")
	assert_false(on_host.seats(client_hero))


## [method Participant.is_local] is the one named home for the question, and it
## answers differently on the two machines reading the same decoded row.
func test_is_local_is_answered_against_this_machines_peer_id() -> void:
	var rows := _wire_roster().all()
	assert_true(rows[0].is_local(1))
	assert_false(rows[0].is_local(2))
	assert_true(rows[1].is_local(2))
	assert_false(rows[1].is_local(1))
