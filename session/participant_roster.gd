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
