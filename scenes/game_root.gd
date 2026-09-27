class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that HudRoot (and
## future AI / save / debug consumers) compose against. Public fields are the
## level's contract — read-only by convention; GameRoot itself owns mutations.
##
## Subclasses populate level content via [method _setup_level], called between
## system wiring and turn start. Default behaviour expects a hand-authored
## scene with `%Player` already present (dev_sandbox style); procgen sandboxes
## override the hook to spawn the player after generation.
##
## Spawning runtime entities: call [method spawn_entity] — it parents under
## `graph.entities_container`, duplicates the default stat board, and force-
## allocates a core if given. The hand-authored dev_sandbox `%Player` skips
## this path; that's fine, `%Player` lookup ignores parent.

const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")

## Where a finished run routes (#460). A path, not a preload: the meta-shell
## pulls in the whole menu tree, and SceneDirector loads threaded anyway.
const META_ROOT := "res://scenes/meta/meta_root.tscn"


## Dev shortcut (#244): `F2` flips FogOverlay.intensity between fully opaque
## (ship default, 1.0) and the dimmer "almost black" (0.88) that lets a dev see
## enemy positions through unsensed fog.
##
## Was `F` until `F` became the global fullscreen toggle ([method
## Settings.toggle_fullscreen]) — a player-facing key beats a dev one, and this
## joins `F5` (restart) in function-key territory where nothing competes.
const _FOG_DEBUG_KEY: int = KEY_F2
const _FOG_INTENSITY_SHIP: float = 1.0
const _FOG_INTENSITY_DEV: float = 0.88

## Intent flags — let a subclass / inherited scene run a *neutered* GameRoot
## (e.g. a live showcase in an editor tab) without the parts a self-driven demo
## doesn't want. Defaults preserve full-game behaviour, so real levels are
## untouched. Every system is present in every GameRoot scene (#1006, ADR
## 0026): "off" is a flag on the system it toggles, never a missing node —
## [member TurnManager.opens_first_turn], [member HudRoot.enabled],
## [member VisionSystem.enabled] — and a missing `%System` is the assert at
## the top of [method _ready], not a branch.
@export_group("Showcase / embed")
## When false, a finished run announces its outcome but stays put — a sandbox
## or a showcase must not teleport itself back to the main menu. Vetoes BOTH
## ways out (#526): the fallback timeout below and the overlay's own button.
@export var route_to_meta_on_run_end: bool = true
## Seconds between the terminal outcome and the FALLBACK route back to the
## meta-shell. Since #526 the run-end overlay carries a *to main menu* button,
## so this is what catches a player who never clicks it — long enough to read
## the outcome and decide, not the primary way out.
@export_range(0.0, 60.0, 0.5, "or_greater") var run_end_route_delay: float = 20.0

## Grown around the graph's SkillNode AABB to get the fog/aura bound, and
## passed to the camera as its zoom==1.0 pan-margin baseline (GraphCamera
## scales it by 1/zoom past that) — breathing room so a node sitting exactly
## on the edge doesn't touch the viewport border, tweakable per level.
@export_range(0, 2000, 1.0, "or_greater") var graph_bounds_margin: float = 900.0

# Entities — `player` may be null until _setup_level() resolves it. The default
# hook tries to find a `%Player` unique-name node; subclasses can replace.
var player: Entity
## Who THIS MACHINE plays and whose eyes it draws with — the per-machine half
## of a run's setup, and the one thing here a peer is allowed to answer
## differently. Defaults to a couch (every local human plays, the view follows
## the turn), which is what a roster-less hand-authored scene wants; a level
## with a roster replaces it via [method SeatPolicy.from_roster] during
## `_setup_level`, before `bind_player` runs. Never read by anything a peer
## must reproduce — see [SeatPolicy].
var seat_policy: SeatPolicy = SeatPolicy.couch()
## Latched by [method route_to_meta_now] so the run leaves the level once (#526)
## — the overlay's button and the fallback timeout are two callers of one route.
var _run_end_routed: bool = false
## Set at the tail of `_ready`, read by [method is_reveal_ready] — the whole
## SceneDirector reveal contract is this one bool.
var _reveal_ready: bool = false

## The run-end overlay already says why the link ended — a refusal's reason
## arrives a message before the hang-up it causes, and the hang-up's generic
## "the host went away" must not paint over it.
var _link_end_presented: bool = false
@onready var graph: Graph = $Graph

# Systems
@onready var input_ctl: PlayerInputController = %PlayerInputController
@onready var allocation_system: AllocationSystem = %AllocationSystem
@onready var entity_factory: EntityFactory = %EntityFactory
@onready var controller_factory: ControllerFactory = %ControllerFactory
@onready var seat_handover: SeatHandover = %SeatHandover
@onready var battle_system: BattleSystem = %BattleSystem
## Read by [AIController] (kill-XP preview for its scorer) through the same
## GameRoot walk as [member battle_system].
@onready var loot_system: LootSystem = %LootSystem
@onready var turn_manager: TurnManager = %TurnManager
## The one mutation path (#510). Exposed here because [AIController] resolves it
## by walking up to its GameRoot, the same way it resolves [member battle_system]
## — the applier node itself has been in `game_root.tscn` since #510.
@onready var command_applier: CommandApplier = %CommandApplier
## #564: the registry needs the roster + this machine's peer id to answer
## `is_remote_collector`. Injected below rather than read off the [GameSession]
## autoload from inside the registry itself, matching how [member seat_policy]
## reaches [member command_applier] — GameRoot mediates, the leaf system stays
## a plain dependency-taking object.
@onready var pick_registry: LootPickRegistry = %LootPickRegistry
## The wire, mounted every level (#531). [b]The node PATH is the contract[/b] —
## Godot resolves an RPC by node path, so `Transport` and `CommandLink` must sit
## at the same place in every scene both peers run, which is why they live in
## the composition root rather than in whichever level happens to be networked.
## A level that wants a real socket overrides the mounted `Transport`'s script
## (`scenes/dev/mp_dev_sandbox.tscn` swaps in [EnetTransport]); it must never
## author a SECOND pair, or `$Transport` resolves to whichever one Godot named
## first. The default is a [LoopbackTransport] with the link in
## [constant CommandLink.Mode.OFF]: mounted and inert, so offline play is
## unchanged — nothing is serialized until a role raises the mode.
@onready var transport: NetworkTransport = %Transport
@onready var command_link: CommandLink = %CommandLink
## The network role of this level (#1004): who decides, bringing the socket
## up, a joiner's wait for the world, and the peer events. The root subscribes
## to its signals for the presentation half.
@onready var network_session: NetworkSession = %NetworkSession
@onready var vision_system: VisionSystem = %VisionSystem
@onready var victory_system: VictorySystem = %VictorySystem
@onready var highlight_controller: HighlightController = %HighlightController

@onready var floater_director: FloaterDirector = %FloaterDirector
@onready var fog_overlay: FogOverlay = %FogOverlay
@onready var aura_overlay: AuraOverlay = %AuraOverlay

# UI
@onready var camera: GraphCamera = %GraphCamera
## The sole decider of where the camera looks (#523). GameRoot never pokes
## `camera.position` around it.
@onready var camera_director: CameraDirector = %CameraDirector
@onready var hud_root: HudRoot = %HudRoot

@onready var node_highlight: NodeHighlightOverlay = %NodeHighlightOverlay
@onready var edge_highlight: EdgeHighlightOverlay = %EdgeHighlightOverlay
@onready var attack_vfx: AttackVFX = %AttackVFX
@onready var allocation_vfx: AllocationVFX = %AllocationVFX
@onready var melee_preview: MeleePreview = %MeleePreview


## Every system is present in every GameRoot scene (#1006, ADR 0026). A
## fixture that wants one "off" sets that system's own flag; a scene that
## dropped the node is a wiring error, and this is where it says so — before
## the first `system.method()` reads as a confusing "Nonexistent function in
## base 'Nil'" halfway through `_ready`.
func _assert_systems_present() -> void:
	for pair: Array in [
		[input_ctl, "PlayerInputController"], [allocation_system, "AllocationSystem"],
		[battle_system, "BattleSystem"], [turn_manager, "TurnManager"],
		[command_applier, "CommandApplier"], [pick_registry, "LootPickRegistry"],
		[transport, "Transport"], [command_link, "CommandLink"],
		[network_session, "NetworkSession"], [vision_system, "VisionSystem"],
		[victory_system, "VictorySystem"], [highlight_controller, "HighlightController"],
		[floater_director, "FloaterDirector"], [fog_overlay, "FogOverlay"],
		[aura_overlay, "AuraOverlay"], [camera, "GraphCamera"],
		[camera_director, "CameraDirector"], [hud_root, "HudRoot"],
		[entity_factory, "EntityFactory"], [controller_factory, "ControllerFactory"],
		[seat_handover, "SeatHandover"],
	]:
		assert(pair[0] != null, ("GameRoot: %%%s is missing — every system is present in "
				+ "every GameRoot scene; set its own `enabled` to turn it off (#1006)") % pair[1])


func _ready() -> void:
	_assert_systems_present()
	# BEFORE anything can act, and before `_setup_level` spawns an actor that
	# could: adopting the role writes `command_applier.is_authority`, and a
	# CLIENT that learns it is not the authority only after its first AI turn
	# has decided locally has already diverged. The socket opens later, in
	# [method NetworkSession.join_or_host].
	network_session.adopt_role()
	# #715: how the arriving world builds an entity the roster never names — see
	# [method EntityFactory.spawn_snapshot_entity]. Set here, before any link
	# can be up, because the first thing a joining client does with its link is ask for that world.
	command_link.entity_spawner = entity_factory.spawn_snapshot_entity
	# The session owns the wire's lifecycle; the root keeps the presentation of
	# each event (#1004). The world-arrived hook re-runs `_ensure_controllers`
	# for entities the resync brought with it — idempotent and cheap.
	network_session.world_ready.connect(_on_world_ready)
	network_session.refused.connect(_present_link_end)
	network_session.link_lost.connect(_present_link_end)
	network_session.local_peer_resolved.connect(_on_local_peer_resolved)
	# The handover itself is [SeatHandover]'s; the root presents it. `quiet`
	# is read here from the harness flag until the harness sets it itself.
	seat_handover.quiet = HarnessFlags.has(HarnessFlags.AUTOPLAY)
	seat_handover.seat_handed_over.connect(_on_seat_handed_over)
	# Entity death (#18): AllocationSystem strips the corpse off the same bus
	# signal; GameRoot owns the player-vs-NPC consequence, and its VISUAL half
	# rides `entity_death_shown`, which `Entity.die()` emits last.
	Events.entity_died.connect(_on_entity_died)
	Events.entity_death_shown.connect(_on_entity_death_shown)
	# #460: VictorySystem decides the run's end; GameRoot presents and routes.
	Events.run_ended.connect(_on_run_ended)

	# Scene-authored ownership (dev_sandbox-style) must claim SP before
	# _setup_level runs — hand-authored owned_by= skips force_allocate's claim.
	allocation_system.register_scene_authored_ownership()
	# Nothing opens a socket before this on either role (#715): the run's shape
	# crossed from the LOBBY at START, so `GameSession` already holds the host's
	# run on every machine. `_setup_level` runs BEFORE hud_root.compose because
	# compose reads `player.stat_board` immediately; `await` is harmless on
	# synchronous overrides.
	await _setup_level()
	_apply_graph_bounds()
	# Invariant: every Entity has an EntityController child, so the turn loop
	# never stalls on an uncontrolled actor in a hand-authored sandbox.
	_ensure_controllers()
	# After `_setup_level`, which is where a roster-driven level replaces the
	# default couch policy — pushed from the one place that owns it to the three
	# consumers that ask "is this actor mine?" (#524, #556, #819/#820).
	camera_director.seat_policy = seat_policy
	command_applier.seat_policy = seat_policy
	battle_system.seat_policy = seat_policy
	# #564: NOT seat_policy — is_remote_collector answers for a PEER (a roster
	# question). A null roster (no lobby) reads as "nobody is remote".
	pick_registry.roster = GameSession.roster
	pick_registry.local_peer_id = GameSession.local_peer_id
	# The run decides how it ends (#457/#460); `resolved_...` falls back to the
	# MODE's default when the run authored no condition.
	if GameSession.is_active():
		victory_system.condition = GameSession.config.resolved_victory_condition()
	bind_player(player)
	# Hot-seat coop (#459): connected unconditionally — [member seat_policy]
	# decides whether the handler does anything. After `_ensure_controllers` so
	# the `is_human_controlled` flag it reads is settled.
	turn_manager.turn_started.connect(_on_turn_started_for_handover)
	# A disabled HUD ([member HudRoot.enabled]) makes every one of these a
	# no-op and hides its own layer; the root does not branch on it.
	hud_root.compose(self)
	_wire_hud_floater_anchor()
	_wire_gained_modifier_toast()
	if hud_root.enabled:
		# Container layout resolves via a queued `sort_children`; `start_turn`
		# below can pop a same-frame toast at the Hero Sigil Card's FloatAnchor,
		# which reads (0,0)-ish until one frame flushes the deferred sort.
		await get_tree().process_frame

	# Hooked BEFORE the link opens: a joiner whose level comes up AFTER the
	# host's first turn gets that turn inside the resync (`adopt_turn` fires
	# `turn_started` from within `_on_resync`), so a hook connected after the
	# await had missed the only turn start it was there to report (2026-09-06).
	_announce_first_turn_for_rung_3()
	# Opens the link on every role and, on a joiner, waits for the authority's
	# world or for the link to end — whichever first. See
	# [method NetworkSession.join_or_host] for why the pull follows the open at
	# once and why the wait is bounded by the link rather than by a timeout.
	if not await network_session.join_or_host():
		SceneTransition.progress_bar.hide()
		_reveal_ready = true
		if SceneTransition.is_curtain_up():
			await SceneTransition.fade_in()
		return
	# #667, second half. The world now exists on EVERY path — offline, host and
	# client alike — so the run may be judged. Before this line a death would
	# let `LastCampStandingCondition` read a partially-populated entity group
	# and latch an outcome that can never be un-fired. Not a network concept:
	# the same one line arms it for a solo sandbox.
	victory_system.world_ready = true

	_arm_rung_4()
	_stagger_initiative()
	_open_first_turn()
	_focus_camera_on_player()
	# LAST. Everything above is what "presentable" means: the world generated,
	# the HUD composed, the camera already on the player. Only now does the
	# screen come back — see [method is_reveal_ready].
	_reveal_ready = true
	if SceneTransition.is_curtain_up():
		await SceneTransition.fade_in()


## Whether this run staggers opening clocks is the run's call
## ([member RunConfig.stagger_initiative], on unless a live session turns it
## off); how is [method TurnManager.stagger_opening_clocks]'. Runs before
## [method _open_first_turn], on every peer.
func _stagger_initiative() -> void:
	if turn_manager == null:
		return
	if GameSession.is_active() and not GameSession.config.stagger_initiative:
		return
	turn_manager.stagger_opening_clocks()


## Open the run's clock — as a [StartTurnCommand], never as a local call (#756).
##
## [b]The mirror never starts a turn on its own.[/b] Before this, every peer ran
## `turn_manager.start_turn(player)` here on ITS OWN seated hero, so the host
## opened on Player 1 and the client opened on Player 2. Nothing ever corrected
## that: `TurnManager.current_entity`, `TurnManager.turns_taken` and each
## [member Entity.turns_taken] are host DECISIONS, and under
## `.claude/rules/multiplayer-sync.md` a peer receives a decision or reproduces
## it — this one was doing neither. Every later [EndTurnCommand] then reproduced
## `_tick_until_ready` from a different cursor, so turn-start upkeep ran for the
## wrong entity and the accumulated tier drifted apart (#756).
##
## So the authority SUBMITS and the mirror WAITS. A mirror's cursor arrives
## either as this command coming back down the [constant
## CommandLink.KIND_COMMAND] leg, or — for a peer whose join world was encoded
## after the host had already started — inside the resync itself
## ([method EntitySnapshot.restore_turn_cursor]).
##
## The direct call survives only where there is no applier at all (a hand-built
## test rig): offline play keeps going through the applier like everything else,
## which is what keeps this one path and not two.
func _open_first_turn() -> void:
	if not turn_manager.opens_first_turn:
		return
	if not network_session.is_authority():
		return
	if player == null:
		return
	# #923 (owner call on #911): the entity that opens is
	# [method TurnManager.opening_entity] — spawn/roster index 0, the same rule
	# offline, couch and remote alike. `player` is a fallback for a fixture
	# where nothing carries a clock. On a couch/hot-seat authority seating >=2
	# local humans, `player` is whichever one `_seat_the_roster`'s loop
	# happened to assign LAST — `opening_entity()` is the settled reading there.
	var opener := turn_manager.opening_entity()
	if opener == null:
		opener = player
	if command_applier == null:
		# Skip the initial tick race: fill the opener's clock so they act first.
		# (start_turn clears the ready-group membership this would otherwise set.)
		if opener.stat_board != null and opener.stat_board.initiative != null:
			opener.stat_board.initiative.restore_to_full()
		turn_manager.start_turn(opener)
		return
	command_applier.submit(StartTurnCommand.new(opener.entity_id))


## Rung 3's verdict line (#715) — the level half of `meta_root`'s
## `--lobby=host|client` driver. Prints, once, on the first turn this machine
## sees: which world it holds and whether it agrees with the other process.
##
## [b]On `turn_started`, not on the resync[/b], because "the first turn starts"
## IS acceptance 1. A client that decoded a world and then never got a turn has
## not proved the thing; the fingerprint beside it is what makes the pair
## comparable across two logs.
##
## Behind the same explicit flag `meta_root` reads, so an ordinary launch, an
## exported build and every test print nothing and parse nothing.
## `""` unless this process was launched by `meta_root`'s `--lobby=` driver.
static func _rung_3_role() -> String:
	return HarnessFlags.value(HarnessFlags.LOBBY)


func _announce_first_turn_for_rung_3() -> void:
	var role := _rung_3_role()
	if role.is_empty() or turn_manager == null:
		return
	var announce := func(entity: Entity) -> void:
		print("[%s] rung 3: FIRST TURN — %s | %d nodes | %s | seat %d | %s" % [
			role,
			entity.display_name if entity != null else "<none>",
			graph.get_skill_nodes().size(),
			"authority" if network_session.is_authority() else "mirror",
			seat_policy.seated_entity_id,
			WorldFingerprint.describe(graph),
		])
	turn_manager.turn_started.connect(announce, CONNECT_ONE_SHOT)


## --- Rung 4: the run plays itself and says how it ended (#754) ----------------
##
## Rung 3 proves two processes reach the same first turn. Rung 4 keeps the same
## two processes going to a VERDICT — the host hands every human seat to the AI,
## both ends print one greppable line when [signal Events.run_ended] fires, and
## both quit so `mise run mp:e2e` can compare the two logs and exit on the
## difference. See `docs/domain/multiplayer-harness.md`.
##
## Everything here is behind `--autoplay` on top of the rung-3 flag, so an
## ordinary launch, an exported build and the GUT suite are untouched.

## Entity-turns (NOT rounds — [member TurnManager.turns_taken] counts each
## entity's turn) an autoplay run may spend before it is declared a timeout.
## Two heroes on the smallest map settle in well under this; the number is a
## hang detector, not a balance claim, and `--max-turns=N` overrides it.
const _RUNG4_MAX_TURNS := 400

## Exit code a timed-out autoplay run quits with — distinct from the 1 the
## engine uses for its own failures, so the harness can tell "the run never
## ended" from "the process fell over".
const _RUNG4_TIMEOUT_EXIT := 2


func _arm_rung_4() -> void:
	var role := _rung_3_role()
	if role.is_empty() or turn_manager == null or not HarnessFlags.has(HarnessFlags.AUTOPLAY):
		return
	Events.run_ended.connect(_announce_verdict_for_rung_4.bind(role), CONNECT_ONE_SHOT)
	var cap := HarnessFlags.number(HarnessFlags.MAX_TURNS, _RUNG4_MAX_TURNS)
	turn_manager.turn_started.connect(func(_e: Entity) -> void: _watch_turn_cap(role, cap))
	if not network_session.is_authority():
		# A mirror needs nothing: its own hero is driven by the authority's
		# confirmed commands, and a second AI deciding locally is exactly the
		# divergence this run exists to detect.
		return
	# Deferred out of the emission: the handover kicks the current entity's turn
	# ([method SeatHandover.hand_seat_to_ai]), and doing that from inside `turn_started`
	# would re-enter the turn loop underneath the signal that started it.
	turn_manager.turn_started.connect(
			func(_e: Entity) -> void: _autoplay_every_human_seat.call_deferred(role),
			CONNECT_ONE_SHOT)


## The host's half of `--autoplay`: every HUMAN seat becomes the AI's.
##
## No new mechanism — this is the peer-left handover (#753/#755) invoked
## deliberately rather than on a dropped socket, which is what makes it worth
## reusing: the AI's turns cross the wire as ordinary confirmed commands, so the
## client is exercised as a mirror of a real opponent, not as a process running
## its own copy of the same policy, and #755's broadcast means the mirror's own
## roster learns the seat is the AI's rather than believing a human still holds
## it.
func _autoplay_every_human_seat(role: String) -> void:
	if GameSession.roster == null:
		return
	var seated := 0
	for p in GameSession.roster.all():
		if p.kind == Participant.Kind.HUMAN:
			seat_handover.hand_seat_to_ai(p)
			seated += 1
	print("[%s] rung 4: autoplay — %d human seat(s) handed to the AI" % [role, seated])


## One line per process on `run_ended`, and then out.
##
## [b]Nothing is awaited before the print.[/b] [method _on_run_ended] routes to
## the meta-shell after [member run_end_route_delay], and routing tears this
## graph down — a fingerprint sampled after that would describe a world that no
## longer exists and mismatch its peer for a reason that is not a sync bug.
##
## [member RunOutcome.winning_camp] is null on a DRAW, and the camp's
## [member Faction.id] is what crosses (a `.tres` path resolves per machine, a
## display name is presentation) — so the two logs compare as plain strings.
func _announce_verdict_for_rung_4(outcome: RunOutcome, role: String) -> void:
	print("[%s] RUNG4 VERDICT — winner=%s | turns=%d | %s" % [
		role,
		"draw" if outcome == null or outcome.winning_camp == null
				else String(outcome.winning_camp.id),
		0 if outcome == null else outcome.turn_count,
		WorldFingerprint.describe(graph),
	])
	get_tree().quit(0)


## The hang detector. A run that cannot end — a stalled turn loop, an AI with
## nothing legal to do, a victory condition that never fires — must fail loudly
## and on its own, rather than being killed by the harness's wall clock, because
## only this side knows how far it actually got.
func _watch_turn_cap(role: String, cap: int) -> void:
	if turn_manager.turns_taken < cap:
		return
	print("[%s] RUNG4 TIMEOUT — %d entity-turns spent, cap %d | %s" % [
		role, turn_manager.turns_taken, cap, WorldFingerprint.describe(graph),
	])
	get_tree().quit(_RUNG4_TIMEOUT_EXIT)
## The drain (#504, design B). An attack's world mutation is spread across a
## real interval, so a scene change mid-volley would strand every hit that had
## not landed yet — a world that is valid but permanently wrong. Draining here
## lands the rest synchronously, while the nodes involved are still alive.
func _exit_tree() -> void:
	battle_system.drain_pending_mutations()


## The [SceneDirector] reveal contract: is this level worth looking at yet?
##
## A level's `_ready` is a coroutine — it awaits [method _setup_level], which on
## a procgen level generates a few hundred nodes across many frames. Whoever
## faded the screen out must not fade it back in until this reads true, or the
## player watches the HUD sit over an empty world and then the world pop in.
##
## The flag is set at the very end of `_ready` and this level lowers its own
## curtain there; [SceneDirector] only waits (bounded — a client stuck waiting
## on a host's `run_setup` still gets a screen eventually).
func is_reveal_ready() -> bool:
	return _reveal_ready


## The link ended — refused by the host, or the host went away — and the
## player is told on the run-end overlay, because the way out (its main-menu
## button → [method route_to_meta_now]) is the same one a finished run takes.
## The session has already abandoned the applier's parked intent.
##
## A refusal's reason arrives a message BEFORE the hang-up it causes, and the
## hang-up's generic "the host went away" must not paint over it — hence the
## latch. After the run has ENDED nothing is presented: the host pressing its
## main-menu button stops the wire, which every client hears as a lost link
## while its own victory overlay is up. That is the normal end of a run.
func _present_link_end(reason: String) -> void:
	if victory_system.outcome != null:
		return
	if not _link_end_presented:
		_link_end_presented = true
		hud_root.present_link_lost(reason)


## Client-side (#668): the socket just told us our own peer id. Restate BOTH
## registry copies — `_ready` pushed a snapshot of `GameSession.roster` and
## `.local_peer_id`, and this exists precisely for the case where those were
## not yet known then. Both, not just the id — they fail through
## [method LootPickRegistry.is_local_collector] in OPPOSITE directions, and
## only one of them is safe. A stale `local_peer_id` of 0 answers false for
## this peer's own hero (its loot picker never opens — visible); a stale null
## `roster` answers true for EVERYONE (every peer opens a picker — #668 back,
## and silent).
func _on_local_peer_resolved(peer_id: int) -> void:
	pick_registry.roster = GameSession.roster
	pick_registry.local_peer_id = peer_id


## A seat passed to the AI on this peer ([signal SeatHandover.seat_handed_over]).
## Seat vision is re-derived because [method SeatPolicy.vision_group] is
## computed from [member Entity.is_human_controlled], not reactive to it; the
## banner is skipped when the handover was asked for rather than forced.
func _on_seat_handed_over(entity: Entity, quiet: bool) -> void:
	_apply_seat_vision()
	if not quiet:
		hud_root.announce_peer_left(entity.display_name)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode != _FOG_DEBUG_KEY:
		return
	if fog_overlay == null:
		return
	fog_overlay.intensity = _FOG_INTENSITY_DEV if fog_overlay.intensity == _FOG_INTENSITY_SHIP else _FOG_INTENSITY_SHIP
	get_viewport().set_input_as_handled()


## Entity death consequence (#18). Node-stripping is AllocationSystem's job (it
## also listens to `entity_died`); here we handle the turn-loop-critical half of
## what's left SYNCHRONOUSLY — a corpse must not hold/receive a turn — and
## defer the VISUAL half (despawn) to `_on_entity_death_shown`.
##
## #460: this used to skip the player, which was only safe because player death
## ended play immediately. It no longer does — [VictorySystem] decides that, and
## in hot-seat coop a dead player may leave a living ally — so a player corpse
## must be pulled from the turn loop like any other, or TurnManager keeps
## ticking its initiative and eventually hands the turn to a dead entity whose
## PlayerController waits forever for input.
##
## #504: `Entity.die()` emits `entity_death_shown` itself, last — after both
## bus phases, so AllocationSystem's strip has run against a still-owned world
## before the corpse despawns. Under design B the model dies at the moment it
## is drawn dying, so there is no reveal to wait for and no fallback branch:
## every death path (an attack, upkeep, an effect, a test calling `die()`)
## arrives here the same way.
func _on_entity_died(entity: Entity) -> void:
	if entity == null:
		return
	_pull_from_turn_loop(entity)


## Pull a corpse out of the turn-loop groups SYNCHRONOUSLY so TurnManager's
## tick / `_tick_until_ready` skip it this frame — `queue_free` leaves the node
## valid (and group-resident) until frame end, or later still under #479's
## reveal gate, so the group removal can't wait for either. Defensive: if the
## corpse somehow held the turn, end that turn so the loop isn't stalled on an
## actor that's about to disappear.
##
## #443: through [method TurnManager.abandon_turn], never by nulling
## `current_entity` from out here. The field write left the turn silently
## un-ended — [signal TurnManager.turn_ended] never fired, and the only thing
## that noticed was an `assert` in `start_turn` that a release build compiles
## out. See that method for why it deliberately stops there and does not tick
## on to the next entity.
func _pull_from_turn_loop(entity: Entity) -> void:
	entity.remove_from_group(Entity.GROUP)
	entity.remove_from_group(Entity.READY_GROUP)
	turn_manager.abandon_turn(entity)


## Presentation clock (#479): the killing blow's own reveal has landed (or, per
## `_on_entity_died`, nothing was ever going to reveal one) — do the actual
## despawn / game-over now.
func _on_entity_death_shown(entity: Entity) -> void:
	_reveal_entity_death(entity)


## Free order is safe: AllocationSystem's death handler deallocates the corpse's
## nodes SYNCHRONOUSLY (off `entity_died`, before either call path here can
## run), so freeing the entity itself — now or after the reveal gate — can't
## orphan them.
## #460: the player's corpse is NOT freed — it stays in the tree (dead, and
## already stripped of its nodes) so the camera and HUD still have something to
## point at while VictorySystem decides the run's fate. Whether a player death
## ends the run is no longer GameRoot's call: in hot-seat coop an ally may still
## be standing, and the condition is the one place that knows.
func _reveal_entity_death(entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	if entity != player:
		entity.queue_free()


## The run is over (#460) — [VictorySystem] is the sole decider; GameRoot only
## presents and routes.
##
## GameRoot no longer decides what the run-end LOOKS like (#517). It used to
## re-emit `Events.game_over` whenever the outcome was not a local WIN, which
## meant the composition root held a point of view — and on a hot-seat couch
## "the local camp" is whoever acted last, so the answer was undefined by
## construction. [HudRoot] now listens to [signal Events.run_ended] directly and
## gates the overlay on [member seat_policy], which is a fact about this
## machine rather than about the turn order. `Events.game_over` went with the
## last of that (#526) — the signal is deleted, not left dangling.
##
## The route back to the meta-shell is deliberately minimal per the issue ("a
## results screen is out of scope — a minimal route is enough"). This is now the
## FALLBACK half of it: the run-end overlay's button is the primary way out, and
## this catches whoever never presses it.
func _on_run_ended(_outcome: RunOutcome) -> void:
	if not route_to_meta_on_run_end:
		return
	await get_tree().create_timer(run_end_route_delay).timeout
	if is_inside_tree():
		route_to_meta_now()


## Leave the finished run for the meta-shell. The ONE way out (#526): both the
## overlay's button and the fallback timeout above come through here, so
## clicking out early and then sitting past the timeout cannot `goto` twice —
## and cannot end the session twice, which would spend the next run's seed.
##
## Vetoed wholesale by [member route_to_meta_on_run_end]: a neutered GameRoot
## (a dev sandbox, an editor-tab showcase) never leaves its own scene, and that
## holds for the button too. Returns whether the route was actually taken — the
## caller needs to know, because a vetoed press has to dismiss the overlay
## instead of leaving a full-screen dim with a dead button on top of a sandbox
## you were still poking at.
func route_to_meta_now() -> bool:
	if _run_end_routed or not route_to_meta_on_run_end:
		return false
	_run_end_routed = true
	# The run is over and we're leaving it: close the session so the next one
	# resolves its own seed instead of inheriting a spent one (#457). The
	# outcome it recorded is read by whoever presents it before this.
	GameSession.end()
	_leave_for_meta()
	return true


## The departure itself, split off [method route_to_meta_now] so the latch and
## the veto can be exercised without a test actually swapping the scene out from
## under GUT. Overridden by `test/fixtures/route_probe_game_root.gd`.
func _leave_for_meta() -> void:
	SceneDirector.goto(META_ROOT)


## Wire a (possibly late-resolved) human player into the *player-interaction*
## layer — highlight fallback owner, input controller, vision viewer. Faction
## and controller kind are decided elsewhere (#475: [method apply_roster], or
## authored directly on a hand-authored scene's node) — this only wires the
## camera/HUD's notion of "who am I looking through".
## Null-safe + idempotent: GameRoot calls it once at the tail of `_ready` (after
## `_setup_level` has had its chance to set `player`), and a level that resolves
## its player asynchronously — or swaps it — can call it again.
##
## A self-driven showcase passes `null` (no human player): every dependant is
## left untouched, which is exactly what keeps these non-`@tool` systems dormant
## when a neutered GameRoot runs live in an editor tab. Don't move per-player
## wiring back out into `_ready` — routing it through here is what makes the
## no-player path clean.
func bind_player(p: Entity) -> void:
	player = p
	if player == null:
		return
	highlight_controller.player = player
	# Clears the outgoing player's armed modes / attack plan / targeting on the
	# way in — see [method PlayerInputController._set_player].
	input_ctl.player = player
	_apply_seat_vision()
	# Nothing victory-side is set from here any more (#517). A hot-seat handover
	# re-enters this method, so anything point-of-view-ish assigned here would
	# read from whoever acted last — which is exactly how `local_camp` came to
	# be undefined on a versus couch. The outcome is POV-free; the HUD resolves
	# the local reading from `seat_policy`, which a handover cannot change.
	# #91/#108 — the Hero Sigil Card's floater anchor follows the active hero
	# too, or player 1 keeps collecting player 2's wound/heal toasts. No-op
	# until the HUD is composed.
	_wire_hud_floater_anchor()
	hud_root.rebind_player(player)
	_focus_camera_on_player()


## Fog is an ALLIED-HUMANS reveal, not a per-hero one (#459) — the rule and
## its four cases live on [method SeatPolicy.vision_group]. Coop shares
## (handover doesn't re-derive fog from a different subgraph and flash the
## map); versus doesn't (rivals are different camps); AI and blockers never do.
##
## The candidate walk stays HERE, and stays in group order, because the skip
## below is array equality — element-wise, so order counts. Both sides of a
## coop handover must produce the identical array or the setter reassigns and
## the map flashes; `test_handover_does_not_re_derive_fog` pins it with
## `is_same`.
##
## The assignment is skipped when the set is unchanged — [member
## VisionSystem.viewers] is a setter that unconditionally rebinds every viewer
## stat and recomputes, and a hot-seat handover between two members of the same
## camp produces the identical set. (A no-op skip, not a recursion guard.)
func _apply_seat_vision() -> void:
	if vision_system == null or player == null or player.faction == null:
		return
	var candidates: Array[Entity] = []
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var ent := node as Entity
		if ent != null:
			candidates.append(ent)
	var viewers := SeatPolicy.vision_group(player, candidates)
	if vision_system.viewers == viewers:
		return
	vision_system.viewers = viewers


## Hot-seat handover (#459). On a shared couch "the player" is whoever's turn
## it is among this machine's heroes — the HUD, the input channel, the camera
## and the victory viewpoint all re-point through the one seam that already
## owns them. Behind a wire the local view is pinned and this does nothing.
##
## Both questions are [member seat_policy]'s: [method SeatPolicy.seats] (is
## this one of mine — `is_human_controlled` on a couch, one `entity_id` in a
## seat) and [method SeatPolicy.follows_active_turn]. So an AI turn never
## steals the local view, a single-human run never fires this at all, and a
## networked peer needs no un-wiring to stay put.
func _on_turn_started_for_handover(entity: Entity) -> void:
	if entity == null or entity == player:
		return
	if not seat_policy.follows_active_turn():
		return
	if not seat_policy.seats(entity):
		return
	bind_player(entity)


## Invariant: every [Entity] carries an [EntityController] — see
## [method ControllerFactory.ensure_all]. Idempotent.
func _ensure_controllers() -> void:
	controller_factory.ensure_all()


## Applies each roster participant's authored camp + control-kind + name onto its
## already-spawned entity — the roster-driven replacement for deciding
## faction or controller from "is this entity named player" (#475).
## [param entities_by_participant_id] maps [member Participant.id] to the
## [Entity] spawned for it; participants with no matching entry, or whose
## [member Participant.camp] is unset, are skipped. Static + side-effect-only
## on the entities: no dependency on a live GameRoot, so it's testable
## against a roster built in isolation, not against lobby UI.
##
## Everything applied here is ABSOLUTE — camp, and "is a human" — so every peer
## running the same roster reaches the same answer. The per-machine half ("which
## of these is mine") is [SeatPolicy]'s, off [method Participant.is_local].
static func apply_roster(entities_by_participant_id: Dictionary, roster: ParticipantRoster) -> void:
	for participant in roster.all():
		var ent: Entity = entities_by_participant_id.get(participant.id)
		if ent == null or participant.camp == null:
			continue
		ent.faction = participant.camp
		ent.is_human_controlled = participant.kind != Participant.Kind.AI
		# #564: the correlation LootPickRegistry.is_remote_collector needs.
		# Set alongside the other roster-authored fields above rather than in
		# a second pass — every entity this loop actually touches IS the
		# seated entity.
		ent.participant_id = participant.id
		# The name the lobby slot typed (or a hand-rolled fixture authored) is run
		# shape like everything else in this loop: it crossed the wire inside the
		# roster, so every peer's HUD shows the same hero name. Empty means the
		# roster never named the seat — the spawn-time name ("Player", "Enemy_3")
		# stays rather than blanking the presentation.
		if not participant.display_name.is_empty():
			ent.display_name = participant.display_name


## Subclass hook. Default = pick up an existing `%Player` node from the scene
## (dev_sandbox shape). Procgen sandboxes override to run generation + spawn
## entities, then assign `self.player`.
func _setup_level() -> void:
	if false: await get_tree().process_frame # include fake `await` to make godot see this as a coroutine
	if has_node("%Player"):
		player = get_node("%Player") as Entity


## Forwarder — see [method EntityFactory.spawn_entity].
func spawn_entity(ent_name: String, color: Color, core_location: SkillNode = null,
		core_class: CoreClass = null) -> Entity:
	return entity_factory.spawn_entity(ent_name, color, core_location, core_class)


## Forwarder — see [method EntityFactory.spawn_blocker].
func spawn_blocker(size: EntityFactory.BlockerSize, core_location: SkillNode,
		footprint: Array[SkillNode] = [], spell_prune_seed: int = 0,
		spell_prune_m: float = 0.0, preassigned_id: int = 0,
		stake_level: int = 1, stake_xp_offset_floor: float = 0.25) -> Entity:
	return entity_factory.spawn_blocker(size, core_location, footprint, spell_prune_seed,
			spell_prune_m, preassigned_id, stake_level, stake_xp_offset_floor)


## The authority's world has landed (#715, [signal NetworkSession.world_ready]).
## Anything [method EntityFactory.spawn_snapshot_entity]
## built arrived after the level's own pass, so give it a controller and put the
## fog back on this machine's real subgraph — the seat's vision was derived from
## a player that owned nothing at the time.
func _on_world_ready(_reason: String) -> void:
	_ensure_controllers()
	_apply_seat_vision()
	# Reassigned rather than left to [method _apply_seat_vision]'s skip-if-equal
	# guard: the viewer SET is unchanged (same heroes), while what each of them
	# OWNS just arrived wholesale — and `owned_by` written by
	# [method GraphSnapshot._decode_node] bypasses [AllocationSystem], so
	# nothing on `allocation_changed` will do it for us. The setter always
	# rebinds and recomputes.
	vision_system.viewers = vision_system.viewers


func _on_core_moved(_entity: Entity, from_node: SkillNode, to_node: SkillNode) -> void:
	if to_node == null or from_node == null:
		return
	to_node.play_core_slide_from(from_node.global_position)


## #91/#108 — routes the player's entity-level toasts (wound/heal, stat
## modifier gain) to the Hero Sigil Card's FloatAnchor instead of the
## world-space core. No-op if the HUD is off ([member HudRoot.enabled]) or
## the player hasn't resolved yet.
func _wire_hud_floater_anchor() -> void:
	if not hud_root.enabled or player == null:
		return
	floater_director.player = player
	floater_director.player_anchor = hud_root.hero_sigil_card.float_anchor


## #306 — "you just got these": on a voluntary player allocation, slab the
## node's granted modifiers beside the Hero avatar, then absorb them into it.
##
## Its own layer, deliberately NOT the floater queue (different dwell, anchor
## and exit). Mounted in HudRoot rather than under Graph like FloaterDirector,
## so it sits in the HUD canvas and does not scale with camera zoom.
##
## Two gates, neither of which the toast decides for itself:
##   - `entity == player` — this is the HERO avatar's surface; an NPC
##     allocating a node must not toast on it.
##   - `not forced` — mirrors the existing convention for cosmetic gain
##     reactions (see AllocationSystem's `allocated` docstring: #70 floaters
##     and #71 pulses gate the same way), so a level's setup/procgen
##     allocations don't fire a flurry at startup.
func _wire_gained_modifier_toast() -> void:
	if not hud_root.enabled or player == null:
		return
	hud_root.gained_modifier_toast.float_anchor = hud_root.hero_sigil_card.float_anchor
	if not allocation_system.allocated.is_connected(_on_node_allocated_for_toast):
		allocation_system.allocated.connect(_on_node_allocated_for_toast)


func _on_node_allocated_for_toast(node: SkillNode, entity: Entity, forced: bool) -> void:
	if forced or entity != player or node == null:
		return
	if hud_root == null or hud_root.gained_modifier_toast == null:
		return
	hud_root.gained_modifier_toast.show_gains(node.modifiers)


## Bounds the camera pan and the fog-of-war / aura paint rects to the graph's
## own footprint — a hand-authored sandbox and a 3000-radius procgen level
## shouldn't share one hardcoded rect. Runs once, after `_setup_level()`
## has populated the graph (nodes don't exist before that — see the camera's
## own `_zoom_by` resync comment for the same ordering gotcha).
##
## The limit rect is exactly the AABB + margin, no bigger — so on a small
## graph (dev_sandbox) it can end up smaller than the viewport at
## [constant GraphCamera.MIN_ZOOM]. Rather than grow the limit rect past the
## graph's actual footprint to cover that, push a matching zoom-out floor onto
## the camera instead: [method Camera2D.limit_*] degenerates once the view
## rect exceeds the limit rect, and stopping the zoom-out there keeps the two
## in agreement without inflating what the fog paints.
func _apply_graph_bounds() -> void:
	if graph == null:
		return
	var raw_bounds := graph.get_node_bounds()
	if raw_bounds.size == Vector2.ZERO:
		return
	var baseline_bounds := raw_bounds.grow(graph_bounds_margin)

	if not camera.bounds_changed.is_connected(_on_camera_bounds_changed):
		camera.bounds_changed.connect(_on_camera_bounds_changed)
	# Camera gets the RAW bounds + the margin as a zoom==1.0 baseline, not
	# the pre-grown `baseline_bounds` rect — it re-derives its own pan
	# limit every frame, scaling the margin by 1/zoom
	# (GraphCamera._update_limits), then pushes the result back via
	# `bounds_changed` so fog/aura paint the same zoom-scaled rect instead
	# of a second, independently-computed one (see _on_camera_bounds_changed).
	camera.set_graph_bounds(raw_bounds, graph_bounds_margin)
	var viewport_size := get_viewport().get_visible_rect().size
	var min_zoom_floor: float = maxf(viewport_size.x / baseline_bounds.size.x, viewport_size.y / baseline_bounds.size.y)
	camera.set_min_zoom_floor(min_zoom_floor)


## Mirrors GraphCamera's zoom-scaled pan limit onto the fog/aura overlays so
## all three always agree on how far past the graph edge is visible.
func _on_camera_bounds_changed(bounds: Rect2) -> void:
	fog_overlay.bounds = bounds
	aura_overlay.bounds = bounds


## Point the view at the bound hero — level start, and every hot-seat handover
## (#459). Routed through [CameraDirector] (#523) so there is exactly ONE thing
## deciding where the camera looks; the request is [b]mandatory[/b] (it bypasses
## the grace window and the skip-if-on-screen check) and a hard cut, because a
## seat changing hands must re-point the view unconditionally — anything softer
## would be a behaviour change to #459.
func _focus_camera_on_player() -> void:
	if player == null:
		return
	# `Entity` extends [Node], not [Node2D] — it has no `position` of its own, and
	# the hero's place in the world IS its core node. Before #715 the fallback was
	# unreachable (a spawned hero always got a core), so it read `player.position`
	# and would have thrown on the first machine that hit it. A joining client
	# reaches it every time: it seats the roster before any node exists and the
	# core arrives with the resync, so the camera simply has nowhere to look yet.
	# `_on_world_ready` -> `bind_player` is not what re-points it; the turn
	# start that follows the world's arrival is.
	var target: Vector2 = (player.core_location.global_position
			if player.core_location != null else Vector2.ZERO)
	camera_director.request_focus(FocusRequest.point(target, 0.0, true, &"handover"))
