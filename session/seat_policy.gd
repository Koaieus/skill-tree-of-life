class_name SeatPolicy
extends RefCounted

## Who THIS MACHINE plays, and whose eyes it draws with. The per-machine half
## of a run's setup — the half that legitimately differs between two peers
## watching the same world.
##
## [b]The invariant:[/b] a SeatPolicy never feeds anything a peer must
## reproduce. Not procgen, not an RNG stream, not command application. It
## decides what this screen shows and which entities this screen calls "mine";
## every peer may answer differently and the simulations still agree. Camp
## structure — how many camps, who is on them — is the OTHER half: it comes off
## the [ParticipantRoster], is identical on every machine, and is what level
## generation may read (#516). Placement that consults a seat is a desync.
##
## Note this is not merely cosmetic: [VisionSystem] toggles
## [member SkillNode.input_pickable] on recompute, so the vision group shapes
## the legal intent surface on this machine. It shapes what may be *offered*
## here, never what a command *does* once submitted.
##
## [b]Two shapes, one axis.[/b]
##
## [codeblock]
##                        seats                follows_active_turn
##   single player        the one hero         (moot — one human)
##   hot-seat coop        both humans          yes — the couch shares a screen
##   hot-seat versus      both humans          yes
##   online (any mode)    my hero only         no — my view stays mine
## [/codeblock]
##
## COUCH and SEAT are exactly the two un-decisions the multiplayer harness used
## to make by hand (`scenes/dev/mp_dev_sandbox.gd`: disconnect the handover,
## re-point [member GameRoot.player]). Coop-vs-versus is deliberately absent —
## that distinction is [member Participant.camp] and nothing here needs it.
##
## [b]Deliberately not here:[/b] whether input may SUBMIT. That is command
## authority (#463) — a client can be seated on a hero it may not yet act for,
## which is what [method PlayerInputController.set_input_frozen] expresses.

enum Seating {
	## This machine drives every local human and the view follows whoever acts.
	## Single player, hot-seat coop, hot-seat versus.
	COUCH,
	## This machine drives exactly one hero and the view stays pinned to it.
	## Any run with a peer on the other end of a wire.
	SEAT,
}

var seating: Seating = Seating.COUCH
## Which hero this machine is seated at, by [member Entity.entity_id]. Unread
## under [constant Seating.COUCH]. Keyed on `entity_id` rather than a
## participant id because that is already the host-minted cross-wire identity
## (`.claude/rules/multiplayer-sync.md`); a second id field would buy nothing.
var seated_entity_id: int = 0


## Every local human plays, the view follows the turn. The default, and what a
## roster-less scene (dev_sandbox, a GUT fixture) gets.
static func couch() -> SeatPolicy:
	return SeatPolicy.new()


## One hero, pinned. [param entity_id] is [member Entity.entity_id].
static func seat(entity_id: int) -> SeatPolicy:
	var policy := SeatPolicy.new()
	policy.seating = Seating.SEAT
	policy.seated_entity_id = entity_id
	return policy


## The policy for the machine identified by [param local_peer_id], given the
## run's roster and the entity spawned for each participant — the same
## `{participant_id: Entity}` dictionary [method GameRoot.apply_roster] takes,
## so the two calls sit side by side at a level's setup.
##
## COUCH when every human in the roster sits at this peer; SEAT otherwise,
## pinned to this peer's first human. A roster with no human at all
## (a self-driven showcase) is a COUCH with nothing to drive.
##
## [b]Reached, but not yet discriminating.[/b] The menu path does arrive here:
## `scenes/meta/meta_root.gd` calls [method GameSession.start] and routes to a
## level, and since #553 that level spawns from the session's roster instead of
## inventing one. What is still missing is a roster with more than one machine
## in it — every participant a lobby builds today is a LOCAL_HUMAN sharing
## [param local_peer_id], so this correctly returns [method couch] every time.
## #554 is what puts a REMOTE_HUMAN with a real `peer_id` in the roster; this
## function needs no change when it does. Today's callers are the procgen
## sandbox and the multiplayer harness.
static func from_roster(
	entities_by_participant_id: Dictionary,
	roster: ParticipantRoster,
	local_peer_id: int = 0
) -> SeatPolicy:
	if roster == null:
		return couch()
	var mine: Array[Entity] = []
	var remote_humans := false
	for participant in roster.all():
		if participant.kind == Participant.Kind.AI:
			continue
		if participant.peer_id == local_peer_id:
			var ent: Entity = entities_by_participant_id.get(participant.id)
			if ent != null:
				mine.append(ent)
		else:
			remote_humans = true
	if not remote_humans:
		return couch()
	if mine.is_empty():
		# A pure spectator: no hero of its own, so it may not claim one. Pinned
		# (a spectator whose view chased every turn would be a couch), seated on
		# nobody — `seats()` is false for every entity.
		return seat(0)
	return seat(mine[0].entity_id)


## Is [param entity] one of this machine's heroes — the ones whose turn this
## screen is meant to serve?
func seats(entity: Entity) -> bool:
	if entity == null:
		return false
	if seating == Seating.SEAT:
		return entity.entity_id != 0 and entity.entity_id == seated_entity_id
	return entity.is_human_controlled


## Does the local view re-point when a hero this machine seats takes its turn?
## True on a shared couch, false behind a wire.
func follows_active_turn() -> bool:
	return seating == Seating.COUCH


## Whose sight unions into the local fog, given the bound hero and the
## entities to consider (pass them in group order — see the ordering note on
## [method GameRoot._apply_camp_vision]).
##
## The rule is [b]allied humans[/b]: an entity that is human-controlled and
## shares [param hero]'s camp. That single line covers every case the four run
## shapes ask for, and the reason it does is worth stating, because the next
## reader will reach for [member Participant.peer_id] and not need it:
##
## - [b]Coop shares.[/b] Two humans on one camp — couch or wire — see for each
##   other. [method GameRoot.apply_roster] sets `is_human_controlled` from
##   [member Participant.kind], and a REMOTE_HUMAN is human, so a teammate on
##   another machine reveals for me exactly as a couch partner does.
## - [b]Versus does not.[/b] Rivals are on different camps by construction, so
##   each hero's group is itself. On a hot-seat couch the group swaps with the
##   handover, which is the point.
## - [b]AI never shares[/b], with the player or with another AI. An AI ally
##   sitting on a human camp does not reveal for it, and AI recon was never
##   this system's business anyway — [AiRecon] builds its own per-entity
##   circles. Faction-shared AI reveal stays the difficulty lever it is
##   filed as (#394).
## - [b]Blockers never share.[/b] Not human, and on their own dormant camp.
##
## [param hero] is always included, even when it fails the filter (a level may
## bind before the entity joins the group, and a showcase may bind an AI) —
## the local view must never end up drawing from nobody.
static func vision_group(hero: Entity, candidates: Array[Entity]) -> Array[Entity]:
	var group: Array[Entity] = []
	if hero == null:
		return group
	var camp: StringName = hero.faction.id if hero.faction != null else &""
	for ent in candidates:
		if ent == null or not ent.is_human_controlled or ent.faction == null:
			continue
		# By `faction.id`, matching [method Entity.attitude_to] — camp fog and
		# camp allegiance must not be two different answers to "same camp?", or
		# a duplicated Faction resource splits vision while attitude still
		# reads allied.
		if ent.faction.id != &"" and ent.faction.id == camp:
			group.append(ent)
	if not group.has(hero):
		group.append(hero)
	return group
