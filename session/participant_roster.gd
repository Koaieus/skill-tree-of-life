class_name ParticipantRoster
extends RefCounted

## Live participant list for the current run — the "press start to join"
## surface; a lobby scene is a pure view over this. Not a Resource: it is
## runtime state owned by GameSession, never saved/loaded as data.

signal participant_joined(p: Participant)
signal participant_left(p: Participant)
signal participant_changed(p: Participant)
signal roster_changed

var _participants: Array[Participant] = []


func add(p: Participant) -> void:
	_participants.append(p)
	participant_joined.emit(p)
	roster_changed.emit()


func remove(id: int) -> void:
	var p := by_id(id)
	if p == null:
		return
	_participants.erase(p)
	participant_left.emit(p)
	roster_changed.emit()


func by_id(id: int) -> Participant:
	for p in _participants:
		if p.id == id:
			return p
	return null


func notify_changed(id: int) -> void:
	var p := by_id(id)
	if p == null:
		return
	participant_changed.emit(p)
	roster_changed.emit()


func local_humans() -> Array[Participant]:
	var result: Array[Participant] = []
	for p in _participants:
		if p.kind == Participant.Kind.LOCAL_HUMAN:
			result.append(p)
	return result


func camps() -> Array[Faction]:
	var result: Array[Faction] = []
	for p in _participants:
		if p.camp != null and not result.has(p.camp):
			result.append(p.camp)
	return result


func all() -> Array[Participant]:
	return _participants.duplicate()


## Wire form for #528 — a flat list of [method Participant.to_dict] rows. The
## roster itself carries no other state (it's runtime bookkeeping, not
## authored data — see the class docstring), so there is nothing else to fold in.
func to_dict() -> Dictionary:
	var rows: Array = []
	for p in _participants:
		rows.append(p.to_dict())
	return {"participants": rows}


## Rebuilds a roster from [method to_dict]'s payload. Goes through [method add]
## (not a direct array write) so `participant_joined` / `roster_changed` fire
## exactly as they would for a locally-joined participant — a lobby view
## listening on those signals doesn't need to know whether a participant
## arrived locally or over the wire.
static func from_dict(d: Dictionary) -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for row in (d.get("participants", []) as Array):
		roster.add(Participant.from_dict(row as Dictionary))
	return roster
