class_name LobbyScreen
extends VBoxContainer

## Lobby: one row per participant, a host-side "AI opponents" count, a seed
## field and a Start button. The seed field is live (#457): START hands this
## screen's [RunConfig] to `GameSession`, which resolves the seed once and feeds
## it to procgen — so typing back the seed the pause-menu footer shows replays
## the same map. Blank means "randomise me".
##
## [b]A view over a [LobbyRoster] (#1002).[/b] The run's shape — who is seated,
## on which camp, in which colour, whether START is allowed — is the roster's;
## this screen renders rows from it, forwards every edit to its writers, and
## repaints on [signal LobbyRoster.changed]. What stays here is what only a
## screen can do: the widgets, the run-section ladders the route's
## [LobbyPolicy] unlocks (map size, blockers, arrangement, victory, budget),
## the [CommandLink] it adopts, and the status copy the wire produces.
##
## The three roster shapes, why the remote seat is declared before anybody
## joins, and why colour is run shape are documented on [LobbyRoster].
##
## Deliberately minimal: scenic screens are what remains of #461.

signal start_pressed(run_config: RunConfig)

## The HOST pressed START and this machine is the one that joined (#715). The
## sibling of [signal start_pressed] for the peer that does not decide: same
## destination, same [RunConfig], reached from the wire rather than a button —
## and deliberately its own signal, because the shell must NOT re-open the run
## ([method GameSession.apply_received] already did, and re-running
## [method GameSession.start] would re-resolve the seed and hand this peer a
## different map).
signal remote_start(run_config: RunConfig)

## Every hero colour a slot may hold (#616 D5). One authored resource, not a
## const array here — see `ui/theme/player_palette.gd` for why gold and pure
## white are both absent from it.
const _PALETTE := preload("res://ui/theme/player_palette.tres")

## The rules behind these live on [LobbyRoster]; the names stay here because
## the rows and the routes still read them off the screen.
const _PENDING_PEER_ID := LobbyRoster.PENDING_PEER_ID
const MAX_NAME_LENGTH := LobbyRoster.MAX_NAME_LENGTH
const DEFAULT_AI_OPPONENTS := LobbyRoster.DEFAULT_AI_OPPONENTS
const MAX_AI_OPPONENTS := LobbyRoster.MAX_AI_OPPONENTS

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
const _AI_PRESET_ROW := preload("res://ui/frontmatter/panels/ai_preset_row.tscn")
const _OPTION_CHOICE_ROW := preload("res://ui/frontmatter/panels/option_choice_row.tscn")
const _BUDGET_RANGE_ROW := preload("res://ui/frontmatter/panels/budget_range_row.tscn")
const _ROW_SCENE := preload("res://ui/common/labelled_row.tscn")

## Keys into [member _run_picks] (#643 decision 1 — these are per-RUN, so
## they are keyed by KNOB, not by [member Participant.id] the way
## a [LobbyRoster.Pick] is). A knob ABSENT from that dictionary is the
## "host never touched this control" state, and #643 acceptance 5 is exactly
## the assertion that such a knob contributes no override at all.
const KNOB_MAP_SIZE := &"map_size"
const KNOB_BLOCKERS := &"blockers"
## Which shape the starters are laid out in (#558) — GROUPED / ALTERNATING /
## RANDOM. Per-RUN like the rest: one arrangement describes the whole board's
## seating, not one participant's.
const KNOB_ARRANGEMENT := &"arrangement"
const KNOB_BUDGET := &"budget"
## How a run ENDS (#638, #742). Per-run like every other knob here — a
## [VictoryCondition] describes the whole board, not one participant's slot.
const KNOB_VICTORY := &"victory"
## Center vs. edge (#742) — which [StarterPlacement] the run generates from.
const KNOB_SPAWN_ORDER := &"spawn_order"

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

## The domain half (#1002): participants, pick memory, seat vetoes and the
## START gate. Minted by [method configure]; an unconfigured instance gets the
## single-player shape in [method _ready].
var _roster: LobbyRoster = null
var _seed_edit: LineEdit
var _start_button: Button
var _ai_count_row: AiCountRow
var _ai_preset_row: AiPresetRow
var _rows_container: VBoxContainer

## --- #714: the roster replicates while the menu is up --------------------------
##
## The lobby's own [NetworkTransport] + [CommandLink] pair, mounted only when a
## socket is ALREADY open (see [method _mount_link]). It is the same seam the
## level mounts, at the one other scope that needs it — and it never opens the
## link itself, so a lobby built with no wire behind it is byte-for-byte the
## offline lobby that shipped before this.
var _transport: NetworkTransport = null
var _link: CommandLink = null

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


## One-shot: this lobby's run has opened and been broadcast (#715). See
## [method _on_run_started] for why it is latched before the send.
var _started: bool = false


## The run-level section beside the seed field (#643). Named and reachable
## through [method add_run_row] because it is a SHARED surface: #558 appends a
## starter-arrangement control here and #638 a victory-condition one, in a later
## wave. Nothing about it is map-size-shaped.
var _run_section: VBoxContainer
var _map_size_row: OptionChoiceRow
var _blocker_row: OptionChoiceRow
var _arrangement_row: OptionChoiceRow
var _victory_row: OptionChoiceRow
var _spawn_order_row: OptionChoiceRow
var _budget_row: BudgetRangeRow

## Run-level picks the host made explicitly, keyed by knob (see [constant
## KNOB_MAP_SIZE]). Values are a ladder INDEX for the pickers and a
## `[base_min, base_max]` pair for the budget row.
##
## [b]Same rebuild-survival contract as the roster's picks, for a different
## reason.[/b] Those survive because the roster rebuilds on every slot change;
## these survive because this dictionary — not the widget — is what
## [method build_run_config] reads. The widget is a view of the pick, so a
## control that is rebuilt, hidden or never realised cannot silently drop one.
var _run_picks: Dictionary = {}


## Configures this lobby before it enters the tree (call right after
## [method LobbyScreen.new], before it enters the tree). [param mode] is
## the shape the menu route ASKED for, not the mode the run ends up with —
## [method LobbyRoster.resolve_mode] derives that from the roster at START (#554 D3).
## Defaults to the single-player shape so an unconfigured instance still behaves
## as it always has.
## [param policy] is what this lobby's ROUTE lets its slots choose (#615 D2) —
## it hangs on the route rather than being looked up from [param mode] precisely
## because [param mode] is not authoritative. Null reproduces the pre-#615
## lobby exactly: no camp control anywhere, and START never refused.
func configure(
	mode: RunConfig.Mode, network: NetworkConfig = null, policy: LobbyPolicy = null
) -> void:
	_roster = LobbyRoster.new(mode, network, policy)
	_roster.changed.connect(_on_roster_changed)

func _ready() -> void:
	if _roster == null:
		configure(RunConfig.Mode.SINGLE)
	add_theme_constant_override("separation", 8)
	# Before the roster is built: a client's own peer id decides which row reads
	# "you" and which pickers it may touch, and a host must be listening for the
	# join that stamps its waiting seat before it can possibly arrive.
	_mount_link()

	if _offers_ai_opponents():
		_ai_count_row = _AI_COUNT_ROW.instantiate()
		content.add_child(_ai_count_row)
		# Seed AFTER `add_child` (the row's controls are `@onready`, so they are
		# null before it enters the tree) and BEFORE connecting `value_changed`:
		# seeding moves the slider, which would otherwise fire a rebuild against
		# a roster that does not exist yet.
		_ai_count_row.set_range(0, MAX_AI_OPPONENTS)
		_ai_count_row.set_value(DEFAULT_AI_OPPONENTS)
		# The joiner sees the new shape too: a rebuild used to reach it only inside
		# START's run setup, so its lobby drew a roster the host had already
		# replaced. Host-only by construction — only a host owns this row.
		_ai_count_row.value_changed.connect(_on_ai_count_changed)

		# #841: gated the same as the count row above it — a client authors no
		# AI slots at all ([method _offers_ai_opponents]), so it has nothing to
		# template.
		_ai_preset_row = _AI_PRESET_ROW.instantiate()
		content.add_child(_ai_preset_row)
		_ai_preset_row.set_core_choices(CoreClass.pickable_for(CoreClass.PICKABLE_AI))
		_ai_preset_row.core_changed.connect(_on_preset_core_changed)
		# #884: camp joins the preset only where an AI seat may pick one.
		if _roster.policy != null and _roster.policy.may_pick_camp(Participant.Kind.AI):
			_ai_preset_row.set_camp_choices(_roster.policy.camp_choices())
			_ai_preset_row.camp_changed.connect(_on_preset_camp_changed)
		# #1086: every AI seat has a tier, so the tier preset is never gated.
		_ai_preset_row.tier_changed.connect(_on_preset_tier_changed)

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

	if _roster.network != null and _roster.network.is_online():
		_link_label = Label.new()
		_link_label.text = _link_caption()
		content.add_child(_link_label)
		_status_label = Label.new()
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(_status_label)
		_report_mount_state()

	_refresh_rows()

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
	if _roster.network.role != NetworkTransport.Role.HOST:
		return _roster.network.describe()
	return "Others join at %s" % _roster.network.advertised_endpoint()


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
	if _link == null or _started:
		return
	# Latched BEFORE the send, not after, and the release below is not enough on
	# its own. [signal GameSession.run_started] is a global autoload signal, and
	# the receiving side re-emits it from [method GameSession.apply_received] —
	# so with both lobbies in ONE process (every headless test of this path) the
	# host's own handler re-enters from inside its own `send`, before the release
	# on the last line can run. The latch is what makes that terminate. In
	# production it says the plainer thing: a lobby starts its run once.
	_started = true
	if not _is_client():
		# `GameSession.roster` and not the lobby's own: [method GameSession.start]
		# has just rebuilt the roster from the config it resolved, and that
		# resolved config is what the peer must adopt — the sentinel seed this
		# lobby was showing a moment ago is not a run.
		_link.send_run_setup(config, GameSession.roster)
	release_link()
	if _is_client():
		remote_start.emit(config)


## Is START allowed on the current roster? Always true without a policy — see
## [method configure].
## Is START allowed on the current roster? The roster's rule ([method
## LobbyRoster.can_start]); always true without a policy.
func can_start() -> bool:
	return _roster.can_start()


## Why START is refused right now, or `""`. Public so the panel layer can
## surface it without re-deriving the rule.
func start_blocked_reason() -> String:
	return _roster.start_blocked_reason()
## a transient wait, so they are left alone rather than overwritten here.
func _refresh_start_enabled() -> void:
	if _start_button != null:
		_start_button.disabled = _link_lost or not can_start()
	if not _link_lost and not _refusal_shown:
		_set_status(start_blocked_reason())


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
##
## [b]Removal path for the #736 connecting gate[/b] — the refusal already
## dropped the socket ([method CommandLink._refuse_peer]), so this seat's
## transient hold on START is over too. Erase-then-refresh BEFORE the explicit
## message below, so that message is the one left standing rather than
## whatever [method _refresh_start_enabled] would otherwise have written.
##
## [b]This line survives only until the next [method _refresh_start_enabled]
## call, though — not until something else explicit overwrites it.[/b] Unlike
## the client-side refusal ([method _on_link_refused]), which latches
## [member _refusal_shown] and so is protected, nothing latches this one: it
## shares [member _status_label] with the #736 gate reason, and any later
## roster change (a colour pick, the AI count, another peer connecting) recomputes
## and can blank it. Deliberate — tracking "was the last write mine" costs more
## than a status line that outlives its moment, and skipping the empty write
## would leave a stale "waiting" line behind it. A host that wants the reason
## after the fact has the trace in [signal CommandLink.logged] instead.
func _on_link_peer_refused(peer_id: int, reason: String) -> void:
	_roster.remove_remote(peer_id)
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
## stamps a participant in place ([method LobbyRoster.clear_remote]).
func participants() -> Array[Participant]:
	return _roster.participants


## The domain half itself, for a caller that wants the picks and the START
## gate rather than the list (#1002).
func roster() -> LobbyRoster:
	return _roster


## Is anybody's seat still waiting for a real id? The only honest "may START
## now" question a caller outside this file can ask (#715).
func has_pending_remote() -> bool:
	return _roster.has_pending_remote()


## shim: removed when #1004 lands. `scenes/game_root.gd` still stamps the
## level-time join through this name; the rule lives on [LobbyRoster].
static func stamp_pending_remote(roster_in: ParticipantRoster, peer_id: int) -> bool:
	return LobbyRoster.stamp_pending_remote(roster_in, peer_id)


## behind it mounts nothing at all, which is what keeps offline, hot-seat and
## every existing lobby test on exactly the path they were on before.
func _mount_link() -> void:
	if _roster.network == null or not _roster.network.is_online() or not Wire.is_open():
		return
	var transport := EnetTransport.new()
	transport.name = "Transport"
	add_child(transport)
	# Binds to the live [Wire] and replays whoever joined already — on a host
	# that re-fires the join this lobby has to stamp.
	var err := (transport.start_host(_roster.network.port)
			if _roster.network.role == NetworkTransport.Role.HOST
			else transport.start_client(_roster.network.address, _roster.network.port))
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
	# #741: only a CLIENT's own [method CommandLink.announce_self] ever reads
	# this — a host announces its WORLD, not an identity — but setting it here
	# unconditionally means this file is the one place the value comes from.
	_link.join_display_name = Settings.current.player_name
	_link.lobby_roster_received.connect(_adopt_remote_roster)
	_link.lobby_pick_received.connect(_on_remote_pick)
	# #716: the build gate, on both of its ends. A seat is offered on
	# `peer_cleared` and never on the bare join, so a peer on the wrong commit
	# cannot appear in anybody's roster even for one broadcast.
	_link.peer_cleared.connect(_on_link_peer_cleared)
	_link.peer_refused.connect(_on_link_peer_refused)
	_link.link_refused.connect(_on_link_refused)
	# The wire's own trace, to stdout and so to `user://logs/godot.log` on every
	# online lobby — not only under the rung-3 flag. A LAN playtest that goes
	# wrong on another machine has nothing else to hand back (2026-09-06).
	var trace_role := "client lobby" if _is_client() else "host lobby"
	_link.logged.connect(func(line: String) -> void: print("[%s] %s" % [trace_role, line]))
	add_child(_link)
	# Set AFTER `add_child`, because [method CommandLink._ready] re-applies the
	# role onto its (here absent) applier — and because a lobby-time link must
	# have a role the moment the socket is live, not when a level says so.
	_link.mode = (CommandLink.Mode.BROADCAST
			if _roster.network.role == NetworkTransport.Role.HOST
			else CommandLink.Mode.MIRROR)
	_transport.peer_joined.connect(_on_link_peer_joined)
	_transport.peer_left.connect(_on_link_peer_left)
	_transport.link_lost.connect(_on_transport_link_lost)
	# #715: START's broadcast (host) and the route-out it produces (both sides)
	# hang off the run opening, not off the button — see [method _on_run_started].
	# Connected only on a lobby that HAS a link, so an offline lobby is untouched.
	if not GameSession.run_started.is_connected(_on_run_started):
		GameSession.run_started.connect(_on_run_started)
	_roster.set_local_peer(_transport.local_peer_id())
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
	return _roster.is_client()


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
##
## [b]It still gates START (#736).[/b] Not seating the peer left nothing marking
## that this window is even open, so a host who pressed START right here shipped
## a roster the joiner could not find itself in — see [method LobbyRoster.add_remote].
func _on_link_peer_joined(peer_id: int) -> void:
	if not _is_client():
		_roster.add_remote(peer_id)
		return
	_roster.set_local_peer(_transport.local_peer_id())


func _on_link_peer_cleared(peer_id: int, join_prefs: Dictionary = {}) -> void:
	if _is_client():
		return
	_roster.clear_remote(peer_id, join_prefs)
	_broadcast_roster()


func _on_link_peer_left(peer_id: int) -> void:
	if _is_client():
		return
	if _roster.remove_remote(peer_id):
		_broadcast_roster()


func _broadcast_roster() -> void:
	if _link != null:
		_link.send_lobby_roster(_roster.to_participant_roster())


func _adopt_remote_roster(roster: ParticipantRoster) -> void:
	_roster.adopt(roster)


## The host answers with its whole roster whether or not the pick landed — the
## refusal path is not a message but the absence of a change in the answer.
func _on_remote_pick(pick: Dictionary) -> void:
	_roster.apply_remote_pick(pick)
	_broadcast_roster()


func _submit_pick(participant: Participant, changes: Dictionary) -> void:
	if _link != null:
		_link.send_lobby_pick(LobbyRoster.encode_pick(participant, _local_peer_id(), changes))
	_refresh_rows()
## cannot drift into two answers.
## rule but the same "null means today's behaviour" the camp half already keeps.
func _build_run_section() -> void:
	if _roster.policy == null or not _roster.policy.offers_run_section():
		return
	_run_section = VBoxContainer.new()
	_run_section.name = "RunSection"
	_run_section.add_theme_constant_override("separation", 4)
	content.add_child(_run_section)

	_map_size_row = _add_ladder_row("Map size:", _roster.policy.map_size_options, KNOB_MAP_SIZE)
	_blocker_row = _add_ladder_row("Blockers:", _roster.policy.blocker_options, KNOB_BLOCKERS)
	_arrangement_row = _add_ladder_row(
			"Starters:", _roster.policy.arrangement_options, KNOB_ARRANGEMENT)
	_victory_row = _add_ladder_row("Victory:", _roster.policy.victory_options, KNOB_VICTORY)
	_spawn_order_row = _add_ladder_row(
			"Spawn order:", _roster.policy.spawn_order_options, KNOB_SPAWN_ORDER, _roster.policy.spawn_order_pickable)

	if _roster.policy.budget_overridable:
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
	title: String, option_set: LobbyOptionSet, knob: StringName, enabled: bool = true
) -> OptionChoiceRow:
	if LobbyPolicy._ladder(option_set).is_empty():
		return null
	var row: OptionChoiceRow = _OPTION_CHOICE_ROW.instantiate()
	add_run_row(row)
	row.set_choices(title, option_set)
	row.set_enabled(enabled)
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
	return null if _roster.policy == null else _roster.policy.scenario


func _authored_preset() -> GraphProcgenConfig:
	var scenario := _run_scenario()
	return null if scenario == null else scenario.preset


## A ladder pick. Unlike a camp pick nothing else has to be refreshed — these
## are per-RUN, so no sibling row's options change — but the pick is recorded in
## [member _run_picks] rather than left in the widget, which is what makes
## it the source of truth [method build_run_config] reads.
func _on_option_picked(index: int, knob: StringName) -> void:
	_run_picks[knob] = index


## Make a ladder pick from code, exactly as a host clicking the row would
## (#754): the widget moves AND [member _run_picks] records it, so the
## pick reaches [method build_run_config] as a real override rather than a
## dropdown that merely looks changed.
##
## Both halves are needed and neither is redundant. [method
## OptionChoiceRow.set_value] deliberately does not emit — it is the
## rebuild-survival view — so the record has to be written here; and writing
## only the record would leave the visible row disagreeing with the run about to
## start, which is the kind of lie a harness driving the SHIPPED route exists to
## avoid. A knob whose ladder its policy never unlocked has no row; the pick is
## still recorded, and [method _append_ladder_overrides] drops it for want of an
## option set, which is the same answer that knob gives a human.
func pick_option(knob: StringName, index: int) -> void:
	var row := _ladder_row(knob)
	if row != null:
		row.set_value(index)
	_on_option_picked(index, knob)


## Set the AI-opponent count from code, as moving the slider would. Unlike
## [method pick_option] this needs no second write: [method AiCountRow.set_value]
## drives the real control, whose `value_changed` this screen is already
## listening to, so the roster rebuild happens on its own. Silently ignored on a
## route that offers no such control — a client's count is the host's to choose.
func set_ai_opponents(count: int) -> void:
	if _ai_count_row != null:
		_ai_count_row.set_value(count)


func _ladder_row(knob: StringName) -> OptionChoiceRow:
	match knob:
		KNOB_MAP_SIZE:
			return _map_size_row
		KNOB_ARRANGEMENT:
			return _arrangement_row
		KNOB_VICTORY:
			return _victory_row
		KNOB_SPAWN_ORDER:
			return _spawn_order_row
		KNOB_BLOCKERS:
			return _blocker_row
		_:
			return null


## The host retuned the budget. Recorded as a `[min, max]` pair under one knob
## rather than two, because they are one control and one decision: a run tuned
## to "go HAM" moved both ends.
func _on_budget_range_changed(base_min: int, base_max: int) -> void:
	_run_picks[KNOB_BUDGET] = [base_min, base_max]


## Every [ScenarioOverride] the host's run-level picks amount to (#643
## acceptance 1/4). Built fresh from [member _run_picks] on each call, so
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
	_append_ladder_overrides(out, _policy_ladder(KNOB_VICTORY), KNOB_VICTORY)
	_append_ladder_overrides(out, _policy_ladder(KNOB_SPAWN_ORDER), KNOB_SPAWN_ORDER)
	if _run_picks.has(KNOB_BUDGET):
		var pair: Array = _run_picks[KNOB_BUDGET]
		out.append(_leaf("preset:content:budget_policy:base_min", int(pair[0])))
		out.append(_leaf("preset:content:budget_policy:base_max", int(pair[1])))
	return out


func _policy_ladder(knob: StringName) -> LobbyOptionSet:
	if _roster.policy == null:
		return null
	match knob:
		KNOB_MAP_SIZE:
			return _roster.policy.map_size_options
		KNOB_ARRANGEMENT:
			return _roster.policy.arrangement_options
		KNOB_VICTORY:
			return _roster.policy.victory_options
		KNOB_SPAWN_ORDER:
			return _roster.policy.spawn_order_options
		_:
			return _roster.policy.blocker_options


func _append_ladder_overrides(
	out: Array[ScenarioOverride], option_set: LobbyOptionSet, knob: StringName
) -> void:
	if option_set == null or not _run_picks.has(knob):
		return
	for patch in option_set.patches_at(int(_run_picks[knob])):
		out.append(_leaf(patch.target, patch.value))


func _leaf(target: String, value: Variant) -> ScenarioOverride:
	var o := ScenarioOverride.new()
	o.target = target
	o.value = value
	return o

func _offers_ai_opponents() -> bool:
	return _roster.offers_ai_opponents()


## The roster changed under this view (a pick, a rebuild, a seat stamped or
## freed, the START gate moving): repaint every row and the button.
func _on_roster_changed() -> void:
	_refresh_rows()

func _refresh_rows() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		# `queue_free` FIRST: a focused `%Name` field mid-teardown fires
		# `focus_exited` from inside `remove_child`'s own exit-tree cascade, and
		# `is_queued_for_deletion()` is the row's only reliable "this is a
		# teardown, not a decision" read at that moment (participant_row.gd's
		# `_commit_name` guard).
		child.queue_free()
		_rows_container.remove_child(child)
	for p in _roster.participants:
		_add_participant_row(p)
	_refresh_start_enabled()


func _add_participant_row(participant: Participant) -> void:
	var row: ParticipantRow = _PARTICIPANT_ROW.instantiate()
	_rows_container.add_child(row)
	row.configure(participant, _local_peer_id())
	row.set_color_choices(_PALETTE, LobbyRoster.taken_colors(_roster.participants, participant.id))
	row.set_core_choices(CoreClass.pickable_for(LobbyRoster.slot_bit_for(participant.kind)))
	# Only a policied lobby ever asks for a camp control — a null policy leaves
	# `%Camp` untouched and hidden, which is the pre-#615 row (#615 D3).
	if _roster.policy != null:
		row.set_camp_choices(
				_roster.policy.camp_choices(), _roster.policy.may_pick_camp(participant.kind))
	if participant.kind == Participant.Kind.AI:
		var tiers: Array[int] = []
		tiers.assign(AIController.Tier.values())
		row.set_tier_choices(tiers)
	row.set_editable(_roster.may_edit_locally(participant))
	# #841: an AI row holding an explicit pick shows the un-override control —
	# provenance the roster tracks, never a value comparison against the preset.
	row.set_core_overridden(_roster.is_core_overridden(participant))
	row.set_camp_overridden(_roster.is_camp_overridden(participant))
	row.set_tier_overridden(_roster.is_tier_overridden(participant))
	# Through the row-signal handlers rather than straight onto the writers: on a
	# CLIENT a pick is a request, and only the handler knows that.
	row.color_picked.connect(_on_row_color_picked.bind(participant))
	row.core_class_picked.connect(_on_row_core_class_picked.bind(participant))
	row.core_reset_requested.connect(_on_row_core_reset.bind(participant))
	row.camp_picked.connect(_on_row_camp_picked.bind(participant))
	row.camp_reset_requested.connect(_on_row_camp_reset.bind(participant))
	row.tier_picked.connect(_on_row_tier_picked.bind(participant))
	row.tier_reset_requested.connect(_on_row_tier_reset.bind(participant))
	row.name_committed.connect(_on_row_name_committed.bind(participant))
## (#714) and waits for the host's roster to say what happened.
## --- row signals: ask on a CLIENT, write on everything else ------------------
##
## On a client a pick is a REQUEST that crosses the wire and comes back as the
## host's roster; everywhere else it goes straight to the roster's writer and
## the host answers with the result. The roster's [signal LobbyRoster.changed]
## repaints the rows; the broadcast is this screen's, because only it holds
## the link.

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


func _on_row_core_reset(participant: Participant) -> void:
	_roster.reset_core(participant)
	_broadcast_roster()


func _on_ai_count_changed(value: float) -> void:
	_roster.set_ai_opponents(int(value))
	_broadcast_roster()


func _on_preset_core_changed(core: CoreClass) -> void:
	_roster.set_preset_core(core)
	_broadcast_roster()


func _on_row_camp_reset(participant: Participant) -> void:
	_roster.reset_camp(participant)
	_broadcast_roster()


func _on_preset_camp_changed(camp: Faction) -> void:
	_roster.set_preset_camp(camp)
	_broadcast_roster()


func _on_preset_tier_changed(tier: Variant) -> void:
	_roster.set_preset_tier(tier)
	_broadcast_roster()


func _on_row_tier_picked(tier: int, participant: Participant) -> void:
	if _is_client():
		_submit_pick(participant, {"ai_tier": tier})
		return
	_roster.pick_tier(participant, tier)
	_broadcast_roster()


func _on_row_tier_reset(participant: Participant) -> void:
	_roster.reset_tier(participant)
	_broadcast_roster()


func _on_row_camp_picked(camp: Faction, participant: Participant) -> void:
	if _is_client():
		_submit_pick(participant, {"camp": camp})
		return
	_on_camp_picked(camp, participant)
	_broadcast_roster()


func _on_row_name_committed(text: String, participant: Participant) -> void:
	_maybe_save_default_name(participant, text)
	if _is_client():
		_submit_pick(participant, {"display_name": text})
		return
	_on_name_picked(text, participant)
	_broadcast_roster()


## #741: a name typed into MY seat becomes the saved default. Hot-seat's second
## slot is a guest on this machine and never overwrites it.
func _maybe_save_default_name(participant: Participant, text: String) -> void:
	if _roster.mode == RunConfig.Mode.COOP_HOTSEAT and participant.id != 1:
		return
	var wanted := LobbyRoster.normalize_name(text)
	if wanted.is_empty() or wanted == Settings.current.player_name:
		return
	Settings.current.player_name = wanted
	Settings.save_settings()


## The writers, local or remote: one door each onto the roster.
func _on_color_picked(color: Color, participant: Participant) -> void:
	_roster.pick_color(participant, color)


func _on_core_class_picked(core: CoreClass, participant: Participant) -> void:
	_roster.pick_core(participant, core)


func _on_camp_picked(camp: Faction, participant: Participant) -> void:
	_roster.pick_camp(participant, camp)


func _on_name_picked(name: String, participant: Participant) -> void:
	_roster.pick_name(participant, name)


func _local_peer_id() -> int:
	return _roster.local_peer_id()
## wiring is testable without instancing a menu (`test_lobby_roster.gd`).
func build_run_config() -> RunConfig:
	return _roster.to_run_config(
			LobbyRoster.parse_seed(_seed_edit.text if _seed_edit != null else ""),
			_run_scenario(), _compose_overrides())


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
