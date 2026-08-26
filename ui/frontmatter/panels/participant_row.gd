class_name ParticipantRow
extends HBoxContainer
## One participant row: swatch (color), name, seat description ("you", "AI", "peer N").
## Configured with a [Participant] in [method configure].


func configure(participant: Participant, local_peer_id: int) -> void:
	get_node("%Swatch").color = participant.color
	get_node("%Name").text = participant.display_name
	get_node("%Seat").text = _describe_seat(participant, local_peer_id)


static func _describe_seat(p: Participant, local_peer_id: int) -> String:
	if p.kind == Participant.Kind.AI:
		return "AI"
	if p.is_local(local_peer_id):
		return "you"
	if p.peer_id == LobbyScreen._PENDING_PEER_ID:
		return "waiting…"
	return "peer %d" % p.peer_id
