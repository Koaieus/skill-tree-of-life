class_name MpHarness
extends Node
## The process-level harness `mise run mp:e2e` drives — rung 3 (both processes
## reach the same first turn) and rung 4 (`--autoplay`: the run plays itself to
## a verdict). Mounted always in `game_root.tscn`, inert unless
## [constant HarnessFlags.LOBBY] is set, so an ordinary launch, an exported
## build and the GUT suite print nothing and parse nothing. See
## `docs/domain/multiplayer-harness.md`.
##
## [b]Every hook connects in [method _ready][/b], which runs before GameRoot's
## (child first) and so before the link opens: a joiner whose level comes up
## AFTER the host's first turn gets that turn inside the resync (`adopt_turn`
## fires `turn_started` from within `_on_resync`), so a hook connected after
## the link's await misses the only turn start it was there to report
## (2026-09-06). Authority is read lazily inside each callback — the role is
## adopted by GameRoot's `_ready`, after this one.

## Entity-turns (NOT rounds — [member TurnManager.turns_taken] counts each
## entity's turn) an autoplay run may spend before it is declared a timeout.
## Two heroes on the smallest map settle in well under this; the number is a
## hang detector, not a balance claim, and `--max-turns=N` overrides it.
const _RUNG4_MAX_TURNS := 400

## Exit code a timed-out autoplay run quits with — distinct from the 1 the
## engine uses for its own failures, so the harness can tell "the run never
## ended" from "the process fell over".
const _RUNG4_TIMEOUT_EXIT := 2

## `--lethal`'s four SETs — the owner's bound (2026-09-30): "each could at most
## tank 3 node losses before dying". Tentative tuning, harness-only.
const _LETHAL_SETS: Dictionary[StringName, float] = {
	&"node_health": 1.0,
	&"health": 3.0,
	&"dealloc_damage": 1.0,
	&"core_healing": 0.0,
}
const _LETHAL_PRIORITY := 1000

@export var turn_manager: TurnManager
@export var graph: Graph
@export var network_session: NetworkSession
@export var seat_handover: SeatHandover

## Pushed by GameRoot after `_setup_level`, as it is to the camera, applier and
## battle system; read only when the rung-3 line prints.
var seat_policy: SeatPolicy = SeatPolicy.couch()


func _ready() -> void:
	var role := _rung_3_role()
	if role.is_empty() or turn_manager == null:
		return
	if HarnessFlags.has(HarnessFlags.LETHAL):
		arm_lethal()
	_announce_first_turn_for_rung_3(role)
	_arm_rung_4(role)


## `""` unless this process was launched by `meta_root`'s `--lobby=` driver —
## the same explicit flag `meta_root` reads.
static func _rung_3_role() -> String:
	return HarnessFlags.value(HarnessFlags.LOBBY)


## Prints, once, on the first turn this machine sees: which world it holds and
## whether it agrees with the other process.
##
## [b]On `turn_started`, not on the resync[/b], because "the first turn starts"
## IS acceptance 1. A client that decoded a world and then never got a turn has
## not proved the thing; the fingerprint beside it is what makes the pair
## comparable across two logs.
func _announce_first_turn_for_rung_3(role: String) -> void:
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


## Rung 4 (#754) keeps the rung-3 pair going to a VERDICT — the host hands every
## human seat to the AI, both ends print one greppable line when
## [signal Events.run_ended] fires, and both quit so `mise run mp:e2e` can
## compare the two logs and exit on the difference. Behind `--autoplay` on top
## of the rung-3 flag.
func _arm_rung_4(role: String) -> void:
	if not HarnessFlags.has(HarnessFlags.AUTOPLAY):
		return
	# Asked for, not forced: nobody left, so the handover is not announced —
	# on both processes, which are configured alike.
	if seat_handover != null:
		seat_handover.quiet = true
	Events.run_ended.connect(_announce_verdict_for_rung_4.bind(role), CONNECT_ONE_SHOT)
	var cap := HarnessFlags.number(HarnessFlags.MAX_TURNS, _RUNG4_MAX_TURNS)
	turn_manager.turn_started.connect(func(_e: Entity) -> void: _watch_turn_cap(role, cap))
	# Deferred out of the emission: the handover kicks the current entity's turn
	# ([method SeatHandover.hand_seat_to_ai]), and doing that from inside
	# `turn_started` would re-enter the turn loop underneath the signal that
	# started it.
	turn_manager.turn_started.connect(
			func(_e: Entity) -> void: _autoplay_on_authority.call_deferred(role),
			CONNECT_ONE_SHOT)


## A mirror needs nothing: its own hero is driven by the authority's confirmed
## commands, and a second AI deciding locally is exactly the divergence this
## run exists to detect. Read here, not at arming time, because the role is
## adopted after this node's `_ready`.
func _autoplay_on_authority(role: String) -> void:
	if network_session == null or not network_session.is_authority():
		return
	_autoplay_every_human_seat(role)


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
## [b]Nothing is awaited before the print.[/b] [method GameRoot._on_run_ended]
## routes to the meta-shell after [member GameRoot.run_end_route_delay], and
## routing tears this graph down — a fingerprint sampled after that would
## describe a world that no longer exists and mismatch its peer for a reason
## that is not a sync bug.
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


## Caps [param entity] at a few node losses (`--lethal`): nodes die to one hit,
## each node lost costs the core one HP of three, and the core never regenerates.
## SET modifiers, never `base_value` writes — `health` and `node_health` are
## derived from CON, and a SET is the value asked for
## (`docs/domain/stat-knobs-and-bins.md`). [constant _LETHAL_PRIORITY] outranks
## any core-class SET on the same stat.
##
## [b]Both processes apply it, to every entity as it enters the tree.[/b] The
## boards also cross by value on every resync; [method StatBoard.read_dict]
## reconciles against the full modifier form, so a mirror that already applied
## the same four holds the host's board exactly rather than two copies.
static func make_lethal(entity: Entity) -> void:
	if entity.stat_board == null:
		return
	for stat_id: StringName in _LETHAL_SETS:
		var m := StatModifier.new()
		m.stat_id = stat_id
		m.operation = StatModifier.Operation.SET
		m.value = _LETHAL_SETS[stat_id]
		m.priority = _LETHAL_PRIORITY
		entity.stat_board.add_modifier(m)


## Arms [method make_lethal] for every [Entity] that enters the tree from now on
## — heroes, blockers, and the ones a join snapshot spawns — once its own
## `_ready` has run, since [method Entity.initialize] applies the intrinsics and
## the core class there and the SETs must land on top of both. Tree-wide
## rather than on [member Graph.entities_container], which is an `@onready` of
## a sibling that may not have readied yet when this node's `_ready` runs.
func arm_lethal() -> void:
	get_tree().node_added.connect(_on_node_added_lethal)


func _on_node_added_lethal(node: Node) -> void:
	if node is Entity:
		node.ready.connect(make_lethal.bind(node), CONNECT_ONE_SHOT)
