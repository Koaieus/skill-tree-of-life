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

## The HOST pressed START and this machine is the one that joined (#715). The
## sibling of [signal start_pressed] for the peer that does not decide: same
## destination, same [RunConfig], reached from the wire rather than a button —
## and deliberately its own signal, because the shell must NOT re-open the run
## ([method GameSession.apply_received] already did, and re-running
## [method GameSession.start] would re-resolve the seed and hand this peer a
## different map).
signal remote_start(run_config: RunConfig)

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
const _MAX_AI_OPPONENTS := 12

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
const _OPTION_CHOICE_ROW := preload("res://ui/frontmatter/panels/option_choice_row.tscn")
const _BUDGET_RANGE_ROW := preload("res://ui/frontmatter/panels/budget_range_row.tscn")
const _ROW_SCENE := preload("res://ui/common/labelled_row.tscn")

## Keys into [member _picked_options] (#643 decision 1 — these are per-RUN, so
## they are keyed by KNOB, not by [member Participant.id] the way
## [member _picked_colors] is). A knob ABSENT from that dictionary is the
## "host never touched this control" state, and #643 acceptance 5 is exactly
## the assertion that such a knob contributes no override at all.
const KNOB_MAP_SIZE := &"map_size"
const KNOB_BLOCKERS := &"blockers"
## Which shape the starters are laid out in (#558) — GROUPED / ALTERNATING /
## RANDOM. Per-RUN like the rest: one arrangement describes the whole board's
## seating, not one participant's.
const KNOB_ARRANGEMENT := &"arrangement"
const KNOB_BUDGET := &"budget"

## Adds a Button to [member content]. Caller connects `.pressed` itself.
##
## The last code-composed button in the panel layer: the other screen that had
## one of these (#531's host/join screen) is gone, and both its successors
## author their button in their own `.tscn`. This screen keeps it because it
## builds its whole column in code — see [LobbyPanel] for why that has to stay
## true until `configure`'s before-`_ready` contract is retired.
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

## --- #714: the roster replicates while the menu is up --------------------------
##
## The lobby's own [NetworkTransport] + [CommandLink] pair, mounted only when a
## socket is ALREADY open (see [method _mount_link]). It is the same seam the
## level mounts, at the one other scope that needs it — and it never opens the
## link itself, so a lobby built with no wire behind it is byte-for-byte the
## offline lobby that shipped before this.
var _transport: NetworkTransport = null
var _link: CommandLink = null
## This machine's real id on the link, or 0 before the server has minted one.
## A client authors its own seat at [constant _PENDING_PEER_ID] and only learns
## the truth on [signal NetworkTransport.peer_joined]; see [method _local_peer_id].
var _local_peer: int = 0

## --- #716: what the wire is doing, said out loud -------------------------------
##
## Two labels, because they answer two different questions and only one of them
## is ever empty. [member _link_label] is the standing caption ("Others join at
## …"); [member _status_label] is the incident line — a refusal, a lost link, a
## dial that never connected — and it stays blank while nothing has gone wrong.
var _link_label: Label = null
var _status_label: Label = null
## Latched when this machine's own link went away ([signal
## NetworkTransport.link_lost]). START is refused while it is set: the route out
## is the panel's [BackAffordance], not a button that would open a run nobody
## else is in.
var _link_lost: bool = false
## Set once this machine has been told WHY it was hung up on. A refusal is
## always followed by the disconnect that enforces it, and the generic
## "connection lost" would then paint over the only line that names the cause —
## so the refusal wins, and the loss only sets the Start veto.
var _refusal_shown: bool = false

## Keys inside a [constant CommandLink.KIND_LOBBY_PICK] payload that are not
## themselves [Participant] fields: WHICH seat, and WHO is asking. The changed
## fields beside them use [method Participant.to_dict]'s own names and encoding.
const PICK_ID := "id"
const PICK_PEER := "peer_id"

## The run-level section beside the seed field (#643). Named and reachable
## through [method add_run_row] because it is a SHARED surface: #558 appends a
## starter-arrangement control here and #638 a victory-condition one, in a later
## wave. Nothing about it is map-size-shaped.
var _run_section: VBoxContainer
var _map_size_row: OptionChoiceRow
var _blocker_row: OptionChoiceRow
var _arrangement_row: OptionChoiceRow
var _budget_row: BudgetRangeRow

## Run-level picks the host made explicitly, keyed by knob (see [constant
## KNOB_MAP_SIZE]). Values are a ladder INDEX for the pickers and a
## `[base_min, base_max]` pair for the budget row.
##
## [b]Same rebuild-survival contract as [member _picked_colors], for a different
## reason.[/b] Those survive because the roster rebuilds on every slot change;
## these survive because this dictionary — not the widget — is what
## [method build_run_config] reads. The widget is a view of the pick, so a
## control that is rebuilt, hidden or never realised cannot silently drop one.
var _picked_options: Dictionary = {}


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
	# Before the roster is built: a client's own peer id decides which row reads
	# "you" and which pickers it may touch, and a host must be listening for the
	# join that stamps its waiting seat before it can possibly arrive.
	_mount_link()

	if _offers_ai_opponents():
		_ai_count_row = _AI_COUNT_ROW.instantiate()
		_ai_count_row.value_changed.connect(func(_v: float): _rebuild_participants())
		content.add_child(_ai_count_row)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	content.add_child(_rows_container)

	# Pushes everything below the roster — seed, run section, Start — toward
	# the bottom of the panel instead of crowding it directly under the last
	# slot row.
	var roster_spacer := Control.new()
	roster_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(roster_spacer)

	var seed_row: LabelledRow = _ROW_SCENE.instantiate()
	seed_row.set_label("Seed:")
	content.add_child(seed_row)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "random, e.g. 20260901"
	_seed_edit.text_changed.connect(_on_seed_text_changed)
	seed_row.set_widget(_seed_edit)

	_build_run_section()

	if _network != null and _network.is_online():
		_link_label = Label.new()
		_link_label.text = _link_caption()
		content.add_child(_link_label)
		_status_label = Label.new()
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(_status_label)
		_report_mount_state()

	_rebuild_participants()

	_start_button = add_option("Start Game")
	_start_button.pressed.connect(_on_start_button_pressed)
	_refresh_start_enabled()


## What the lobby says about the wire.
##
## [b]A host reads out where it can be REACHED[/b] (#582 acceptance 3) — the
## address a joiner types into [JoinPanel], picked out of every address this
## machine answers to by [method NetworkConfig.pick_advertised_address]. It has
## to be said somewhere, because nothing discovers it: LAN broadcast was
## evaluated and dropped (#463), so "one room, one number" means a human reads
## the number to another human.
##
## [b]A client keeps [method NetworkConfig.describe][/b] — it already knows what
## it dialled, and telling it its own local address would be noise at best and
## the wrong number at worst (#582 D6).
func _link_caption() -> String:
	if _network.role != NetworkTransport.Role.HOST:
		return _network.describe()
	return "Others join at %s" % _network.advertised_endpoint()


## The policy's veto, applied at the one place it can be: a versus lobby whose
## humans all share a camp has no opposing side, and #554 D3's
## [method resolve_mode] would quietly hand back COOP_HOTSEAT rather than fail.
## The button is also disabled, so this guard is belt-and-braces for a caller
## that emits `pressed` directly (every test does).
func _on_start_button_pressed() -> void:
	if not can_start():
		return
	# The link is NOT released here any more (#715). START's whole job on a host
	# is now to broadcast the settled run, and the seed it has to carry is not
	# resolved until the shell calls [method GameSession.start] on the config this
	# emit hands up. So the release moved one signal later, onto
	# [method _on_run_started] — which is also where the CLIENT releases, off the
	# very same signal, arriving from the wire instead of from a button.
	start_pressed.emit(build_run_config())


## The run is open — on a HOST because the shell just called
## [method GameSession.start] with what the button above emitted, on a CLIENT
## because the host's [constant CommandLink.KIND_SETUP] landed on this lobby's
## own link and [method GameSession.apply_received] adopted it (#715).
##
## [b]One signal, both sides, and that symmetry is the point.[/b] Before this,
## the run's shape crossed on JOIN, pushed by [code]GameRoot._on_peer_joined[/code]
## off a [signal NetworkTransport.peer_joined] that a pre-established link never
## fires again — so a level built on an adopted socket waited on a message that
## had already been sent. START broadcasts it explicitly instead, at the one
## moment the run is actually settled, and both machines leave the menu from the
## same fact rather than from a handshake.
##
## The release is here rather than at the button for the ordering reason above,
## and it still runs BEFORE either machine routes: the socket outlives this
## screen and the level adopts it (#713), but this lobby's [CommandLink] must
## not, or two bound facades answer every packet ([method Wire.claim_binder]).
func _on_run_started(config: RunConfig) -> void:
	if _link == null:
		return
	if not _is_client():
		# `GameSession.roster` and not `_participants`: [method GameSession.start]
		# has just rebuilt the roster from the config it resolved, and that
		# resolved config is what the peer must adopt — the sentinel seed this
		# lobby was showing a moment ago is not a run.
		_link.send_run_setup(config, GameSession.roster)
	release_link()
	if _is_client():
		remote_start.emit(config)


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
		_start_button.disabled = _link_lost or not can_start()


## --- #716 item 4: link loss has somewhere to appear ---------------------------
##
## Three distinct sentences, because they are three distinct situations and a
## human on a dead screen needs to know which one they are in: the host dropped
## me for a reason, the link died under me, or the peer I refused was that one.
## Blank means nothing has gone wrong — this label is an incident line, not a
## caption ([method _link_caption] is the caption).
func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


## Public so a test — and, later, a diagnostics panel — can read the incident
## line without reaching into a private child.
func status_text() -> String:
	return "" if _status_label == null else _status_label.text


## This machine's link went away without it asking. There is nothing to retry
## from here: the route back is the panel's [BackAffordance], and START is
## refused until then rather than opening a run whose other seat cannot arrive.
func _on_transport_link_lost(reason: String) -> void:
	_link_lost = true
	if not _refusal_shown:
		_set_status("Connection lost — %s. Go back and try again." % reason)
	_refresh_start_enabled()


## This machine was refused: by the host it dialled, or by its own local
## comparison against a hello. Not latched into [member _link_lost] — a refusal
## is a verdict about the code being run, and saying "connection lost" over it
## would name the wrong problem.
func _on_link_refused(reason: String) -> void:
	_refusal_shown = true
	_set_status("Refused — %s" % reason)


## Host-side: a joiner did not clear the gate. It was disconnected and never
## seated, so the roster is deliberately untouched here — the only trace a
## refused peer leaves anywhere is this line.
func _on_link_peer_refused(peer_id: int, reason: String) -> void:
	_set_status("Refused peer %d — %s" % [peer_id, reason])


## What the wire was already doing when this screen mounted (#716 item 4). A dial
## that fails SYNCHRONOUSLY — an unreachable or malformed address, where
## `create_client` itself errors — is over before any panel exists, so no signal
## will ever arrive and [member Wire.last_status] is the only account of it left.
## Keyed on [member _transport] rather than on [method Wire.is_open] alone: a
## mount that adopted a live link is the healthy case however the socket got
## there, and a test that binds a [LoopbackTransport] afterwards clears this in
## [method bind_link].
func _report_mount_state() -> void:
	if _transport != null:
		return
	_link_lost = true
	_set_status("Connection lost — %s. Go back and try again."
			% (Wire.last_status if Wire.last_status != "" else "no link"))


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


## --- #714: the wire ----------------------------------------------------------
##
## Host-authoritative intent-up / confirmed-command-down
## (`docs/domain/multiplayer-sync-model.md`) at the ROSTER's scope: a client
## sends the one seat it touched as a [constant CommandLink.KIND_LOBBY_PICK],
## the host puts it through the very writers a local pick goes through
## ([method _on_color_picked] and its siblings), and the host answers with its
## whole roster as a [constant CommandLink.KIND_LOBBY]. No new architecture, and
## exactly one rule set — the refusal path in particular is not a message but the
## absence of a change in the answer everybody gets anyway.
##
## [b]The link is ADOPTED, never opened here.[/b] `meta_root.gd` is the one place
## that decides a route opens a socket, the same file that already decides which
## [NetworkConfig] a route leaves on [GameSession]. A lobby with no live [Wire]
## behind it mounts nothing at all, which is what keeps offline, hot-seat and
## every existing lobby test on exactly the path they were on before.
func _mount_link() -> void:
	if _network == null or not _network.is_online() or not Wire.is_open():
		return
	var transport := EnetTransport.new()
	transport.name = "Transport"
	add_child(transport)
	# Binds to the live [Wire] and replays whoever joined already — on a host
	# that re-fires the join this lobby has to stamp.
	var err := (transport.start_host(_network.port)
			if _network.role == NetworkTransport.Role.HOST
			else transport.start_client(_network.address, _network.port))
	if err != OK:
		remove_child(transport)
		transport.queue_free()
		return
	bind_link(transport)


## Put this lobby on [param transport], which is expected to be live already.
##
## Split out of [method _mount_link] so a headless test can hand it a
## [LoopbackTransport] pair and drive the whole protocol without a socket — the
## same seam every other leg of the wire is tested through
## (`test/unit/network/`). Production has exactly one caller, above.
func bind_link(transport: NetworkTransport) -> void:
	_transport = transport
	_link = CommandLink.new()
	_link.name = "CommandLink"
	_link.transport = _transport
	_link.lobby_roster_received.connect(_adopt_remote_roster)
	_link.lobby_pick_received.connect(_on_remote_pick)
	# #716: the build gate, on both of its ends. A seat is offered on
	# `peer_cleared` and never on the bare join, so a peer on the wrong commit
	# cannot appear in anybody's roster even for one broadcast.
	_link.peer_cleared.connect(_on_link_peer_cleared)
	_link.peer_refused.connect(_on_link_peer_refused)
	_link.link_refused.connect(_on_link_refused)
	add_child(_link)
	# Set AFTER `add_child`, because [method CommandLink._ready] re-applies the
	# role onto its (here absent) applier — and because a lobby-time link must
	# have a role the moment the socket is live, not when a level says so.
	_link.mode = (CommandLink.Mode.BROADCAST
			if _network.role == NetworkTransport.Role.HOST
			else CommandLink.Mode.MIRROR)
	_transport.peer_joined.connect(_on_link_peer_joined)
	_transport.peer_left.connect(_on_link_peer_left)
	_transport.link_lost.connect(_on_transport_link_lost)
	# #715: START's broadcast (host) and the route-out it produces (both sides)
	# hang off the run opening, not off the button — see [method _on_run_started].
	# Connected only on a lobby that HAS a link, so an offline lobby is untouched.
	if not GameSession.run_started.is_connected(_on_run_started):
		GameSession.run_started.connect(_on_run_started)
	_local_peer = _transport.local_peer_id()
	# A link was adopted after all, so whatever [method _report_mount_state]
	# concluded from its absence is stale.
	_link_lost = false
	_refusal_shown = false
	_set_status("")
	# A no-op on the production path (the rows do not exist yet — `_ready` mounts
	# the link first, precisely so they can be built knowing the answer), and what
	# makes a link bound afterwards repaint the seats it just re-decided.
	_refresh_rows()


## Drop this lobby's binding to the socket WITHOUT closing it. The socket is what
## the level adopts (#713); what must not survive is a second [CommandLink]
## listening on it, which is why this runs at START rather than waiting for the
## menu scene to be freed.
##
## [b]Public, and both roles call it (#715).[/b] The host used to be the only one
## that ever released — a client was routed by nothing in particular and relied
## on the menu scene being freed synchronously before the level's
## [EnetTransport] bound. It is not, and [method Wire.claim_binder] now refuses
## the level's facade outright rather than letting two of them double-handle
## every packet. Both sides release on [method _on_run_started].
##
## Idempotent: releasing twice, or with no link mounted, is a no-op.
func release_link() -> void:
	for node in [_link, _transport]:
		if node == null:
			continue
		# The transport may not be ours — [method bind_link] takes a live one.
		if node.get_parent() == self:
			remove_child(node)
			node.queue_free()
	_link = null
	_transport = null


func _is_client() -> bool:
	return _network != null and _network.role == NetworkTransport.Role.CLIENT


## A peer arrived. On a client it is this machine finally learning its OWN id,
## which is what makes [method Participant.is_local] answer for the row it is
## sitting at.
##
## [b]On a HOST this no longer seats anybody (#716 item 1).[/b] A socket-level
## join says only that somebody connected; whether they are running this code is
## not known until the build gate has answered, and #716 acceptance 2 is that a
## refused peer never appears in anyone's roster — not even for the one broadcast
## it would take to seat it and un-seat it. The seating moved to
## [method _on_link_peer_cleared], one signal later.
func _on_link_peer_joined(_peer_id: int) -> void:
	if not _is_client():
		return
	_local_peer = _transport.local_peer_id()
	_refresh_rows()


## The peer cleared the build gate, so now it may have a seat — #554 D2's
## outstanding half, one step later than it used to be
## ([method stamp_pending_remote_peer] is still the writer).
func _on_link_peer_cleared(peer_id: int) -> void:
	if _is_client():
		return
	stamp_pending_remote_peer(peer_id)
	_broadcast_roster()


## A peer dropped: its seat goes back to waiting rather than vanishing, because
## #554 D2's seat was authored for procgen up front and only the identity was
## ever outstanding.
func _on_link_peer_left(peer_id: int) -> void:
	if _is_client() or peer_id == _PENDING_PEER_ID:
		return
	var freed := false
	for p in _participants:
		if p.kind == Participant.Kind.HUMAN and p.peer_id == peer_id:
			p.peer_id = _PENDING_PEER_ID
			freed = true
	if not freed:
		return
	_refresh_rows()
	_broadcast_roster()


## Host-side: ship what this lobby actually holds. Called after every accepted
## change, join or drop — and after a REFUSED one too, which is the whole
## convergence story (#714 acceptance 3): a client that asked for something it
## may not have is answered with the truth rather than with silence.
func _broadcast_roster() -> void:
	if _link != null:
		_link.send_lobby_roster(ParticipantRoster.of(_participants))


## Client-side: the host's answer, adopted wholesale. No merge — the host's
## roster IS the roster, and a client that kept any part of its own would be the
## second source of truth this model exists to not have.
func _adopt_remote_roster(roster: ParticipantRoster) -> void:
	if roster == null:
		return
	_participants = roster.all()
	_refresh_rows()


## Host-side: a client asked for a change to one seat. Validated against the same
## roster rules a local pick meets, applied through the same writers, and
## answered with the whole roster either way.
func _on_remote_pick(pick: Dictionary) -> void:
	var target := _by_id(int(pick.get(PICK_ID, 0)))
	if may_edit_remotely(target, int(pick.get(PICK_PEER, 0))):
		if pick.has("display_name"):
			target.display_name = String(pick["display_name"])
		if pick.has("color"):
			_on_color_picked(pick["color"], target)
		if pick.has("core_class"):
			_on_core_class_picked(_loaded(pick["core_class"]) as CoreClass, target)
		if pick.has("camp"):
			_on_camp_picked(_loaded(pick["camp"]) as Faction, target)
	_refresh_rows()
	_broadcast_roster()


static func _loaded(path: Variant) -> Resource:
	var as_path := String(path)
	return null if as_path.is_empty() else load(as_path)


func _by_id(id: int) -> Participant:
	for p in _participants:
		if p.id == id:
			return p
	return null


## One seat's changed fields, in [method Participant.to_dict]'s encoding — a
## [Resource] crosses as its `resource_path` and never as a reference
## (`.claude/rules/multiplayer-sync.md`). [param from_peer] is the sender's own
## id, which is what the host checks the seat against.
static func encode_pick(
	participant: Participant, from_peer: int, changes: Dictionary
) -> Dictionary:
	var pick := {PICK_ID: participant.id, PICK_PEER: from_peer}
	for key in changes:
		var value: Variant = changes[key]
		pick[key] = value.resource_path if value is Resource else value
	return pick


## Client-side: ask for a change rather than making one. There is deliberately no
## local pre-application (#548 decision 5 at the roster's scope) — the row is
## repainted from the roster this machine still holds, and moves only when the
## host's answer lands.
func _submit_pick(participant: Participant, changes: Dictionary) -> void:
	if _link != null:
		_link.send_lobby_pick(encode_pick(participant, _local_peer_id(), changes))
	_refresh_rows()


## May the machine DRAWING this lobby change [param p] (#714 acceptance 6)?
##
## A human seat is editable iff it is this machine's own — [method
## Participant.is_local], #554/#562's one home for "which of these is me", with
## no local/remote flavour written into the payload. An AI seat belongs to
## whoever authors the roster: everyone except a client, which is exactly
## [method _offers_ai_opponents]'s rule and is stated as a parameter so the two
## cannot drift into two answers.
static func may_edit(p: Participant, local_peer_id: int, authors_ai: bool) -> bool:
	if p == null:
		return false
	if p.kind == Participant.Kind.AI:
		return authors_ai
	return p.is_local(local_peer_id)


## The HOST's half of the same question, asked of a pick that arrived over the
## wire. Deliberately not [method may_edit] with the sender's id: peer `0` means
## "no link", every offline seat carries it, and a payload claiming it must never
## match a row. An AI seat is never remotely editable at all — a client does not
## author the AI, and saying so here is cheaper than trusting it not to try.
static func may_edit_remotely(p: Participant, from_peer: int) -> bool:
	if p == null or from_peer == 0 or p.kind == Participant.Kind.AI:
		return false
	return p.peer_id == from_peer


## --- #643: the per-RUN section ----------------------------------------------
##
## Beside the seed field, never on a [ParticipantRow] (#643 decision 1): a
## per-slot map-size control would imply each participant picks a map.
##
## Every control here is gated by [LobbyPolicy] (#597 D5, #615 D2), and a NULL
## policy renders the section not at all — #643 acceptance 2, which is not a new
## rule but the same "null means today's behaviour" the camp half already keeps.
func _build_run_section() -> void:
	if _policy == null or not _policy.offers_run_section():
		return
	_run_section = VBoxContainer.new()
	_run_section.name = "RunSection"
	_run_section.add_theme_constant_override("separation", 4)
	content.add_child(_run_section)

	_map_size_row = _add_ladder_row("Map size:", _policy.map_size_options, KNOB_MAP_SIZE)
	_blocker_row = _add_ladder_row("Blockers:", _policy.blocker_options, KNOB_BLOCKERS)
	_arrangement_row = _add_ladder_row(
			"Starters:", _policy.arrangement_options, KNOB_ARRANGEMENT)

	if _policy.budget_overridable:
		_budget_row = _BUDGET_RANGE_ROW.instantiate()
		add_run_row(_budget_row)
		var authored := _authored_budget()
		_budget_row.set_range(authored[0], authored[1])
		_budget_row.range_changed.connect(_on_budget_range_changed)


## Appends [param row] to the run section — the seam #558 (starter arrangement)
## and #638 (victory condition) add their own controls through, so neither has
## to know how this screen builds its column. Safe before `_ready` only in the
## sense that the section must exist; a route that unlocks nothing has no
## section and silently accepts nothing, which is the correct answer for a knob
## its policy did not unlock either.
func add_run_row(row: Control) -> void:
	if _run_section == null:
		return
	_run_section.add_child(row)


## One named ladder, or null when [param option_set] is unauthored. The row is
## instanced BEFORE `set_choices` decides whether to show it, because
## `%`-unique lookups resolve on `_ready` — a row configured before entering the
## tree would fault on `%Label`.
func _add_ladder_row(
	title: String, option_set: LobbyOptionSet, knob: StringName
) -> OptionChoiceRow:
	if LobbyPolicy._ladder(option_set).is_empty():
		return null
	var row: OptionChoiceRow = _OPTION_CHOICE_ROW.instantiate()
	add_run_row(row)
	row.set_choices(title, option_set)
	row.option_picked.connect(_on_option_picked.bind(knob))
	return row


## The preset's OWN authored budget, which is what the spinners open on — the
## host is tuning relative to "the normal stuff" (owner, 2026-08-27), so a
## neutral placeholder would hide the very number being tuned. Falls back to
## [BudgetPolicy]'s own defaults when the route carries no [Scenario] yet, so
## the control is still usable rather than showing zeroes.
func _authored_budget() -> Array[int]:
	var preset := _authored_preset()
	if preset != null and preset.content != null and preset.content.budget_policy != null:
		var bp := preset.content.budget_policy
		return [bp.base_min, bp.base_max]
	var fallback := BudgetPolicy.new()
	return [fallback.base_min, fallback.base_max]


## The [Scenario] this run generates from — authored per ROUTE, on the policy
## (#597 fork 3, settled by the owner 2026-08-28).
##
## [b]Why not derived from [method resolve_mode].[/b] That is a fact about the
## ROSTER, and the roster changes while the lobby is open: seating a second
## human flips SINGLE -> COOP_HOTSEAT, which would silently swap the scenario —
## and with it the preset every override merges onto — underneath picks the host
## had already made. The route, by contrast, is fixed the moment the lobby opens.
## This also adds no new concept: [LobbyPolicy] is already the per-route authored
## gate for every other lobby choice, so there is no second table to drift and no
## switch statement anywhere.
##
## [b]Null stays null.[/b] A route with no policy — or a policy with no scenario
## — yields no [Scenario], [method RunConfig.resolved_preset] returns null, and
## the level falls back to its own `preset` export exactly as on master. That is
## the characterization property, not a defensive branch.
func _run_scenario() -> Scenario:
	return null if _policy == null else _policy.scenario


func _authored_preset() -> GraphProcgenConfig:
	var scenario := _run_scenario()
	return null if scenario == null else scenario.preset


## A ladder pick. Unlike a camp pick nothing else has to be refreshed — these
## are per-RUN, so no sibling row's options change — but the pick is recorded in
## [member _picked_options] rather than left in the widget, which is what makes
## it the source of truth [method build_run_config] reads.
func _on_option_picked(index: int, knob: StringName) -> void:
	_picked_options[knob] = index


## The host retuned the budget. Recorded as a `[min, max]` pair under one knob
## rather than two, because they are one control and one decision: a run tuned
## to "go HAM" moved both ends.
func _on_budget_range_changed(base_min: int, base_max: int) -> void:
	_picked_options[KNOB_BUDGET] = [base_min, base_max]


## Every [ScenarioOverride] the host's run-level picks amount to (#643
## acceptance 1/4). Built fresh from [member _picked_options] on each call, so
## an untouched knob contributes NOTHING — #643 acceptance 5 is "no override is
## written", not "the value happens to match the authored one", and only an
## absent entry can satisfy that.
##
## [b]The patches are duplicated, never handed over by reference.[/b] A ladder's
## [ScenarioOverride]s live on a cached, authored `.tres`; putting those very
## objects on a [RunConfig] would let a later consumer mutate shared authored
## content — the same [ExtResource]-boundary trap `_localize_module` exists for,
## arriving from the other side.
func _compose_overrides() -> Array[ScenarioOverride]:
	var out: Array[ScenarioOverride] = []
	_append_ladder_overrides(out, _policy_ladder(KNOB_MAP_SIZE), KNOB_MAP_SIZE)
	_append_ladder_overrides(out, _policy_ladder(KNOB_BLOCKERS), KNOB_BLOCKERS)
	_append_ladder_overrides(out, _policy_ladder(KNOB_ARRANGEMENT), KNOB_ARRANGEMENT)
	if _picked_options.has(KNOB_BUDGET):
		var pair: Array = _picked_options[KNOB_BUDGET]
		out.append(_leaf("content:budget_policy:base_min", int(pair[0])))
		out.append(_leaf("content:budget_policy:base_max", int(pair[1])))
	return out


func _policy_ladder(knob: StringName) -> LobbyOptionSet:
	if _policy == null:
		return null
	match knob:
		KNOB_MAP_SIZE:
			return _policy.map_size_options
		KNOB_ARRANGEMENT:
			return _policy.arrangement_options
		_:
			return _policy.blocker_options


func _append_ladder_overrides(
	out: Array[ScenarioOverride], option_set: LobbyOptionSet, knob: StringName
) -> void:
	if option_set == null or not _picked_options.has(knob):
		return
	for patch in option_set.patches_at(int(_picked_options[knob])):
		out.append(_leaf(patch.target, patch.value))


static func _leaf(target: String, value: Variant) -> ScenarioOverride:
	var o := ScenarioOverride.new()
	o.target = target
	o.value = value
	return o


func _offers_ai_opponents() -> bool:
	# Hot-seat coop and versus alike want the control; a host offers it because
	# it is the host's roster everybody plays. A joining client's own roster is
	# replaced wholesale by the host's [method GameSession.apply_received], so
	# a count it chose here would be a lie on screen.
	return not _is_client()




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
	row.set_editable(may_edit(participant, _local_peer_id(), _offers_ai_opponents()))
	# Through the row-signal handlers rather than straight onto the writers: on a
	# CLIENT a pick is a request, and only the handler knows that. The writers
	# below stay the single place a roster is actually changed, local or remote.
	row.color_picked.connect(_on_row_color_picked.bind(participant))
	row.core_class_picked.connect(_on_row_core_class_picked.bind(participant))
	row.camp_picked.connect(_on_row_camp_picked.bind(participant))


## A row asked for a colour. Local machines write it; a client sends it up
## (#714) and waits for the host's roster to say what happened.
func _on_row_color_picked(color: Color, participant: Participant) -> void:
	if _is_client():
		_submit_pick(participant, {"color": color})
		return
	_on_color_picked(color, participant)
	_broadcast_roster()


func _on_row_core_class_picked(core: CoreClass, participant: Participant) -> void:
	if _is_client():
		_submit_pick(participant, {"core_class": core})
		return
	_on_core_class_picked(core, participant)
	_broadcast_roster()


func _on_row_camp_picked(camp: Faction, participant: Participant) -> void:
	if _is_client():
		_submit_pick(participant, {"camp": camp})
		return
	_on_camp_picked(camp, participant)
	_broadcast_roster()


## A slot chose a colour. The lobby writes it, not the row — this screen owns
## the roster — and then rebuilds every row so the newly-taken colour greys out
## in its siblings' dropdowns and the freed one comes back (#616 acceptance 4).
##
## [b]The uniqueness rule is enforced HERE since #714[/b], not only by the greyed
## chips [method taken_colors] produces for the picker. Both readings ask
## [method taken_colors], so there is still exactly one rule — but a pick that
## arrived over the wire never saw a dropdown, and a client that asks for a taken
## colour has to meet the same refusal a local player physically cannot express.
## Locally this changes nothing: the chip it would need is already disabled.
func _on_color_picked(color: Color, participant: Participant) -> void:
	if color == participant.color:
		return
	if taken_colors(_participants, participant.id).has(color):
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
## what its own rows carry until then — and since #714 the moment it stops being
## a placeholder is [signal NetworkTransport.peer_joined], while the menu is
## still up, which is what lets a joiner's own row become editable in the lobby
## rather than only in the level.
func _local_peer_id() -> int:
	if _network == null or not _network.is_online():
		return 0
	if _local_peer != 0:
		return _local_peer
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
## — but the max roster is 14 (2 humans + [constant _MAX_AI_OPPONENTS]) against
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
	# #643: the run's Scenario names the preset every override merges ONTO, so
	# the two must travel together — overrides with no scenario would merge onto
	# nothing and the picks would vanish silently, which is the exact failure
	# mode #642 D4 names for a different field.
	cfg.scenario = _run_scenario()
	cfg.overrides = _compose_overrides()
	return cfg


## Non-numeric/empty text means seed = 0 — [RunConfig]'s documented legal
## authoring value for "randomise me".
static func _parse_seed(text: String) -> int:
	if text.is_empty() or not text.is_valid_int():
		return 0
	return text.to_int()


## Keeps the seed field digits-only as the host types, rather than accepting
## anything and letting [method _parse_seed] quietly discard it as "randomise
## me" — a typo would otherwise look accepted and silently reseed the run.
## Setting [member LineEdit.text] from code does not re-emit `text_changed` in
## Godot 4, so this needs no reentrancy guard.
func _on_seed_text_changed(new_text: String) -> void:
	var filtered := ""
	for c in new_text:
		if c.is_valid_int():
			filtered += c
	if filtered == new_text:
		return
	var caret := _seed_edit.caret_column - (new_text.length() - filtered.length())
	_seed_edit.text = filtered
	_seed_edit.caret_column = clampi(caret, 0, filtered.length())
