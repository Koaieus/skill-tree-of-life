class_name LobbyChannel
extends LinkChannel
## The lobby's protocol: the host's whole roster down, one seat's pick up, and
## the run setup START sends — the one stateless protocol, needing no graph and
## no applier. Mounted by `network/lobby_link.tscn`.

const KEY_ROSTER := "roster"
const KEY_PICK := "pick"
const KEY_CONFIG := "config"

## Host → client: the whole authoritative lobby roster. Carries no [RunConfig],
## so nothing about it can open a run — a lobby's seed is still the `0`
## sentinel, and [method GameSession.apply_received] asserts it is resolved.
## Whole-roster rather than a delta: a handful of rows, and a delta would buy an
## ordering problem a lobby does not have.
const KIND_LOBBY := "lobby"
## Client → host: "I picked X for my seat" — an INTENT, and the host's
## [constant KIND_LOBBY] answer is its confirmation.
const KIND_LOBBY_PICK := "lobby_pick"
## Host → client at START: the resolved config + roster, which OPENS the run on
## the joiner ([method GameSession.apply_received]). Same wire kind the level's
## link carries for a joiner that arrives mid-run.
const KIND_SETUP := "setup"

## The host's answer REPLACES what this peer shows — no merge, no prediction,
## which is what makes a refused pick converge rather than linger.
signal lobby_roster_received(roster: ParticipantRoster)
signal lobby_pick_received(pick: Dictionary)


func kinds() -> Array[String]:
	return [KIND_LOBBY, KIND_LOBBY_PICK, KIND_SETUP]


func send_lobby_roster(roster: ParticipantRoster) -> void:
	if roster == null:
		return
	if link.send({NetworkLink.KEY_KIND: KIND_LOBBY, KEY_ROSTER: roster.to_dict()},
			NetworkConfig.Role.HOST):
		link.logged.emit("→ lobby roster (%d participants)" % roster.all().size())


## [param pick] is built by [method LobbyRoster.encode_pick] and crosses verbatim.
func send_lobby_pick(pick: Dictionary) -> void:
	if pick.is_empty():
		return
	if link.send({NetworkLink.KEY_KIND: KIND_LOBBY_PICK, KEY_PICK: pick},
			NetworkConfig.Role.CLIENT):
		link.logged.emit("↑ lobby pick for seat %d" % int(pick.get("id", 0)))


func send_run_setup(config: RunConfig, roster: ParticipantRoster) -> void:
	if config == null:
		return
	if link.send({
		NetworkLink.KEY_KIND: KIND_SETUP,
		KEY_CONFIG: config.to_dict(),
		KEY_ROSTER: (roster.to_dict() if roster != null else {"participants": []}),
	}, NetworkConfig.Role.HOST):
		link.logged.emit("→ run setup (seed %d, %d participants)" %
				[config.seed, roster.all().size() if roster != null else 0])


func receive(kind: String, payload: Dictionary) -> void:
	match kind:
		KIND_LOBBY:
			_on_lobby_roster(payload)
		KIND_LOBBY_PICK:
			_on_lobby_pick(payload)
		KIND_SETUP:
			_on_run_setup(payload)


func _on_lobby_roster(payload: Dictionary) -> void:
	if link.role != NetworkConfig.Role.CLIENT:
		return
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	lobby_roster_received.emit(roster)
	link.logged.emit("← lobby roster (%d participants)" % roster.all().size())


func _on_lobby_pick(payload: Dictionary) -> void:
	if link.role != NetworkConfig.Role.HOST:
		return
	var pick: Dictionary = payload.get(KEY_PICK, {})
	if pick.is_empty():
		link.logged.emit("↑ empty lobby pick, dropped")
		return
	lobby_pick_received.emit(pick)
	link.logged.emit("↑ lobby pick for seat %d" % int(pick.get("id", 0)))


func _on_run_setup(payload: Dictionary) -> void:
	var config := RunConfig.from_dict(payload.get(KEY_CONFIG, {}))
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	GameSession.apply_received(config, roster)
	link.logged.emit("← run setup (seed %d, %d participants)" % [config.seed, roster.all().size()])
