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
## [b]This screen owns hero colour, for every slot (#616 D1/D4).[/b] Overturning
## #563's closing note, [member Participant.color] is run shape rather than a
## per-machine presentation choice: it crosses the wire in
## [method Participant.to_dict], and every peer draws every hero in the colour
## its slot chose. That makes the AI slots this screen's problem too — a roster
## that only coloured the humans would render four identical greys — so defaults
## come round-robin off [constant _PALETTE] across the WHOLE roster and the
## per-row picker overrides.
##
## Deliberately minimal: scenic screens and per-player names are #461.

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

## Every hero colour a slot may hold (#616 D5). One authored resource, not a
## const array here — see `ui/theme/player_palette.gd` for why gold and pure
## white are both absent from it.
const _PALETTE := preload("res://ui/theme/player_palette.tres")
## What a slot starts on when nobody has picked (#618 D5). The pick is what
## differs between a human and an AI slot; the MECHANISM is identical, and both
## defaults must themselves be pickable in their own slot kind — a default the
## picker won't list is a state the player cannot return to.
const _DEFAULT_PLAYER_CORE := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_AI_CORE := preload("res://entity/core/basic_enemy_core.tres")

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
## What the route that opened this lobby lets its slots choose (#615). Null is
## the pre-#615 lobby: no camp control on any row, and nothing blocks START.
var _policy: LobbyPolicy = null
var _seed_edit: LineEdit
var _start_button: Button
var _ai_count_row: AiCountRow
var _participants: Array[Participant] = []
var _rows_container: VBoxContainer
## Colours a player explicitly chose, by [member Participant.id] — survives the
## roster rebuild an AI-count change triggers. Absent id means "still on its
## palette default".
var _picked_colors: Dictionary = {}
## Core classes a player explicitly chose, by [member Participant.id]. Same
## rebuild-survival contract as [member _picked_colors].
var _picked_cores: Dictionary = {}
## Camps a player explicitly chose, by [member Participant.id]. Same
## rebuild-survival contract as [member _picked_colors].
var _picked_camps: Dictionary = {}


## Configures this lobby before it enters the tree (call right after
## [method LobbyScreen.new], before it enters the tree). [param mode] is
## the shape the menu route ASKED for, not the mode the run ends up with —
## [method _resolved_mode] derives that from the roster at START (#554 D3).
## Defaults to the single-player shape so an unconfigured instance still behaves
## as it always has.
## [param policy] is what this lobby's ROUTE lets its slots choose (#615 D2) —
## it hangs on the route rather than being looked up from [param mode] precisely
## because [param mode] is not authoritative. Null reproduces the pre-#615
## lobby exactly: no camp control anywhere, and START never refused.
func configure(
	mode: RunConfig.Mode, network: NetworkConfig = null, policy: LobbyPolicy = null
) -> void:
	_mode = mode
	_network = network
	_policy = policy


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	if _offers_ai_opponents():
		_ai_count_row = _AI_COUNT_ROW.instantiate()
		_ai_count_row.value_changed.connect(func(_v: float): _rebuild_participants())
		content.add_child(_ai_count_row)

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

	_start_button = add_option("Start Game")
	_start_button.pressed.connect(_on_start_button_pressed)
	_refresh_start_enabled()


## The policy's veto, applied at the one place it can be: a versus lobby whose
## humans all share a camp has no opposing side, and #554 D3's
## [method resolve_mode] would quietly hand back COOP_HOTSEAT rather than fail.
## The button is also disabled, so this guard is belt-and-braces for a caller
## that emits `pressed` directly (every test does).
func _on_start_button_pressed() -> void:
	if not can_start():
		return
	start_pressed.emit(build_run_config())


## Is START allowed on the current roster? Always true without a policy — see
## [method configure].
func can_start() -> bool:
	return start_blocked_reason().is_empty()


## Why START is refused right now, or `""`. Public so the panel layer can
## surface it later without re-deriving the rule (#615 descopes the message UI).
func start_blocked_reason() -> String:
	return "" if _policy == null else _policy.start_blocked_reason(_participants)


func _refresh_start_enabled() -> void:
	if _start_button != null:
		_start_button.disabled = not can_start()


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
	# Changing the AI count rebuilds the roster from scratch, so re-apply what
	# the player already chose — a slot's colour must not silently revert to its
	# palette default because a DIFFERENT slot was added.
	for p in _participants:
		if _picked_colors.has(p.id):
			p.color = _picked_colors[p.id]
		if _picked_cores.has(p.id):
			p.core_class = _picked_cores[p.id]
		if _picked_camps.has(p.id):
			p.camp = _picked_camps[p.id]
	_refresh_rows()


func _ai_opponent_count() -> int:
	if _ai_count_row == null:
		return _DEFAULT_AI_OPPONENTS if _offers_ai_opponents() else 0
	return int(_ai_count_row.value)


func _refresh_rows() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	for p in _participants:
		_add_participant_row(p)
	_refresh_start_enabled()


func _add_participant_row(participant: Participant) -> void:
	var row: ParticipantRow = _PARTICIPANT_ROW.instantiate()
	_rows_container.add_child(row)
	row.configure(participant, _local_peer_id())
	row.set_color_choices(_PALETTE, taken_colors(_participants, participant.id))
	row.set_core_choices(CoreClass.pickable_for(slot_bit_for(participant.kind)))
	# Only a policied lobby ever asks for a camp control — a null policy leaves
	# `%Camp` untouched and hidden, which is the pre-#615 row (#615 D3).
	if _policy != null:
		row.set_camp_choices(
				_policy.camp_choices(), _policy.may_pick_camp(participant.kind))
	row.color_picked.connect(_on_color_picked.bind(participant))
	row.core_class_picked.connect(_on_core_class_picked.bind(participant))
	row.camp_picked.connect(_on_camp_picked.bind(participant))


## A slot chose a colour. The lobby writes it, not the row — this screen owns
## the roster — and then rebuilds every row so the newly-taken colour greys out
## in its siblings' dropdowns and the freed one comes back (#616 acceptance 4).
func _on_color_picked(color: Color, participant: Participant) -> void:
	if color == participant.color:
		return
	participant.color = color
	_picked_colors[participant.id] = color
	_refresh_rows()


## A slot chose a core class. Unlike colour, classes are NOT unique across slots
## — two players may both play Ninja — so nothing else has to be refreshed; the
## row repaints its own sigil.
func _on_core_class_picked(core: CoreClass, participant: Participant) -> void:
	participant.core_class = core
	_picked_cores[participant.id] = core


## A slot chose a camp (#615). Camps are shared, not unique like colours, so
## nothing has to be greyed out elsewhere — but the whole roster is refreshed
## anyway, because the policy's START veto is a fact about the roster and the
## button has to follow it.
##
## [b]This does not touch the mode[/b] (#615 D6): [method resolve_mode] still
## derives it from the roster at START, counting humans only.
func _on_camp_picked(camp: Faction, participant: Participant) -> void:
	if camp == participant.camp:
		return
	participant.camp = camp
	_picked_camps[participant.id] = camp
	_refresh_rows()


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
	var next_id := result.size() + 1
	for i in maxi(0, ai_opponents):
		result.append(_make_participant(
				next_id + i, "AI %d" % (i + 1), _NPC_FACTION, Participant.Kind.AI))
	assign_default_colors(result, _PALETTE)
	assign_default_cores(result)
	return result


## Which [member CoreClass.pickable_in] bit a slot of this kind carries. Lives
## here rather than on [CoreClass] because [CoreClass] deliberately does not
## know [Participant] exists — see the note on `pickable_in`.
static func slot_bit_for(kind: Participant.Kind) -> int:
	return CoreClass.PICKABLE_AI if kind == Participant.Kind.AI else CoreClass.PICKABLE_PLAYER


## Seat every slot on its default class (#618 D5). Every slot gets one, AI
## included — "the enemies would receive default enemy core by default but
## should also be pickable" (owner, 2026-08-26).
static func assign_default_cores(participants_in: Array[Participant]) -> void:
	for p in participants_in:
		if p.core_class == null:
			p.core_class = _DEFAULT_AI_CORE if p.kind == Participant.Kind.AI else _DEFAULT_PLAYER_CORE


## Hand every slot a distinct colour off [param palette], in roster order
## (#616 D4/D6). Humans and AI alike: the AI slots used to share
## `_NPC_FACTION.color`, which rendered four opponents as four identical greys
## the moment #563 made the spawn site read the roster.
##
## Round-robin, so a roster longer than the palette repeats rather than crashing
## — but the max roster is 6 (2 humans + [constant _MAX_AI_OPPONENTS]) against
## twenty colours, so in practice the wrap is unreachable and every slot differs.
static func assign_default_colors(
	participants_in: Array[Participant], palette: PlayerPalette
) -> void:
	if palette == null:
		return
	for i in participants_in.size():
		participants_in[i].color = palette.default_for(i)


## The colours other slots are already holding — what a row must grey out so no
## two heroes share one (#616 D6). [param except_id] is the asking slot, which
## must still be offered the colour it holds or it could never re-select it.
static func taken_colors(
	participants_in: Array[Participant], except_id: int
) -> Array[Color]:
	var out: Array[Color] = []
	for p in participants_in:
		if p.id != except_id and not out.has(p.color):
			out.append(p.color)
	return out


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
