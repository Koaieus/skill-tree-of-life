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

## Removable blocker sizes (#300). Tier = size + 1 (SMALL → 1, MEDIUM → 2,
## LARGE → 3); see [method spawn_blocker]. Procgen blocker placements carry
## this enum's int value as the per-node `size` marker.
enum BlockerSize { SMALL, MEDIUM, LARGE }

const _BLOCKER_SCENE := preload("res://entity/blocker/blocker_entity.tscn")
const _BLOCKER_BOARDS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_small_board.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_medium_board.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_large_board.tres"),
}
const _BLOCKER_SPELLBOOKS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_spellbook_small.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_spellbook_medium.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_spellbook_large.tres"),
}

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
## doesn't want. The owner toggles its own children here; nobody reaches in from
## outside. Defaults preserve full-game behaviour, so real levels are untouched.
@export_group("Showcase / embed")
## When false, `_ready` skips the opening `start_turn` — the turn loop never
## kicks, so a showcase can drive its own beat loop (and set `current_entity`
## directly for killer attribution) without TurnManager/AI taking over.
@export var auto_start_turn: bool = true
## When false, `_ready` skips `HudRoot.compose` and hides the UI layer.
@export var show_ui: bool = true
## When false, the fog overlay is hidden (a self-driven demo wants every node
## visible regardless of owned-subgraph vision).
@export var enable_fog: bool = true
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
@onready var graph: Graph = $Graph

# Systems
@onready var input_ctl: PlayerInputController = %PlayerInputController
@onready var allocation_system: AllocationSystem = %AllocationSystem
@onready var battle_system: BattleSystem = %BattleSystem
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


func _ready() -> void:
	# BEFORE anything can act, and before `_setup_level` spawns an actor that
	# could. Adopting the role writes `command_applier.is_authority`, and a
	# CLIENT that learns it is not the authority only after its first AI turn
	# has decided and submitted locally has already diverged — the exact trap
	# `scenes/dev/mp_dev_sandbox.gd` documents at length in its own `_ready`.
	# The socket itself opens later, in `_open_link`.
	_adopt_network_role()
	# #715: how the arriving world builds an entity the roster never names — see
	# [method spawn_snapshot_entity]. Set here, before any link can be up, because
	# the first thing a joining client does with its link is ask for that world.
	if command_link != null:
		command_link.entity_spawner = spawn_snapshot_entity
		# The entities the resync brings with it arrive AFTER `_ensure_controllers`
		# has already run, so they would sit in `Entity.GROUP` uncontrolled and the
		# turn loop would stall on the first one to take a turn. Re-running it is
		# idempotent (explicit composition always wins) and cheap.
		command_link.resync_applied.connect(_on_resync_applied)
		# Rung 3's protocol trace, hooked HERE rather than beside its verdict line
		# at the tail of `_ready` — by then the resync has already been pushed
		# (host) or applied (client) and the interesting lines are gone. It is what
		# makes acceptance 3 comparable ACROSS the two logs: the host's
		# `⟳ RESYNC pushed — … (fp N)` and the client's `⟳ resync applied — … (fp N)`
		# sample the SAME world, whereas the two FIRST TURN lines are each taken at
		# their own machine's turn start and so straddle whatever the turn start
		# itself moves (regen, mana). See [method _announce_first_turn_for_rung_3].
		var rung3 := _rung_3_role()
		if not rung3.is_empty():
			command_link.logged.connect(
					func(line: String) -> void: print("[%s] %s" % [rung3, line]))
	# Entity death (#18): AllocationSystem strips the corpse's nodes off the same
	# bus signal; GameRoot owns the player-vs-NPC consequence (game-over / despawn).
	Events.entity_died.connect(_on_entity_died)
	# The VISUAL consequence (despawn / game-over) rides `entity_death_shown`,
	# which `Entity.die()` emits last — see `_on_entity_death_shown`.
	Events.entity_death_shown.connect(_on_entity_death_shown)
	# #460: the run's terminal state. VictorySystem decides it; GameRoot only
	# presents (the HUD cue) and routes.
	Events.run_ended.connect(_on_run_ended)

	# Scene-authored ownership (dev_sandbox-style) must claim SP before
	# _setup_level runs — procgen spawning goes through force_allocate which
	# claims itself, but hand-authored owned_by= assignments skip that path.
	allocation_system.register_scene_authored_ownership()
	# #715: nothing opens a socket early any more, on either role. A CLIENT used
	# to bring its link up HERE and then block `_setup_level` on the host's
	# `run_setup` — because the run's shape crossed on JOIN and could not be
	# missed. It no longer crosses on join: the host broadcasts it from the LOBBY
	# at START ([method LobbyScreen._on_run_started]), so by the time this level
	# is built `GameSession` already holds the host's run on every machine, and a
	# level that awaited that message would await a signal that has already fired
	# — a 30-second `SceneDirector.REVEAL_TIMEOUT_S` hang, not dead code.
	#
	# _setup_level runs BEFORE hud_root.compose because compose reads
	# `player.stat_board` immediately — procgen sandboxes that spawn the
	# player here need the entity in place first. `await` is harmless on
	# synchronous overrides; procgen sandboxes that drive a loading bar
	# return a coroutine.
	await _setup_level()
	_apply_graph_bounds()
	# Invariant: every Entity must have an EntityController child so the
	# turn loop never stalls on an uncontrolled actor. Hand-authored
	# scenes (dev_sandbox, first_level_sandbox) historically forgot to
	# attach AIController to enemies; this defaulter is the catch-all
	# that keeps every sandbox playable without per-scene wiring.
	_ensure_controllers()
	# After `_setup_level`, which is where a roster-driven level replaces the
	# default couch policy. The director needs it to answer "is this actor
	# mine?" before it may frame anyone's action (#524).
	if camera_director != null:
		camera_director.seat_policy = seat_policy
	# The applier asks the SAME seat question before its pre-roll pause (#556),
	# so it is pushed from the one place that owns the policy rather than
	# re-derived there. Without this the gate stays null and the pre-roll is
	# inert — see [method CommandApplier._pre_roll].
	if command_applier != null:
		command_applier.seat_policy = seat_policy
	# #564: NOT seat_policy — is_remote_collector answers for a PEER (a
	# roster question), which is exactly what the per-machine SeatPolicy
	# cannot do. GameSession.roster is null outside an active run (a
	# hand-authored sandbox with no lobby), which the registry treats as
	# "nobody is remote" rather than an error.
	if pick_registry != null:
		pick_registry.roster = GameSession.roster
		pick_registry.local_peer_id = GameSession.local_peer_id
	# The run decides how it ends (#457/#460). After `_setup_level`, which is
	# where a directly-launched level opens its session. `resolved_...` is what
	# falls back to the MODE's default when the run authored no condition — the
	# scene-authored export is the source only for a level with no live run.
	if victory_system != null and GameSession.is_active():
		victory_system.condition = GameSession.config.resolved_victory_condition()
	bind_player(player)
	# Hot-seat coop (#459): on a shared couch "the player" changes hands every
	# turn. Connected unconditionally — [member seat_policy] decides whether the
	# handler does anything, so a networked peer stays put without un-wiring a
	# signal. Connected after `_ensure_controllers` so the `is_human_controlled`
	# flag the handler reads is already settled.
	if turn_manager != null:
		turn_manager.turn_started.connect(_on_turn_started_for_handover)
	if not enable_fog:
		if fog_overlay != null:
			fog_overlay.visible = false
		# Floaters must not query the (dormant, non-@tool) VisionSystem for
		# per-node visibility in a no-fog showcase — calling a method on a
		# non-@tool node from the editor is the boundary-error class. Null it so
		# every floater shows (mirrors SandboxWorld's no-player wiring).
		if floater_director != null:
			floater_director.vision_system = null
	if show_ui:
		if hud_root != null:
			hud_root.compose(self)
		_wire_hud_floater_anchor()
		_wire_gained_modifier_toast()
		# Container layout (HeroSigilCard's MarginContainer/VBoxContainer chain)
		# is resolved via a queued `sort_children`, which hasn't flushed yet this
		# far into the same synchronous _ready — Controls still report their
		# pre-layout (0,0)-ish rects. `start_turn` below fires synchronously and
		# can trigger a same-frame XP gain toast at the Hero Sigil Card's
		# FloatAnchor; reading its position before layout settles popped that
		# toast at the viewport's top-left corner instead of the card. One frame
		# is enough for the deferred sort to flush.
		await get_tree().process_frame
	else:
		$UI.visible = false

	# EVERY role opens here now (#715), and the reason the host and offline always
	# did is finally the reason on the joining side too: opening after
	# `_setup_level` means a command arriving the instant the link comes up finds
	# a world to apply to. Split from `_adopt_network_role` because the role has
	# to be known far earlier than the socket may open.
	#
	# [b]#667's drop latch stays, and its window is what changed.[/b] It used to
	# span the client's whole procgen — seconds, with a socket up and no world.
	# It now spans the ONE round trip between adopting the link on the next line
	# and the resync landing: this peer's world is empty until the pull answers,
	# and a `KIND_COMMAND` that arrives meanwhile would apply against nothing.
	# Narrower, not gone — the latch is still what makes the window safe rather
	# than merely short, because `apply_remote` enqueues and drains AT ONCE
	# against whatever world is there. If the command's ids do not resolve,
	# `CommandApplier._validate` warns and DROPS it. If they DO resolve, nothing
	# warns at all and it lands on whatever node happens to carry that
	# `stable_id`. Silence here is not evidence that nothing went wrong.
	#
	# Either way it is survivable for exactly one reason, and it is the last line
	# of this block: `pull_host_world` asks the authority for its whole world, and
	# the reply carries the authority's whole state, superseding both shapes above
	# — what this peer missed and what it misapplied alike. Ordering makes it
	# airtight rather than probable — `Wire._receive` is an `@rpc(..., "reliable")`,
	# so it is ordered as well as delivered: the host encodes the resync when the
	# request arrives, and anything it applies after that is sent after the
	# envelope and lands on top of it. Nothing this window swallowed can outlive
	# the pull.
	#
	# So the gate is not a buffer, it is the repair — and `pull_host_world` must
	# stay on this line, immediately after the link is up. Moving it later (behind
	# a fade, an await, a turn start) reopens the hole this comment is about.
	if _is_network_client() and command_link != null:
		command_link.defer_until_resync = true
	_open_link()
	pull_host_world()
	# And then WAIT for the answer, on the joining side only (#715). Before this,
	# a client had a world of its own — the wrong one, but a populated one — so
	# everything below could run against it and the pull repaired it a moment
	# later. It no longer has one: its graph is empty until the resync lands, and
	# arming [VictorySystem], starting a turn or lifting the curtain over nothing
	# is not "a bit early", it is a level with no map. This await IS what the
	# client's loading bar has been covering since `_setup_level` — the host's
	# generate and ship, rather than this machine's own procgen.
	#
	# Unbounded on purpose, and safe because somebody else bounds it:
	# [SceneDirector] shows a screen after [constant
	# SceneDirector.REVEAL_TIMEOUT_S] regardless, and `_reveal_ready` staying
	# false is the honest report that this peer never got a world. A timeout that
	# gave up and started a turn on an empty graph would be worse than a wait.
	if _is_network_client() and command_link != null:
		await command_link.resync_applied
	# #667, second half. The world now exists on EVERY path — offline, host and
	# client alike — so the run may be judged. Before this line a death (from
	# the network window above, or from anything else that can fire during
	# generation) would let `LastCampStandingCondition` read a
	# partially-populated entity group, see one camp standing, and latch an
	# outcome that can never be un-fired. Deliberately not a network concept:
	# the same one line arms it for a solo sandbox.
	if victory_system != null:
		victory_system.world_ready = true

	_announce_first_turn_for_rung_3()
	if auto_start_turn and player != null and turn_manager != null:
		# Skip the initial tick race: fill the player's clock so they act first.
		# (start_turn clears the ready-group membership this would otherwise set.)
		if player.stat_board != null and player.stat_board.initiative != null:
			player.stat_board.initiative.restore_to_full()
		turn_manager.start_turn(player)
	_focus_camera_on_player()
	# LAST. Everything above is what "presentable" means: the world generated,
	# the HUD composed, the camera already on the player (`request_focus` with a
	# 0s duration snaps, so nothing slides in under a lifting curtain). Only now
	# does the screen come back — see [method is_reveal_ready].
	_reveal_ready = true
	if SceneTransition.is_curtain_up():
		await SceneTransition.fade_in()


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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lobby="):
			return arg.trim_prefix("--lobby=")
	return ""


func _announce_first_turn_for_rung_3() -> void:
	var role := _rung_3_role()
	if role.is_empty() or turn_manager == null:
		return
	var announce := func(entity: Entity) -> void:
		print("[%s] rung 3: FIRST TURN — %s | %d nodes | %s | seat %d | %s" % [
			role,
			entity.display_name if entity != null else "<none>",
			graph.get_skill_nodes().size(),
			"authority" if command_link == null or command_link.mode != CommandLink.Mode.MIRROR
					else "mirror",
			seat_policy.seated_entity_id,
			WorldFingerprint.describe(graph),
		])
	turn_manager.turn_started.connect(announce, CONNECT_ONE_SHOT)


## The drain (#504, design B). An attack's world mutation is spread across a
## real interval, so a scene change mid-volley would strand every hit that had
## not landed yet — a world that is valid but permanently wrong. Draining here
## lands the rest synchronously, while the nodes involved are still alive.
func _exit_tree() -> void:
	if battle_system != null:
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


## #463: does this machine ADOPT its run, or DECIDE it?
##
## The one question the join path turns on, asked in one place. A client's
## lobby settings are a wish, not a run: `GameSession.apply_received` replaces
## its [RunConfig] and its whole [ParticipantRoster] with the host's, so
## everything this machine builds must wait for that message. Offline play and
## the host both answer false and take the untouched pre-#463 path.
func _is_network_client() -> bool:
	var net: NetworkConfig = GameSession.network
	return (net != null and net.is_online()
			and net.role == NetworkTransport.Role.CLIENT)


## #463/#715: how a joining client gets a world at all. It does not generate one
## — it asks the authority for the serialized one, through the [constant
## CommandLink.KIND_RESYNC] envelope #561 already ships: entities, graph, then
## the entity->node pass, in one message.
##
## [b]#715 made this the ONLY way a client gets a map, and that closed a
## window.[/b] Until then the client generated from the host's seed and pulled on
## top, because generating from a seed is not the same as playing the host's map
## (`procgen/` leans on transcendentals whose last bit is not portable across two
## platforms' libm, #547). So there was a period where the link was up and a
## WRONG world was present. There is no longer: the client builds nothing, and
## `#689`/`#706`'s `pow()` in the seeded draw leaves the LAN critical path with
## it, because nothing on this machine re-derives the map.
##
## [b]A pull, not a push, and that is the whole ordering answer.[/b] A push
## races the level's own construction — over a loopback it lands INSIDE
## `_on_run_setup`, before the level has spawned anything at all. Asking once
## the level is built has no such window, and needs no upward "I am ready"
## message: [method CommandLink.request_resync] IS that message.
##
## [b]The reply's internal order is load-bearing, and it serves BOTH shapes.[/b]
## [method CommandLink._on_resync] decodes entities, decodes the graph, THEN
## resolves the entity->node refs. On the join path the graph is EMPTY, which is
## the #533 harness's old odd case and is now the primary one. On a mid-run
## repair (#521/#560/#561) it is POPULATED, and the order is what stops
## [method EntitySnapshot.resolve_graph_refs] resolving every `core_location`
## against nodes [method GraphSnapshot.decode] is about to delete. One order,
## both shapes — which is the reason this is a resync pull and not the two
## pushed snapshots `scenes/dev/mp_procgen_sandbox.gd` sends in the opposite
## order. Anyone "fixing" this to match the harness's order will reintroduce the
## bug; `test_graph_snapshot.gd` pins both shapes.
func pull_host_world() -> void:
	if command_link == null or not _is_network_client():
		return
	command_link.request_resync("join: adopting the host's world", true)


## Half one of bringing the wire up (#531): tell the link which side of it we
## are on. [member CommandLink.mode] is the single writer of
## [member CommandApplier.is_authority], so this one assignment is also what
## decides whether this machine DECIDES or is TOLD.
##
## [b]A no-op unless the menu set a role[/b], which is what keeps offline play
## unchanged and what lets `scenes/dev/mp_dev_sandbox.gd` keep driving its own
## link off the command line — the harness never populates
## [member GameSession.network], so nothing here touches the authority flag it
## set by hand a moment earlier.
func _adopt_network_role() -> void:
	if command_link == null:
		return
	var net: NetworkConfig = GameSession.network
	if net == null or not net.is_online():
		return
	command_link.mode = (CommandLink.Mode.BROADCAST
			if net.role == NetworkTransport.Role.HOST
			else CommandLink.Mode.MIRROR)


## Half two: open the socket on whatever transport this level mounted.
##
## [b]GameRoot never picks the transport CLASS.[/b] It brings up the node at the
## fixed path (see [member transport]) in the role it was handed, and a level
## authored for real play swaps that node's script for [EnetTransport] —
## `scenes/level.tscn` does, the same way the harness does. Asking
## a [LoopbackTransport] to host is therefore not an error here; it announces
## itself and links to nobody, which is exactly what a level that never meant to
## be networked should do.
func _open_link() -> void:
	if command_link == null or transport == null:
		return
	var net: NetworkConfig = GameSession.network
	if net == null or not net.is_online():
		return
	# #554: both roles want the joining peer's id — the host to stamp its roster,
	# the client to learn its own. Connected before the socket opens so no
	# connection can beat the listener.
	transport.peer_joined.connect(_on_peer_joined)
	match net.role:
		NetworkTransport.Role.HOST:
			# The hello is what produces the in-sync / DIVERGED verdict, and it
			# has to wait for a peer — `start_host` only opens a socket.
			transport.link_changed.connect(_greet_if_linked)
			transport.start_host(net.port)
		NetworkTransport.Role.CLIENT:
			transport.start_client(net.address, net.port)


## Host-side: announce our world to each peer as it arrives. `link_changed`
## fires for disconnects too, hence the [method NetworkTransport.is_linked]
## gate rather than greeting on every status line.
func _greet_if_linked(_status: String) -> void:
	if transport != null and transport.is_linked() and command_link != null:
		command_link.send_hello()


## #554: a peer arrived. On the lobby path everything about that has ALREADY
## happened — the socket was opened by the menu (#714), the joiner's seat was
## stamped there, and its id reached [GameSession] there too. What survives here
## is the belt-and-braces restatement of both facts for a peer that arrives while
## a level is up, and the replayed join [method EnetTransport._adopt_live_link]
## fires for a peer that was already on the socket when this level adopted it.
##
## [b]It no longer sends the run's shape, and that is #715's core subtraction.[/b]
## This was `run_setup`'s only sender, and it fired off a
## [signal NetworkTransport.peer_joined] that a PRE-ESTABLISHED link never fires
## again — so a level that adopted the lobby's socket would sit waiting for a
## message nobody would ever send. START broadcasts it from the lobby instead,
## once, over the live link ([method LobbyScreen._on_run_started]).
func _on_peer_joined(peer_id: int) -> void:
	var net: NetworkConfig = GameSession.network
	if net == null:
		return
	if net.role == NetworkTransport.Role.CLIENT:
		GameSession.local_peer_id = transport.local_peer_id()
		return
	LobbyScreen.stamp_pending_remote(GameSession.roster, peer_id)
	# And ship this peer the world (#715). Host-side this line runs at the tail of
	# `_ready`, so the world is COMPLETE — `_open_link` is the last thing before
	# it, and [method EnetTransport._adopt_live_link] replays the join for a peer
	# that was already on the socket, which on the lobby path is every peer.
	#
	# [b]Why a push as well as the client's pull.[/b] They race, and neither wins
	# alone. A client's level is up in milliseconds (it generates nothing) while
	# the host spends 5-10 seconds on procgen — so `request_resync` arrives while
	# the host's level has not yet adopted the link, `Wire` emits it to nobody,
	# and it is silently dropped. Conversely this push lands on nothing if the
	# client's level is the slower one.
	#
	# [b]And when BOTH legs land, the world is applied ONCE.[/b] Both are flagged
	# [constant CommandLink.KEY_JOIN] (the flag rides the request through
	# `_on_resync_request`, so the answer carries it too) and the client's
	# `_join_world_arrived` latch drops the loser outright rather than decoding a
	# whole world it already holds. `_awaiting_resync` stops it asking twice.
	# `CommandLink._on_resync`'s guard is where that is argued, including why it
	# keys off the flag rather than off a fingerprint compare — a mid-run repair
	# (#521/#560/#561) must still apply even when the fold agrees.
	#
	# The old warning against pushing from here does not survive #715: it said a
	# graph snapshot would "decode into a graph that is about to be generated
	# over", and the joining peer no longer generates anything.
	if command_link != null:
		command_link.send_resync(
				"join: the peer is on the link and has no world", true)


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
## corpse somehow held the turn, clear `current_entity` so the loop isn't
## stalled on an actor that's about to disappear.
func _pull_from_turn_loop(entity: Entity) -> void:
	entity.remove_from_group(Entity.GROUP)
	entity.remove_from_group(Entity.READY_GROUP)
	if turn_manager != null and turn_manager.current_entity == entity:
		turn_manager.current_entity = null


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
	if hud_root != null:
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


## Attaches a default [EntityController] child to any [Entity] in the level
## that doesn't already have one: [PlayerController] where [member
## Entity.is_human_controlled] is set, [AIController] otherwise. No-op if the
## scene/code already wired a controller — explicit composition always wins.
##
## Reads [member Entity.is_human_controlled] rather than comparing identity
## against [member player] — that authored-per-entity flag is what
## [method apply_roster] sets from a [Participant]'s kind, and it's also what
## a hand-authored scene (dev_sandbox) sets directly on its `%Player` node.
## #475: this is the seam that stops assuming "the player" is singular.
func _ensure_controllers() -> void:
	for node in get_tree().get_nodes_in_group("entities"):
		var ent := node as Entity
		if ent == null:
			continue
		if _find_controller(ent) != null:
			continue
		var ctrl: EntityController
		if ent.is_human_controlled:
			ctrl = PlayerController.new()
			ctrl.name = "PlayerController"
		else:
			ctrl = AIController.new()
			ctrl.name = "AIController"
		ent.add_child(ctrl)


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


static func _find_controller(ent: Entity) -> EntityController:
	for child in ent.get_children():
		if child is EntityController:
			return child as EntityController
	return null


## Subclass hook. Default = pick up an existing `%Player` node from the scene
## (dev_sandbox shape). Procgen sandboxes override to run generation + spawn
## entities, then assign `self.player`.
func _setup_level() -> void:
	if false: await get_tree().process_frame # include fake `await` to make godot see this as a coroutine
	if has_node("%Player"):
		player = get_node("%Player") as Entity


## Spawn an [Entity] under `graph.entities_container` with a duplicated copy
## of the default stat board. If [param core_location] is given, force-allocates
## it as the entity's first node and sets `core_location`. If [param core_class]
## is given, assigns it as `core_class` so its modifier set + on_turn_started
## hook fire from Entity._ready. Returns the entity.
##
## Skips [method AllocationSystem.allocate] gating — this is dev/procgen
## setup, not a gameplay action. Mid-game spawning should still route through
## the gated path.
func spawn_entity(
	ent_name: String,
	color: Color,
	core_location: SkillNode = null,
	core_class: CoreClass = null,
	with_ai: bool = false,
) -> Entity:
	var ent := preload("res://entity/entity.tscn").instantiate() as Entity
	ent.name = ent_name
	ent.display_name = ent_name
	ent.color = color
	ent.core_class = core_class
	graph.entities_container.add_child(ent)
	if core_location != null:
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
	if with_ai:
		var ai := AIController.new()
		ai.name = "AIController"
		ent.add_child(ai)
	return ent


## Spawn a removable blocker entity (#300) owning [param core_location]. A
## blocker is a plain [Entity] — no controller, no [CoreClass] — whose tiered
## board ([param size] → CON/armor/health, no initiative) and the size's
## spellbook are authored under `entity/blocker/`. Parents under
## `graph.entities_container` and force-allocates the core, exactly like
## [method spawn_entity] (procgen setup, not a gameplay action). Returns the
## entity, with [member Entity.entity_tier] set to size + 1 (1/2/3).
## Spawn one Dormant Core of [param size] onto [param core_location].
##
## [param spell_prune_m] is the #586 loot-book prune's shape parameter (see
## [method SpellBook.duplicate_pruned]); leaving it at `0.0` keeps the tier's
## authored book whole, which is what a hand-authored level or a fixture
## wants. [param spell_prune_seed] seeds that prune — procgen hands one out
## per placement, because every peer re-runs this and must land on the same
## book. The prune copies before it pops — the tier books are `preload`ed
## resources shared by every blocker of a size, so popping in place would
## strip the tier for the rest of the run.
##
## [param preassigned_id] adopts an [Entity] id decided elsewhere instead of
## letting [Graph] mint one (#715) — the authority's, when a snapshot is
## rebuilding a blocker on a peer that ran no procgen. `0`, the default, is
## every ordinary caller and mints as before.
func spawn_blocker(size: BlockerSize, core_location: SkillNode,
		spell_prune_seed: int = 0, spell_prune_m: float = 0.0,
		preassigned_id: int = 0) -> Entity:
	var ent := _BLOCKER_SCENE.instantiate() as Entity
	# Before `add_child`: `Graph._mint_entity_id` assigns only to an entity whose
	# id is still 0, so stamping first is adoption rather than a second mint.
	ent.entity_id = preassigned_id
	ent.name = "Blocker_%s" % BlockerSize.keys()[size].to_lower()
	# #587 — the player-facing name is "Dormant Core", never "Blocker": these
	# are single-node entities that hold a node but never move or act, and
	# `blocker` is the mechanic, not the thing. The node NAME stays `Blocker_*`
	# so scene-tree lookups and the group are untouched; only `display_name`
	# reaches a tooltip.
	ent.display_name = "Dormant Core (%s)" % BlockerSize.keys()[size].capitalize()
	ent.entity_tier = int(size) + 1
	ent.stat_board = _BLOCKER_BOARDS[size] as EntityStatBoard
	var book := _BLOCKER_SPELLBOOKS[size] as SpellBook
	if spell_prune_m > 0.0:
		var prune_rng := RandomNumberGenerator.new()
		prune_rng.seed = spell_prune_seed
		book = book.duplicate_pruned(prune_rng, spell_prune_m)
	ent.spellbook = book
	graph.entities_container.add_child(ent)
	if core_location != null:
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
	return ent


## Rebuild an [Entity] an arriving snapshot names and this peer does not have
## (#715) — [member CommandLink.entity_spawner]'s one production implementation.
##
## [b]Only a BLOCKER, and refusing anything else is the point.[/b] Since #715 a
## joining client runs no procgen, so the entities procgen spawns that the roster
## never names — one per removable blocker (#477), ~120 on the shipped preset —
## have no other way to exist here, and their nodes would otherwise decode as
## unowned and move the ownership fold. Every OTHER entity is the roster's, and
## the roster spawns the same set on every peer by construction
## ([method ProcgenPlaySandbox._seat_the_roster]): a row asking for one of those
## means the two peers disagree about who is playing, which is a fault to
## surface, not to paper over by inventing a hero.
##
## The tier is what names the size — [method spawn_blocker] writes
## `entity_tier = size + 1` — and everything else the blocker needs (its tiered
## [EntityStatBoard], its scene, its `scenery` group) comes from that same call,
## which is exactly why this lives here and not in [EntitySnapshot].
##
## [b]The #586 PRUNED spellbook crosses by value (#726).[/b] The tier book this
## assigns is the WHOLE authored one; the host's is a `duplicate_pruned` slice
## of it, with no `resource_path` to intern. [method EntitySnapshot._decode_identity]
## overwrites what this hands out with a fresh book rebuilt from the row's
## [member SpellDef.id] list, so nothing here needs to know about the prune.
func spawn_snapshot_entity(
	entity_id: int, scene_path: String, tier: int, _display_name: String
) -> Entity:
	if scene_path != _BLOCKER_SCENE.resource_path:
		push_warning(
			"GameRoot: snapshot names entity %d from '%s', which is not a blocker — "
			% [entity_id, scene_path]
			+ "the roster should have spawned it. Refusing to invent one.")
		return null
	var size := clampi(tier - 1, 0, BlockerSize.size() - 1) as BlockerSize
	return spawn_blocker(size, null, 0, 0.0, entity_id)


## The authority's world has landed (#715). Anything [method spawn_snapshot_entity]
## built arrived after the level's own pass, so give it a controller and put the
## fog back on this machine's real subgraph — the seat's vision was derived from
## a player that owned nothing at the time.
func _on_resync_applied(_reason: String) -> void:
	_ensure_controllers()
	_apply_seat_vision()
	if vision_system != null:
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
## world-space core. No-op if the HUD isn't composed (show_ui == false) or
## the player hasn't resolved yet.
func _wire_hud_floater_anchor() -> void:
	if floater_director == null or hud_root == null or player == null:
		return
	if hud_root.hero_sigil_card == null:
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
	if allocation_system == null or hud_root == null or player == null:
		return
	if hud_root.hero_sigil_card == null or hud_root.gained_modifier_toast == null:
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

	if camera != null:
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
	else:
		# No camera (e.g. an embedded showcase) — nothing will ever fire
		# `bounds_changed`, so fall back to the static zoom==1.0 rect directly.
		_on_camera_bounds_changed(baseline_bounds)


## Mirrors GraphCamera's zoom-scaled pan limit onto the fog/aura overlays so
## all three always agree on how far past the graph edge is visible.
func _on_camera_bounds_changed(bounds: Rect2) -> void:
	if fog_overlay != null:
		fog_overlay.bounds = bounds
	if aura_overlay != null:
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
	# `_on_resync_applied` -> `bind_player` is not what re-points it; the turn
	# start that follows the world's arrival is.
	var target: Vector2 = (player.core_location.global_position
			if player.core_location != null else Vector2.ZERO)
	if camera_director != null:
		camera_director.request_focus(FocusRequest.point(target, 0.0, true, &"handover"))
		return
	if camera != null:
		camera.position = target
