class_name LobbyScreen
extends VBoxContainer

## Lobby: one row per participant, a host-side "AI opponents" count, a seed
## field and a Start button. The seed field is live (#457): START hands this
## screen's [RunConfig] to `GameSession`, which resolves the seed once and feeds
## it to procgen — so typing back the seed the pause-menu footer shows replays
## the same map. Blank means "randomise me".
##
## [b]This screen authors the whole roster (#554).[/b] Since #553 the roster is
## the sole source of how many contenders a level spawns and how many starting
## points procgen is asked for, and the lobby is where that count is chosen — so
## the AI opponents are participants here, not something the level invents.
##
## Three shapes, decided by the [NetworkConfig] this screen was configured with
## rather than by a mode the player picked:
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
## its own answer with [method Participant.is_local]. A roster that named one
## row "the local one" would be wrong on the machine it crossed to.
##
## [b]Why the remote seat is declared before anybody joins.[/b] #554's decision 3
## derives [enum RunConfig.Mode] at START from the roster, and procgen reads the
## camp shape at level setup — both happen before a peer's socket is anywhere
## near this machine. A roster that only grew when the join actually landed would
## generate a map with no room for the joiner on it. So a networked lobby seats
## the second human immediately, at [constant _PENDING_PEER_ID], and the join
## stamps that placeholder with the real id (see
## [method stamp_pending_remote_peer]). "The roster grows on join" is true of the
## peer id, not of the seat.
##
## Deliberately minimal: scenic screens, per-player names and colour picking are
## #461.

signal start_pressed(run_config: RunConfig)

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
## Every AI opponent shares one camp, matching the fallback roster
## `scenes/procgen_play_sandbox.gd` builds when no lobby ran. N AI opponents are
## therefore one rival camp of N, not N mutually hostile camps — free-for-all AI
## is a run shape nobody has asked for yet.
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

## The [member Participant.peer_id] a not-yet-arrived remote human carries.
## Negative so it can never collide with a real Godot peer id (1 and up) nor
## with the `0` that means "local" — [method SeatPolicy.from_roster] therefore
## reads it as somebody else's seat from the moment the lobby is built, which is
## the correct answer even before the join lands.
const _PENDING_PEER_ID := -1

## What the host's own participant answers to. A host is always peer 1 under
## Godot's high-level multiplayer.
const _HOST_PEER_ID := NetworkTransport.HOST_PEER_ID

## Placeholder player colors — row 1 matches procgen's enemy_colors[0] red
## (procgen_play_sandbox.gd), since there's no per-player color picker yet.
const _PLACEHOLDER_COLORS := [
	Color(0.95, 0.4, 0.4, 1.0),
	Color(0.4, 0.8, 1.0, 1.0),
]
# TODO(#616): ~20-colour player palette + per-slot colour picker; the roster
#             becomes authoritative for hero colour (blocked on #563).
# TODO(#617): faction emblems from `addons/at-icons`, shown on each row.
# TODO(#618): per-slot CoreClass pick (the sigil rides along), with a
#             player/AI pickability mask on CoreClass itself.
# TODO(#615): LobbyPolicy on the Route decides which slots may pick a camp.

## AI opponents a fresh lobby offers. One rival camp is what a menu-launched run
## produced before this screen authored any AI at all (the level's fallback
## roster is `camp_sizes = [1, 1]`), so this is that behaviour, made visible.
const _DEFAULT_AI_OPPONENTS := 1
const _MAX_AI_OPPONENTS := 4

## The rows this screen stacks, kept under the name the shipped code and its
## tests already use. It is this node: the screen IS its own column now that
## [FrontmatterPanel] supplies the frame, the title and the back button around
## it (#579). Before the cutover this was a child [VBoxContainer] built by
## the deleted `MenuScreen._ready`, which also drew a background and a title bar
## — chrome that would be drawn twice inside a panel.
var content: VBoxContainer:
	get:
		return self

const _PARTICIPANT_ROW := preload("res://ui/frontmatter/panels/participant_row.tscn")
const _AI_COUNT_ROW := preload("res://ui/frontmatter/panels/ai_count_row.tscn")

## Adds a Button to [member content]. Caller connects `.pressed` itself.
##
## Duplicated in [HostJoinScreen] rather than shared through a common base: the
## base that used to own it was `MenuScreen`, and #579 deletes it. Seven lines
## of widget construction in two files beats a new base class whose whole reason
## to exist is those seven lines.
func add_option(text: String, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	content.add_child(button)
	return button

var _mode: RunConfig.Mode = RunConfig.Mode.SINGLE
var _network: NetworkConfig = null
var _seed_edit: LineEdit
var _ai_count_spin: AiCountRow  # Renamed from SpinBox to AiCountRow, but keeping the name for backward compat
var _participants: Array[Participant] = []
var _rows_container: VBoxContainer


## Configures this lobby before it enters the tree (call right after
## [method LobbyScreen.new], before it enters the tree). [param mode] is
## the shape the menu route ASKED for, not the mode the run ends up with —
## [method _resolved_mode] derives that from the roster at START (#554 D3).
## Defaults to the single-player shape so an unconfigured instance still behaves
## as it always has.
func configure(mode: RunConfig.Mode, network: NetworkConfig = null) -> void:
	_mode = mode
	_network = network


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	if _offers_ai_opponents():
		_ai_count_spin = _AI_COUNT_ROW.instantiate()
		_ai_count_spin.value_changed.connect(func(_v: float): _rebuild_participants())
		content.add_child(_ai_count_spin)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	content.add_child(_rows_container)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	content.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_row.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "random"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)

	if _network != null and _network.is_online():
		var link_label := Label.new()
		link_label.text = _network.describe()
		content.add_child(link_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	_rebuild_participants()

	add_option("Start Game").pressed.connect(func(): start_pressed.emit(build_run_config()))


## The roster this lobby currently shows. Live, not a copy — the join path
## stamps a participant in place (see [method stamp_pending_remote_peer]).
func participants() -> Array[Participant]:
	return _participants


## Give the pending remote seat the peer id the transport just reported, and
## return true if there was one to stamp. This is the "roster grows on join"
## half of #554 D2 that a lobby can honour: the seat was authored up front so
## procgen could see it, and only the identity was outstanding.
func stamp_pending_remote_peer(peer_id: int) -> bool:
	for p in _participants:
		if is_pending_remote(p):
			p.peer_id = peer_id
			_refresh_rows()
			return true
	return false


## True when this participant is a remote seat nobody has arrived on yet — the
## one question a caller outside this file might reasonably ask about the
## sentinel, answered without exporting the number.
static func is_pending_remote(p: Participant) -> bool:
	return p != null and p.kind == Participant.Kind.HUMAN and p.peer_id == _PENDING_PEER_ID


## The join half of #554 D2, as a seam the level can call without knowing what
## a pending seat looks like: give the roster's waiting human seat the id the
## transport just reported. Returns false when there was nothing waiting — a
## second peer on a two-seat lobby, or a roster that never expected one.
##
## Static and roster-shaped (not screen-shaped) because the machine that needs
## it is the HOST AT LEVEL TIME: the lobby is gone by the time a socket lands,
## and the live roster is [member GameSession.roster]. The sentinel stays
## private to this file so no other site has to agree with it.
static func stamp_pending_remote(roster: ParticipantRoster, peer_id: int) -> bool:
	if roster == null:
		return false
	for p in roster.all():
		if is_pending_remote(p):
			p.peer_id = peer_id
			roster.notify_changed(p.id)
			return true
	return false


func _offers_ai_opponents() -> bool:
	# Hot-seat coop and versus alike want the control; a host offers it because
	# it is the host's roster everybody plays. A joining client's own roster is
	# replaced wholesale by the host's [method GameSession.apply_received], so
	# a count it chose here would be a lie on screen.
	return _network == null or _network.role != NetworkTransport.Role.CLIENT




func _rebuild_participants() -> void:
	_participants = build_participants(_mode, _network, _ai_opponent_count())
	_refresh_rows()


func _ai_opponent_count() -> int:
	if _ai_count_spin == null:
		return _DEFAULT_AI_OPPONENTS if _offers_ai_opponents() else 0
	return int(_ai_count_spin.value)


func _refresh_rows() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	for p in _participants:
		_add_participant_row(p)


func _add_participant_row(participant: Participant) -> void:
	var row: ParticipantRow = _PARTICIPANT_ROW.instantiate()
	row.configure(participant, _local_peer_id())
	_rows_container.add_child(row)


## This machine's own id, as far as a lobby can know it: a client's real id is
## minted by the server on connect, so the placeholder it authored for itself is
## what its own rows carry until then.
func _local_peer_id() -> int:
	if _network == null or not _network.is_online():
		return 0
	return _HOST_PEER_ID if _network.role == NetworkTransport.Role.HOST else _PENDING_PEER_ID




## The roster a lobby of this shape authors. Static and pure so the seat/mode
## wiring is testable without instancing a menu (`test_lobby_roster.gd`).
static func build_participants(
	mode: RunConfig.Mode, network: NetworkConfig, ai_opponents: int
) -> Array[Participant]:
	var result: Array[Participant] = []
	var online := network != null and network.is_online()
	if online:
		# The local human is peer 1 when hosting, and gets the host's id back
		# over the wire when joining — a client's own roster is discarded on
		# receipt, so what it puts here only has to be a coherent placeholder.
		var local_peer := _HOST_PEER_ID if network.role == NetworkTransport.Role.HOST else _PENDING_PEER_ID
		result.append(_make_participant(1, "Player 1", _CAMP_1, Participant.Kind.HUMAN, local_peer))
		var remote_peer := _PENDING_PEER_ID if network.role == NetworkTransport.Role.HOST else _HOST_PEER_ID
		result.append(_make_participant(2, "Player 2", _CAMP_2, Participant.Kind.HUMAN, remote_peer))
	elif mode == RunConfig.Mode.COOP_HOTSEAT:
		result.append(_make_participant(1, "Player 1", _CAMP_1))
		result.append(_make_participant(2, "Player 2", _CAMP_1))
	else:
		result.append(_make_participant(1, "Player 1", _PLAYER_FACTION))
	for i in result.size():
		result[i].color = _PLACEHOLDER_COLORS[i % _PLACEHOLDER_COLORS.size()]
	var next_id := result.size() + 1
	for i in maxi(0, ai_opponents):
		var ai := _make_participant(next_id + i, "AI %d" % (i + 1), _NPC_FACTION, Participant.Kind.AI)
		ai.color = _NPC_FACTION.color
		result.append(ai)
	return result


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


## #554 D3: the mode is DERIVED, at START, from the roster this lobby ended up
## with — never from the button that opened it. VERSUS when the humans span more
## than one camp, COOP_HOTSEAT when they share one, and SINGLE when there is
## only one of them.
##
## [b]Presentation only.[/b] `docs/domain/seat-policy.md` §"One axis" is explicit
## that [enum RunConfig.Mode] exists "for menu presentation and defaults" and
## that deriving seating from it would be a second source of truth against the
## roster. Nothing here feeds [SeatPolicy]; that reads the roster directly.
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


func build_run_config() -> RunConfig:
	var cfg := RunConfig.new()
	cfg.mode = resolve_mode(_participants)
	cfg.seed = _parse_seed(_seed_edit.text if _seed_edit != null else "")
	cfg.participants = _participants
	return cfg


## Non-numeric/empty text means seed = 0 — [RunConfig]'s documented legal
## authoring value for "randomise me".
static func _parse_seed(text: String) -> int:
	if text.is_empty() or not text.is_valid_int():
		return 0
	return text.to_int()
