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
	# [method spawn_snapshot_entity]. Set here, before any link can be up, because
	# the first thing a joining client does with its link is ask for that world.
	command_link.entity_spawner = spawn_snapshot_entity
	# The session owns the wire's lifecycle; the root keeps the presentation of
	# each event (#1004). The world-arrived hook re-runs `_ensure_controllers`
	# for entities the resync brought with it — idempotent and cheap.
	network_session.world_ready.connect(_on_world_ready)
	network_session.refused.connect(_present_link_end)
	network_session.link_lost.connect(_present_link_end)
	network_session.seat_handover.connect(_on_seat_handover)
	network_session.peer_left.connect(_on_seat_vacated)
	network_session.local_peer_resolved.connect(_on_local_peer_resolved)
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


## Rescale every initiative-carrying entity's opening clock across (0, cap] so
## the first cycle interleaves turns instead of every entity opening at 0 and
## the tie-break deciding the whole order every cycle (#911).
##
## Runs BEFORE [method _open_first_turn], and unconditionally — never gated on
## [method NetworkSession.is_authority]. This has to be a pure function of shared
## data (spawn order) so every peer reaches the same clocks independently,
## exactly like world generation itself; it is not a host DECISION a peer
## receives. What [method _open_first_turn] gates is only who SUBMITS the
## opening [StartTurnCommand] — that command's own validator
## (`CommandApplier._validate_command`) doesn't look at initiative at all, so
## this only reshapes who acts SECOND onward, never who opens turn 1.
##
## [b]Index 0 is already the entity [method _opening_entity] names[/b] —
## `carriers` is built by walking `graph.entities_container` in spawn order,
## and roster index 0 heads that spawn order (#923, owner call on #911:
## "spawn order. which should be identical to roster order (player1,
## player2, ..., AI1, AI2, ...)"): [method
## ProcgenPlaySandbox._camp_grouped_participants] spawns camp-bucketed, in
## [method ParticipantRoster.camps]' first-appearance order, so roster[0]'s
## camp is bucket 0 and roster[0] heads it. No reordering needed.
##
## Blockers (no `initiative` pool) are not counted in `n` and are untouched.
func _stagger_initiative() -> void:
	if graph == null:
		return
	var stagger := true
	if GameSession.is_active():
		stagger = GameSession.config.stagger_initiative
	if not stagger:
		return
	var carriers: Array[Entity] = []
	for child in graph.entities_container.get_children():
		var e := child as Entity
		if e != null and e.stat_board != null and e.stat_board.initiative != null:
			carriers.append(e)
	GameRoot.apply_initiative_stagger(carriers)


## The entity the opening [StartTurnCommand] will name: the initiative-carrying
## entity at spawn index 0 (#923, owner call on #911 — spawn order heads
## roster order, for offline, couch and remote alike; see [method
## _stagger_initiative]'s note on why index 0 coincides with roster[0]). No
## peer-id lookup: the entity a joined client happens to be host of is
## irrelevant here, and deriving the same "who opens" fact a second way —
## off a peer id rather than off spawn order directly — is exactly what
## #923 retired ([method _stagger_initiative]'s old reorder-by-opener step,
## and the `test_host_seat_ranks_first_even_when_spawned_second` test that
## pinned it).
##
## Walks `graph.entities_container` directly rather than reusing [method
## _entity_for_participant] — that one reads `get_tree()`, which only a node
## actually inside the scene tree has; this runs from `_ready()` (always
## true there) but is also exercised standalone against a bare, unparented
## [GameRoot] in `test_initiative_stagger.gd`, and `graph` alone is enough
## data either way. Null when there's no graph to ask.
func _opening_entity() -> Entity:
	if graph == null:
		return null
	for child in graph.entities_container.get_children():
		var e := child as Entity
		if e != null and e.stat_board != null and e.stat_board.initiative != null:
			return e
	return null


## The pure half of [method _stagger_initiative] — split out so it is
## testable against a hand-built roster with no [Graph] / [GameRoot] scene at
## all. `carriers` is spawn-ordered (index 0 = first spawned); index `i` of
## `n` opens at `floor(cap * (n - i) / n)` — first = cap (ready at once, no
## initial tick race to win), last = `cap / n`, never 0. Written through
## [method PoolStat.set_current] (never `base_value` — this is a `current`
## write, not a redefinition of the pool).
static func apply_initiative_stagger(carriers: Array[Entity]) -> void:
	var n := carriers.size()
	if n == 0:
		return
	for i in n:
		var pool := carriers[i].stat_board.initiative
		var cap := float(pool.get_value())
		pool.set_current(floor(cap * float(n - i) / float(n)))


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
	# #923 (owner call on #911): the entity that opens is [method
	# _opening_entity]'s answer where there's a graph to ask — spawn/roster
	# index 0, the same rule offline, couch and remote alike. `player` is a
	# fallback for a hand-authored fixture with no session/graph at all,
	# and the ordinary one-local-human case where `_opening_entity` and
	# `player` already agree. On a couch/hot-seat authority seating >=2 local
	# humans, `player` is whichever one `_seat_the_roster`'s loop happened to
	# assign LAST — `_opening_entity` is the settled reading there too.
	var opener := _opening_entity()
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
	# ([method hand_seat_to_ai]), and doing that from inside `turn_started`
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
			hand_seat_to_ai(p)
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


## Host-side: a seated peer left mid-run. Every HUMAN seat it held goes to the
## AI ([method hand_seat_to_ai]) so the run goes on for everyone still here.
func _on_seat_vacated(peer_id: int) -> void:
	if GameSession.roster == null:
		return
	for p in GameSession.roster.all():
		if p.kind == Participant.Kind.HUMAN and p.peer_id == peer_id:
			hand_seat_to_ai(p)
## The HOST's half of "this seat is the AI's now" — the authority-only parts,
## on top of the [method _adopt_seat_handover] every peer runs.
##
## The broadcast (#755) goes out BEFORE the turn kick, and that order is
## load-bearing: the wire is reliable-ordered, so sequencing the handover ahead
## of the AI's first command is what stops a mirror seeing an AI act on a seat
## it still believes a human holds.
##
## The entity half swaps the no-op [PlayerController] for an [AIController].
## If it is this hero's turn RIGHT NOW the new controller missed
## `turn_started`, and the human who would have ended the turn is gone — so the
## turn is kicked by hand. Fire-and-forget, as [method EntityController._on_turn_started]
## calls it. This half is the host's ALONE: a mirror that grew an
## [AIController] of its own would be a second machine deciding actions for a
## hero it has no authority over, which is the whole of
## `.claude/rules/multiplayer-sync.md` broken in one line.
func hand_seat_to_ai(participant: Participant) -> void:
	var ent := _adopt_seat_handover(participant)
	command_link.send_seat_handover(participant.id)
	if ent == null:
		return
	var ai := _find_controller(ent) as AIController
	if ai == null:
		var old := _find_controller(ent)
		if old != null:
			# Detached NOW, not only queued: `_find_controller` walks children
			# in order and a still-parented PlayerController would keep winning
			# until the frame's free flush.
			ent.remove_child(old)
			old.queue_free()
		ai = _new_ai_controller(ent)
		ent.add_child(ai)
	if turn_manager.current_entity == ent:
		ai.take_turn()


## Mirror-side entry for the same handover, off
## [signal CommandLink.seat_handover_received] (#755). Applies the shared half
## and nothing else — see [method hand_seat_to_ai] for why the controller swap
## must not follow it here.
func _on_seat_handover(participant_id: int) -> void:
	if GameSession.roster == null:
		return
	var participant := GameSession.roster.by_id(participant_id)
	if participant == null:
		return
	_adopt_seat_handover(participant)


## What EVERY peer does when a seat passes to the AI, host and mirror alike.
## Returns the seat's [Entity], or null if this peer has none for it.
##
## [b]The roster half comes first[/b], and matters beyond the controller:
## [method LootPickRegistry.is_remote_collector] reads [member Participant.kind],
## and a HUMAN seat whose peer is gone would park every relic this hero claims
## on a pick that never comes (#646) — a second hang behind the first.
##
## [b]The flag half is why this crosses the wire at all[/b] (#755). Until then
## the host flipped [member Entity.is_human_controlled] alone and every mirror's
## copy stayed `true` — but [method SeatPolicy.vision_group] is an ALLIED-HUMANS
## reveal keyed on exactly that flag, so a coop ally on a third machine went on
## seeing through a hero the host had already stopped sharing with. Fog is
## local-view-only, so this was never a desync of the authoritative world; it
## was two machines drawing different maps of it, which is worse to play with
## and impossible to notice from a fingerprint.
##
## [method _apply_seat_vision] is re-run explicitly because that group is
## COMPUTED, not reactive: flipping the flag without it leaves the stale fog in
## place until something else happens to recompute.
func _adopt_seat_handover(participant: Participant) -> Entity:
	participant.kind = Participant.Kind.AI
	var ent := _entity_for_participant(participant.id)
	if ent == null:
		return null
	ent.is_human_controlled = false
	_apply_seat_vision()
	# ...but NOT the announcement, when the handover was asked for rather than
	# forced (#754). `--autoplay` hands both seats over on purpose and nobody
	# left; a HUD crying that somebody did would be the harness lying about the
	# very run it is checking. Read from the flag rather than passed down as an
	# argument because this method is also the MIRROR's entry
	# ([method _on_seat_handover]), which is told a seat changed hands and never
	# why — and both processes carry the flag.
	if not HarnessFlags.has(HarnessFlags.AUTOPLAY):
		hud_root.announce_peer_left(ent.display_name)
	return ent


func _entity_for_participant(participant_id: int) -> Entity:
	if participant_id == 0:
		return null
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var ent := node as Entity
		if ent != null and ent.participant_id == participant_id:
			return ent
	return null


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
			ctrl = _new_ai_controller(ent)
		ent.add_child(ctrl)


## The one place an [AIController] is built. Its tier is the seat's
## [member Participant.ai_tier], looked up in [member GameSession.roster] by
## [member Entity.participant_id]; with no roster or no matching seat (a
## hand-authored sandbox) the controller keeps [constant AIController.DEFAULT_TIER].
## Nothing else in production writes [member AIController.ai_tier].
func _new_ai_controller(ent: Entity) -> AIController:
	var ai := AIController.new()
	ai.name = "AIController"
	if GameSession.roster != null and ent.participant_id != 0:
		var seat := GameSession.roster.by_id(ent.participant_id)
		if seat != null:
			ai.ai_tier = seat.ai_tier as AIController.Tier
	return ai


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
		ent.add_child(_new_ai_controller(ent))
	return ent


## Spawn a removable blocker entity (#300) owning [param core_location] and
## [param footprint]. A blocker is a plain [Entity] — no controller — whose
## tiered board ([param size] → CON/armor/health, no initiative) and the size's
## spellbook are authored under `entity/blocker/`.
##
## [b]The #777 falloff aura is NOT granted here.[/b] `blocker_entity.tscn`
## authors `core_class = blocker_core.tres`, whose `effects` array carries it,
## so [method Entity._ready] grants it on `add_child` below — the ordinary
## entity-wide effect seam, reached with no code. That class is deliberately
## not a pickable one: `pickable_in = 0`, absent from `core_class_roster.tres`,
## and filed under `entity/blocker/` rather than `entity/core/`.
##
## The aura is inert on a footprintless blocker — [ProportionalScale] puts the
## source itself at scale 0, so a lone core is the only node in scope and takes
## nothing. It is also inert at grant time on the [method spawn_snapshot_entity]
## path, which spawns with a null core; the snapshot's later `core_location`
## assignment is what fills it, since that setter dispatches `_on_core_moved`
## (a full recompute — see [member Entity.core_location]). Parents under
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
##
## [param stake_level] is the #916 pre-stake (1..[constant
## AllocationSystem.STAKE_CEILING], procgen rolls it per placement): the core
## node's cap is stamped, `force_allocate` opens the 0→1 as usual, and
## [method AllocationSystem.force_fill] walks the fill to the cap — no SP
## minted for the fill, so the blocker's pool never says it bought it. A
## staked kill then frees a node already filled to 3, SP the killer never
## spent, so the kill XP is offset by a MULTIPLY on `core_kill_xp` clamped to
## `blockers_cfg.stake_xp_offset_floor` (owner's formula on #784; every input
## is a live board read). Only the CORE is staked, never the footprint. The
## snapshot adoption path ([method spawn_snapshot_entity]) leaves it at 1 and
## passes no core, so the row's own `stake_level`/`allocation_level` land
## untouched by anything here.
func spawn_blocker(size: BlockerSize, core_location: SkillNode,
		footprint: Array[SkillNode] = [], spell_prune_seed: int = 0,
		spell_prune_m: float = 0.0, preassigned_id: int = 0,
		stake_level: int = 1, stake_xp_offset_floor: float = 0.25) -> Entity:
	var ent := _BLOCKER_SCENE.instantiate() as Entity
	# Before `add_child`: `Graph._mint_entity_id` assigns only to an entity whose
	# id is still 0, so stamping first is adoption rather than a second mint.
	ent.entity_id = preassigned_id
	ent.name = "Blocker_%s" % BlockerSize.keys()[size].to_lower()
	# #587 — the player-facing name is "Dormant Core", never "Blocker": these
	# hold a patch of territory but never move or act, and `blocker` is the
	# mechanic, not the thing. The node NAME stays `Blocker_*`
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
		var stake := clampi(stake_level, 1, AllocationSystem.STAKE_CEILING)
		# Cap BEFORE the allocate: the fill is clamped to the cap, and the
		# stake_level setter re-derives the radius the halo reads.
		core_location.stake_level = stake
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
		if stake > 1:
			allocation_system.force_fill(core_location, stake)
			_offset_kill_xp_for_stake(ent, stake, stake_xp_offset_floor)
		# The core FIRST, then the bonus nodes: `force_allocate` is the setup
		# primitive, so nothing here checks adjacency — but the footprint is
		# grown connected at placement time and the class's falloff aura measures
		# hops over the owned subgraph, which only reads right with the core in it.
		for node in footprint:
			if node != null and node != core_location:
				allocation_system.force_allocate(ent, node)
	return ent


## The #916 kill-XP offset for a pre-staked blocker, owner's formula verbatim
## (#784): `core_kill_xp × clamp(1 − (stake − 1) · XP_PER_SP / core_kill_xp,
## floor, 1)` with `XP_PER_SP = xp.value / sp_gain_on_levelup.value` — what one
## SP is worth in XP on THIS blocker's board, so the freed fill is priced in
## the board's own currency and no literal number lives here. Granted as a
## core modifier: per-entity (the board is duplicated at `initialize`), and
## it rides [EntitySnapshot] with the rest of them.
func _offset_kill_xp_for_stake(ent: Entity, stake: int, floor_: float) -> void:
	var board := ent.stat_board
	if board == null or board.core_kill_xp == null or board.xp == null \
			or board.sp_gain_on_levelup == null:
		return
	var sp_gain: float = board.sp_gain_on_levelup.value
	var kill_xp: float = board.core_kill_xp.value
	if sp_gain <= 0.0 or kill_xp <= 0.0:
		return
	# `Stat.value` is Variant-typed — cast, or an int/int pair divides as ints.
	var xp_per_sp: float = float(board.xp.value) / sp_gain
	var m := StatModifier.new()
	m.stat_id = &"core_kill_xp"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = clampf(1.0 - float(stake - 1) * xp_per_sp / kill_xp, clampf(floor_, 0.0, 1.0), 1.0)
	ent.grant_core_modifier(m)


## Rebuild an [Entity] an arriving snapshot names and this peer does not have
## (#715) — [member CommandLink.entity_spawner]'s one production implementation.
##
## [b]Only a BLOCKER, and refusing anything else is the point.[/b] Since #715 a
## joining client runs no procgen, so the entities procgen spawns that the roster
## never names — one per removable blocker (#477), 50 on the shipped preset since
## #777's density rebalance — have no other way to exist here, and their nodes
## would otherwise decode as
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
	# Empty footprint: on a joining peer every owned node arrives through
	# `GraphSnapshot`'s per-node `owner_id`, so there is nothing to allocate
	# here and nothing about the footprint to serialize (#777 decision 9).
	return spawn_blocker(size, null, [], 0, 0.0, entity_id)


## The authority's world has landed (#715, [signal NetworkSession.world_ready]).
## Anything [method spawn_snapshot_entity]
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
