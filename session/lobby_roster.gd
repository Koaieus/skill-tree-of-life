class_name LobbyRoster
extends RefCounted

## The lobby's DOMAIN half (#1002): who is in the run, what each seat picked,
## and whether START is allowed. [LobbyScreen] holds one, renders rows from it,
## forwards every edit here and calls [method to_run_config] at START — the
## screen is a view, this is the run's shape before it becomes a [RunConfig].
##
## [b]Three shapes, decided by the [NetworkConfig] rather than by a mode the
## player picked[/b] (#554):
##
## [codeblock]
##   offline, SINGLE      1 human at peer 0 on `player.tres`    -> SINGLE
##   offline, hot-seat    2 humans at peer 0 sharing `camp_1`    -> COOP_HOTSEAT
##   host / join          1 human on camp_1 at THIS peer +
##                        1 human on camp_2 at the other one     -> VERSUS
## [/codeblock]
##
## [b]Which of those humans is "me" is never written down (#562)[/b] — the two
## seats differ only by [member Participant.peer_id], and each machine derives
## its own answer with [method Participant.is_local].
##
## [b]Why the remote seat is declared before anybody joins.[/b] The mode is
## derived at START from the roster and procgen reads the camp shape at level
## setup — both before a peer's socket is anywhere near this machine. So a
## networked roster seats the second human immediately, at
## [constant PENDING_PEER_ID], and the join stamps that placeholder with the
## real id ([method clear_remote]). "The roster grows on join" is true of the
## peer id, not of the seat.
##
## [b]Pick memory.[/b] Changing the AI count rebuilds the participant list from
## scratch ([method build_participants] is pure), so what a player explicitly
## chose lives beside the list as one [LobbyRoster.Pick] per seat id and is
## re-applied after every rebuild — a slot's colour must not silently revert to
## its palette default because a DIFFERENT slot was added. A field's zero value
## is "still on the default": white for colour (the palette never offers it),
## null for core and camp, "" for the name.
##
## [b]Colour is run shape, for every slot (#616).[/b] It crosses the wire in
## [method Participant.to_dict], so the AI slots are this roster's problem
## too: defaults come round-robin off the palette across the WHOLE roster.
##
## [b]The run section is NOT here.[/b] Map size, blockers, arrangement, victory
## and budget are ladders the route's [LobbyPolicy] unlocks and the screen
## composes into [ScenarioOverride]s — [method to_run_config] takes the settled
## scenario + overrides as arguments rather than owning the ladders, so this
## file never has to know what an [OptionChoiceRow] is.
##
## Emits [signal changed] after every mutation that altered a seat or the
## START gate; the screen's one handler repaints from it.

signal changed

const PENDING_PEER_ID := -1
const HOST_PEER_ID := NetworkTransport.HOST_PEER_ID
## The name field's cap, enforced locally by the row's `max_length` and
## remotely by [method normalize_name] — one number, both ends.
const MAX_NAME_LENGTH := 24
## What a fresh offline / hosting roster seats. `MAX` is the slider's ceiling;
## `test_center_core_starters.gd` pins that procgen can place that many.
const DEFAULT_AI_OPPONENTS := 5
const MAX_AI_OPPONENTS := 12
## Keys inside a [constant CommandLink.KIND_LOBBY_PICK] payload that are not
## themselves [Participant] fields: WHICH seat, and WHO is asking. The changed
## fields beside them use [method Participant.to_dict]'s own names.
const PICK_ID := "id"
const PICK_PEER := "peer_id"

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _PALETTE := preload("res://ui/theme/player_palette.tres")
const _DEFAULT_PLAYER_CORE := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_AI_CORE := preload("res://entity/core/balanced_core.tres")


## What one seat explicitly chose, keyed by [member Participant.id] in
## [member _picks]. Survives the rebuild an AI-count change triggers; a zero
## value means "still on the default" for that field.
class Pick:
	extends RefCounted
	var color: Color = Color.WHITE
	var core: CoreClass = null
	var camp: Faction = null
	var display_name: String = ""


## The shape the route ASKED for, not the mode the run ends up with —
## [method resolve_mode] derives that from the roster at START (#554 D3).
var mode: RunConfig.Mode = RunConfig.Mode.SINGLE
var network: NetworkConfig = null
## What this roster's ROUTE lets its slots choose (#615 D2). Null is the
## pre-#615 lobby: nothing blocks START.
var policy: LobbyPolicy = null
var participants: Array[Participant] = []
## The AI core preset (#841). `null` is "no preset armed"; AI slots only.
var core_preset: CoreClass = null
## This machine's real id on the link, or 0 before the server has minted one
## (a client authors its own seat at [constant PENDING_PEER_ID] and learns
## the truth on join — see [method local_peer_id]).
var local_peer: int = 0

var _ai_opponents: int = 0
var _picks: Dictionary = {}
## #736: peers connected at the TRANSPORT level but not yet through
## [CommandLink]'s build gate. A pending SEAT and a connecting SOCKET are two
## different things, and START must wait for the second. Every entry has a
## removal path — [method clear_remote] or [method remove_remote].
var _connecting_peers: Dictionary = {}


func _init(
	mode_in: RunConfig.Mode = RunConfig.Mode.SINGLE,
	network_in: NetworkConfig = null,
	policy_in: LobbyPolicy = null
) -> void:
	mode = mode_in
	network = network_in
	policy = policy_in
	_ai_opponents = DEFAULT_AI_OPPONENTS if offers_ai_opponents() else 0
	_rebuild()


# --- shape queries -------------------------------------------------------------

func is_online() -> bool:
	return network != null and network.is_online()


func is_client() -> bool:
	return network != null and network.role == NetworkTransport.Role.CLIENT


## Hot-seat coop and versus alike want the AI count; a host offers it because
## it is the host's roster everybody plays. A joining client's own roster is
## replaced wholesale by [method adopt], so a count it chose would be a lie.
func offers_ai_opponents() -> bool:
	return not is_client()


func ai_opponent_count() -> int:
	return _ai_opponents


func local_peer_id() -> int:
	if not is_online():
		return 0
	if local_peer != 0:
		return local_peer
	return HOST_PEER_ID if network.role == NetworkTransport.Role.HOST else PENDING_PEER_ID


func by_id(id: int) -> Participant:
	for p in participants:
		if p.id == id:
			return p
	return null


func by_peer_id(peer_id: int) -> Participant:
	for p in participants:
		if p.peer_id == peer_id:
			return p
	return null


## The one locality rule, for THIS machine: offline and hot-seat may edit any
## seat, a host or a client its own seat only, and an AI seat belongs to
## whoever authors the roster.
func may_edit_locally(p: Participant) -> bool:
	return may_edit(p, local_peer_id(), offers_ai_opponents())


## An AI seat holding an explicit core pick (#841) — provenance, never a
## value comparison against the preset.
func is_core_overridden(p: Participant) -> bool:
	return p != null and p.kind == Participant.Kind.AI and _pick_of(p.id).core != null


func has_pending_remote() -> bool:
	for p in participants:
		if is_pending_remote(p):
			return true
	return false


# --- START ---------------------------------------------------------------------

func can_start() -> bool:
	return start_blocked_reason().is_empty()


## Why START is refused right now, or `""`. The transient #736 gate is checked
## first, ahead of the policy: a peer mid-handshake is a fact about the WIRE,
## while the policy only speaks to the roster it can see.
func start_blocked_reason() -> String:
	if not _connecting_peers.is_empty():
		return "Waiting for %d peer(s) to finish joining…" % _connecting_peers.size()
	return "" if policy == null else policy.start_blocked_reason(participants)


func to_run_config(
	seed: int = 0, scenario: Scenario = null, overrides: Array[ScenarioOverride] = []
) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.mode = resolve_mode(participants)
	cfg.seed = seed
	cfg.participants = participants
	cfg.scenario = scenario
	cfg.overrides = overrides
	return cfg


func to_participant_roster() -> ParticipantRoster:
	return ParticipantRoster.of(participants)


# --- local edits ---------------------------------------------------------------

func set_ai_opponents(count: int) -> void:
	count = maxi(0, count)
	if count == _ai_opponents and not participants.is_empty():
		return
	_ai_opponents = count
	_rebuild()
	changed.emit()


func set_core_preset(core: CoreClass) -> void:
	core_preset = core
	_resolve_cores()
	changed.emit()


func set_local_peer(peer_id: int) -> void:
	local_peer = peer_id
	changed.emit()


## True when the roster changed. Refused (no write, no signal) when the colour
## is already this seat's or another seat holds it — two slots never share.
func pick_color(p: Participant, color: Color) -> bool:
	if p == null or color == p.color or taken_colors(participants, p.id).has(color):
		return false
	p.color = color
	_pick_of(p.id).color = color
	changed.emit()
	return true


func pick_core(p: Participant, core: CoreClass) -> bool:
	if p == null or core == null:
		return false
	p.core_class = core
	_pick_of(p.id).core = core
	changed.emit()
	return true


func reset_core(p: Participant) -> bool:
	if p == null or _pick_of(p.id).core == null:
		return false
	_pick_of(p.id).core = null
	_resolve_cores()
	changed.emit()
	return true


func pick_camp(p: Participant, camp: Faction) -> bool:
	if p == null or camp == p.camp:
		return false
	p.camp = camp
	_pick_of(p.id).camp = camp
	changed.emit()
	return true


func pick_name(p: Participant, name: String) -> bool:
	if p == null:
		return false
	var wanted := normalize_name(name)
	if wanted.is_empty() or wanted == p.display_name:
		return false
	p.display_name = wanted
	_pick_of(p.id).display_name = wanted
	changed.emit()
	return true


# --- the wire's mutations (#714 / #716 / #736) ---------------------------------

## A peer connected at the transport level; START waits until it clears the
## build gate or drops. Host-side only — a client gates nothing.
func add_remote(peer_id: int) -> void:
	_connecting_peers[peer_id] = true
	changed.emit()


## The peer cleared the build gate: the wait is over, and the pending seat (if
## one is still free) is stamped with its id and the name it offered. Returns
## whether a seat was stamped.
func clear_remote(peer_id: int, join_prefs: Dictionary = {}) -> bool:
	_connecting_peers.erase(peer_id)
	var seated := false
	for p in participants:
		if is_pending_remote(p):
			p.peer_id = peer_id
			seated = true
			var offered := String(join_prefs.get("display_name", ""))
			if not offered.is_empty():
				var wanted := normalize_name(offered)
				if not wanted.is_empty():
					p.display_name = wanted
					_pick_of(p.id).display_name = wanted
			break
	changed.emit()
	return seated


## The peer left (or never finished joining): its seat goes back to waiting.
## Returns whether a seat was freed.
func remove_remote(peer_id: int) -> bool:
	if peer_id == PENDING_PEER_ID:
		return false
	var was_connecting := _connecting_peers.erase(peer_id)
	var freed := false
	for p in participants:
		if p.kind == Participant.Kind.HUMAN and p.peer_id == peer_id:
			p.peer_id = PENDING_PEER_ID
			freed = true
	if freed or was_connecting:
		changed.emit()
	return freed


## A client's own roster is a placeholder; the host's broadcast replaces it.
func adopt(roster: ParticipantRoster) -> void:
	if roster == null:
		return
	participants = roster.all()
	changed.emit()


## A peer's pick, put through the same writers a local pick goes through, on
## its own seat only. Returns whether anything changed — the host answers with
## its whole roster either way, so a refusal is simply the absence of a change.
func apply_remote_pick(pick: Dictionary) -> bool:
	var target := by_id(int(pick.get(PICK_ID, 0)))
	if not may_edit_remotely(target, int(pick.get(PICK_PEER, 0))):
		return false
	var any := false
	if pick.has("display_name"):
		any = pick_name(target, String(pick["display_name"])) or any
	if pick.has("color"):
		any = pick_color(target, pick["color"]) or any
	if pick.has("core_class"):
		any = pick_core(target, _loaded(pick["core_class"]) as CoreClass) or any
	if pick.has("camp"):
		any = pick_camp(target, _loaded(pick["camp"]) as Faction) or any
	return any


# --- internals -----------------------------------------------------------------

func _pick_of(id: int) -> Pick:
	if not _picks.has(id):
		_picks[id] = Pick.new()
	return _picks[id]


func _picked_cores() -> Dictionary:
	var out := {}
	for id in _picks:
		if _picks[id].core != null:
			out[id] = _picks[id].core
	return out


func _resolve_cores() -> void:
	apply_core_preset(participants, _picked_cores(), core_preset)


## Rebuild the list from scratch and re-apply every remembered pick. A rebuild
## must not UN-SEAT a peer that already joined: [method build_participants] is
## born with every remote seat back on [constant PENDING_PEER_ID], so the
## stamped ids are carried across by seat id. [member _connecting_peers] is
## keyed by peer, not seat, and survives untouched.
func _rebuild() -> void:
	var seated_peers: Dictionary = {}
	for p in participants:
		if p != null and p.kind == Participant.Kind.HUMAN and p.peer_id != PENDING_PEER_ID:
			seated_peers[p.id] = p.peer_id
	participants = build_participants(mode, network, _ai_opponents)
	for p in participants:
		if _picks.has(p.id):
			var pick: Pick = _picks[p.id]
			if pick.color != Color.WHITE:
				p.color = pick.color
			if pick.camp != null:
				p.camp = pick.camp
			if not pick.display_name.is_empty():
				p.display_name = pick.display_name
		if p.kind == Participant.Kind.HUMAN and seated_peers.has(p.id):
			p.peer_id = seated_peers[p.id]
	# Cores are resolved together, not folded into the loop above: the preset's
	# fallback-to-kind-default path has to see the WHOLE roster.
	_resolve_cores()


# --- the pure rules ------------------------------------------------------------

## The roster a mode + network shape authors, before any pick. Pure: the same
## inputs always give the same seats, colours and default cores.
static func build_participants(
	mode_in: RunConfig.Mode, network_in: NetworkConfig, ai_opponents: int
) -> Array[Participant]:
	var result: Array[Participant] = []
	var online := network_in != null and network_in.is_online()
	if online:
		# The local human is peer 1 when hosting, and gets the host's id back
		# over the wire when joining — a client's own roster is discarded on
		# receipt, so what it puts here only has to be a coherent placeholder.
		var hosting := network_in.role == NetworkTransport.Role.HOST
		var local := HOST_PEER_ID if hosting else PENDING_PEER_ID
		# Seeded only when HOSTING — a client's placeholder would flash the saved
		# name and then revert to "Player 2" when the host's broadcast lands.
		var seat1_name := _default_name("Player 1") if hosting else "Player 1"
		result.append(_make_participant(1, seat1_name, _CAMP_1, Participant.Kind.HUMAN, local))
		var remote := PENDING_PEER_ID if hosting else HOST_PEER_ID
		result.append(_make_participant(2, "Player 2", _CAMP_2, Participant.Kind.HUMAN, remote))
	elif mode_in == RunConfig.Mode.COOP_HOTSEAT:
		result.append(_make_participant(1, _default_name("Player 1"), _CAMP_1))
		result.append(_make_participant(2, "Player 2", _CAMP_1))
	else:
		result.append(_make_participant(1, _default_name("Player 1"), _PLAYER_FACTION))
	var next_id := result.size() + 1
	for i in maxi(0, ai_opponents):
		result.append(_make_participant(
				next_id + i, "AI %d" % (i + 1), _NPC_FACTION, Participant.Kind.AI))
	assign_default_colors(result, _PALETTE)
	assign_default_cores(result)
	return result


static func slot_bit_for(kind: Participant.Kind) -> int:
	return CoreClass.PICKABLE_AI if kind == Participant.Kind.AI else CoreClass.PICKABLE_PLAYER


static func assign_default_cores(participants_in: Array[Participant]) -> void:
	for p in participants_in:
		if p.core_class == null:
			p.core_class = _DEFAULT_AI_CORE if p.kind == Participant.Kind.AI else _DEFAULT_PLAYER_CORE


## #841's resolution rule: an explicit pick wins, else an armed preset templates
## every AI seat, else the kind default. `null` preset behaves exactly as
## [method assign_default_cores].
static func apply_core_preset(
	participants_in: Array[Participant], picked_cores: Dictionary, preset: CoreClass
) -> void:
	for p in participants_in:
		if picked_cores.has(p.id):
			p.core_class = picked_cores[p.id]
		elif preset != null and p.kind == Participant.Kind.AI:
			p.core_class = preset
		else:
			p.core_class = null
	assign_default_cores(participants_in)


static func assign_default_colors(
	participants_in: Array[Participant], palette: PlayerPalette
) -> void:
	if palette == null:
		return
	for i in participants_in.size():
		participants_in[i].color = palette.default_for(i)


static func taken_colors(
	participants_in: Array[Participant], except_id: int
) -> Array[Color]:
	var out: Array[Color] = []
	for p in participants_in:
		if p.id != except_id and not out.has(p.color):
			out.append(p.color)
	return out


## More than one non-AI camp is VERSUS, more than one human on one camp is
## hot-seat, else SINGLE — the sole mode authority (#554 D3).
static func resolve_mode(participants_in: Array[Participant]) -> RunConfig.Mode:
	var human_camps: Array[Faction] = []
	var humans := 0
	for p in participants_in:
		if p.kind == Participant.Kind.AI:
			continue
		humans += 1
		if p.camp != null and not human_camps.has(p.camp):
			human_camps.append(p.camp)
	if human_camps.size() > 1:
		return RunConfig.Mode.VERSUS
	if humans > 1:
		return RunConfig.Mode.COOP_HOTSEAT
	return RunConfig.Mode.SINGLE


## A remote seat nobody has arrived on yet.
static func is_pending_remote(p: Participant) -> bool:
	return p != null and p.kind == Participant.Kind.HUMAN and p.peer_id == PENDING_PEER_ID


## The join half of #554 D2 for the HOST AT LEVEL TIME: the lobby is gone by
## the time a socket lands, and the live roster is [member GameSession.roster].
static func stamp_pending_remote(roster: ParticipantRoster, peer_id: int) -> bool:
	if roster == null:
		return false
	for p in roster.all():
		if is_pending_remote(p):
			p.peer_id = peer_id
			roster.notify_changed(p.id)
			return true
	return false


static func may_edit(p: Participant, local_peer_id_in: int, authors_ai: bool) -> bool:
	if p == null:
		return false
	if p.kind == Participant.Kind.AI:
		return authors_ai
	return p.is_local(local_peer_id_in)


## A peer may edit its own human seat and nothing else; peer 0 is nobody.
static func may_edit_remotely(p: Participant, from_peer: int) -> bool:
	if p == null or from_peer == 0 or p.kind == Participant.Kind.AI:
		return false
	return p.peer_id == from_peer


static func normalize_name(text: String) -> String:
	return text.strip_edges().left(MAX_NAME_LENGTH)


## A [constant CommandLink.KIND_LOBBY_PICK] payload: resources cross by path.
static func encode_pick(
	participant: Participant, from_peer: int, changes: Dictionary
) -> Dictionary:
	var pick := {PICK_ID: participant.id, PICK_PEER: from_peer}
	for key in changes:
		var value: Variant = changes[key]
		pick[key] = value.resource_path if value is Resource else value
	return pick


## Blank or non-numeric means "randomise me" (#457).
static func parse_seed(text: String) -> int:
	if text.is_empty() or not text.is_valid_int():
		return 0
	return text.to_int()


static func _loaded(path: Variant) -> Resource:
	var as_path := String(path)
	return null if as_path.is_empty() else load(as_path)


static func _default_name(fallback: String) -> String:
	var saved := Settings.current.player_name
	return saved if not saved.is_empty() else fallback


static func _make_participant(
	id: int,
	display_name: String,
	camp: Faction,
	kind: Participant.Kind = Participant.Kind.HUMAN,
	peer_id: int = 0
) -> Participant:
	var p := Participant.new()
	p.id = id
	p.display_name = display_name
	p.kind = kind
	p.camp = camp
	p.peer_id = peer_id
	return p
