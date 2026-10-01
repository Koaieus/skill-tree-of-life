class_name TurnManager
extends Node

## Turn-by-turn coordination. Owns:
##   - who currently has the turn (`current_entity`)
##   - initiative bookkeeping
##
## Per the GDD: initiative ticks until 100 → entity acts → end_turn deducts
## 100 initiative and the cycle resumes. A single implicit phase per turn:
## all per-turn budgets (AP / DP / SP / XP / mana / wound-heal / node-refill)
## replenish at `turn_started` and the entity spends them in any order until
## End Turn. Intent (allocate vs deallocate vs attack vs cast vs move-core) is
## disambiguated by INPUT CHANNEL, not by phase — see PlayerInputController.

signal ticked
signal turn_started(entity: Entity)

## A REAL turn begin only — emitted by [method start_turn] right after
## [signal turn_started], never by [method adopt_turn]'s resync cursor. For a
## listener whose state must advance once per turn actually served (scout-mark
## decay), where [signal turn_started] would double-count a repaired mirror.
signal real_turn_started(entity: Entity)
signal turn_ended(entity: Entity)
## A classic initiative round closed (#1257) — see [member rounds_completed].
## [param round] is the new [member rounds_completed]. Never emitted by
## [method adopt_turn]: a repair has no presentation semantics.
signal round_completed(round: int)

## Fires whenever [method forecast]'s answer could have changed: after
## `turn_started`, after `turn_ended`, and whenever any live entity's
## `initiative` pool or `initiative_speed` stat changes value. The HUD strip
## (#910) subscribes to this ONE signal and nothing else — never
## `initiative.current_changed` / `initiative_speed.value_changed` per entity,
## which would mean re-wiring on every spawn/death itself.
signal forecast_changed

## Whether the level opens the run's clock at all (#1006; the root's old
## `auto_start_turn`). False and [method GameRoot._open_first_turn] submits no
## opening [StartTurnCommand] — a showcase drives its own beat loop (and adopts
## the cursor via [method adopt_turn] for killer attribution), a `_setup_level`
## test never lets TurnManager/AI take over. Not an off state: the manager
## stays live for every turn something else starts, so this is a plain flag
## rather than the `enabled` convention.
@export var opens_first_turn: bool = true

## Scopes the initiative clock to the entities under this node. Null → every
## entity in the tree (the game: one world per tree). Set it wherever one tree
## holds several worlds — the editor's sandbox host instantiates every live tab
## at once, and an unscoped [method tick] replenishes every tab's entities, so
## [method end_turn] serves whichever foreign entity crosses first.
@export var entity_root: Node = null

## The entity currently taking its turn; null between turns.
##
## Written only by TurnManager (#1030): once the manager is ready an outside
## assignment `push_error`s and is ignored. Arrange a turn through the named
## entries — [method start_turn] opens a real one (readiness consumed,
## `turn_started` upkeep), [method adopt_turn] takes a cursor silently, the
## mirror's path. Reads stay `tm.current_entity`.
var current_entity: Entity = null:
	get:
		return _current_entity
	set(value):
		if is_node_ready():
			push_error("TurnManager.current_entity is written only by TurnManager"
				+ " — arrange a turn with start_turn(entity) or adopt_turn(entity, n)")
			return
		_current_entity = value

var _current_entity: Entity = null

## Turns served since the level started — every [method start_turn], across all
## entities, not rounds. [RunOutcome.turn_count] reports it (#460).
var turns_taken: int = 0
## Initiative rounds completed (#1257). A round OPENS with a roster — every
## living initiative carrier this clock serves — and COMPLETES when the turn of
## the last roster member still waiting ends; the next opens at once with a
## fresh roster. So a fast entity may act twice in one round, a mid-round joiner
## waits for the next roster, and a member that dies leaves the current one.
## Only turn ORDER matters: a uniform change to initiative gain changes no count.
##
## Bookkeeping lives at the [signal turn_ended] sites ([method end_turn],
## [method abandon_turn]), which [EndTurnCommand] runs on every peer at the same
## point of the command stream; the resync ([method adopt_turn]) adopts the
## authority's round state outright, like [member turns_taken].
##
## Known edge, accepted by the owner: a near-zero-gain member holds its round
## open. Gain is uniform today.
var rounds_completed: int = 0
## Whether a round is open. False until the first [method start_turn] (or an
## adopted open round) — so a fixture arranging turns through
## [method adopt_turn] alone never tallies phantom rounds.
var _round_open: bool = false
## The open round's roster members still waiting for their turn to end.
var _round_waiting: Array[Entity] = []


## Whether a round is open — the resync carries it with [method round_waiting].
func is_round_open() -> bool:
	return _round_open


## The open round's roster members whose turn has not ended yet (a copy).
func round_waiting() -> Array[Entity]:
	return _round_waiting.duplicate()


## [b]The handoff is a call sequence, not a subscription.[/b] [method start_turn]
## calls [method Entity.begin_turn] on the entity it names — upkeep, then
## [signal Entity.turn_began], which is what that entity's [EntityController]
## drives [method EntityController.take_turn] from — and only THEN emits
## [signal turn_started], so every listener (HUD banner, initiative bar, action
## cluster, seat handover, harness, [BattleSystem]) sees the turn's upkeep
## already applied. [method end_turn] / [method abandon_turn] call
## [method Entity.finish_turn] before [signal turn_ended] the same way. No entity
## or controller discovers this manager; a second manager in the tree can only
## ever begin the turns it starts.
##
## [method adopt_turn] is the one entry that runs neither: the cursor arrives
## as a RESULT inside a snapshot that already holds the upkeep, so it calls only
## [method Entity.mark_turn_adopted] and emits [signal turn_started] for the
## presentation listeners, which want to hear an adopted cursor exactly as an
## ordinary one.


## The level's TurnManager joins this group (single instance per level) for
## the few non-entity readers that still look it up.
const GROUP := &"turn_manager"

## The [PoolStat]s / [Stat]s currently wired to [method _on_forecast_source_changed]
## — tracked so [method _rebind_forecast_sources] can cleanly disconnect before
## re-walking. Never read for anything else.
var _bound_initiative_pools: Array[PoolStat] = []
var _bound_initiative_speeds: Array[Stat] = []


func _enter_tree() -> void:
	add_to_group(GROUP)
	get_tree().node_added.connect(_on_tree_node_added)
	Events.entity_died.connect(_on_entity_died_rebind)
	_rebind_forecast_sources()


## Undoes [method _enter_tree]'s two connections. Both target the SceneTree
## singleton and the `Events` autoload — neither is `self`, so nothing
## disconnects them automatically when this node leaves the tree (or is
## freed) the way a child-of-self connection would. Left unpaired, a freed
## TurnManager's stale callable still fires on the next node add anywhere in
## the tree — in GUT's single process that means a LATER, unrelated test's
## node churn calling into an exited node, `get_tree()` reading null there.
func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	if Events.entity_died.is_connected(_on_entity_died_rebind):
		Events.entity_died.disconnect(_on_entity_died_rebind)


func _on_tree_node_added(node: Node) -> void:
	if not is_inside_tree():
		return
	if node is Entity:
		_request_forecast_rebind()


func _on_entity_died_rebind(entity: Entity) -> void:
	# A member that dies leaves the open round's roster (#1257). Only
	# [method _note_turn_over] closes a round.
	_round_waiting.erase(entity)
	if not is_inside_tree():
		return
	_request_forecast_rebind()


## True between a rebind request and its deferred run — coalesces a burst
## (N entities spawned in one frame costs one walk, not N).
var _rebind_pending: bool = false


## Deferred, not immediate: [signal SceneTree.node_added] fires after the
## node's `_enter_tree` but BEFORE its `_ready` — and `Entity.add_to_group`
## (`Entity.GROUP`) runs in `_ready` (`entity/entity.gd`). Walking
## `Entity.GROUP` synchronously on `node_added` would run before a freshly
## spawned entity ever joined it, silently skipping that entity's binding
## until some LATER spawn or death happened to re-walk — a real hole: a
## mid-turn `initiative_speed` change on that entity would never fire
## [signal forecast_changed] (Sage review, #909 round 1). `call_deferred`
## runs after `_ready` has had its turn.
func _request_forecast_rebind() -> void:
	if _rebind_pending:
		return
	_rebind_pending = true
	_run_deferred_rebind.call_deferred()


func _run_deferred_rebind() -> void:
	_rebind_pending = false
	if not is_inside_tree():
		return
	_rebind_forecast_sources()


## Re-walks [const Entity.GROUP] and (re)binds [signal forecast_changed] to every
## live entity's `initiative.current_changed` / `initiative_speed.value_changed`
## — the entity-group walk the spec calls for, so a spawn or death (#909) never
## leaves a stale or missing subscription. Idempotent: safe to call on every
## spawn/death without accumulating duplicate connections.
func _rebind_forecast_sources() -> void:
	for p in _bound_initiative_pools:
		if is_instance_valid(p) and p.current_changed.is_connected(_on_forecast_pool_changed):
			p.current_changed.disconnect(_on_forecast_pool_changed)
	_bound_initiative_pools.clear()
	for s in _bound_initiative_speeds:
		if is_instance_valid(s) and s.value_changed.is_connected(_on_forecast_speed_changed):
			s.value_changed.disconnect(_on_forecast_speed_changed)
	_bound_initiative_speeds.clear()
	for node in _in_scope(Entity.GROUP):
		var e := node as Entity
		if e == null or e.stat_board == null:
			continue
		# Guarded per object, not per entity: in the editor an authored entity
		# holds the SHARED board ext_resource until `initialize()` swaps in its
		# copy, so several entities in one walk can alias one pool. The binding
		# stays on that shared board afterwards — harmless, a TurnManager is
		# never ticked in the editor.
		var pool := e.stat_board.initiative
		if pool != null and not pool.current_changed.is_connected(_on_forecast_pool_changed):
			pool.current_changed.connect(_on_forecast_pool_changed)
			_bound_initiative_pools.append(pool)
		var speed := e.stat_board.initiative_speed
		if speed != null and not speed.value_changed.is_connected(_on_forecast_speed_changed):
			speed.value_changed.connect(_on_forecast_speed_changed)
			_bound_initiative_speeds.append(speed)


func _on_forecast_pool_changed(_new_current) -> void:
	forecast_changed.emit()


func _on_forecast_speed_changed() -> void:
	forecast_changed.emit()


## Hand the turn to `entity`: [method Entity.begin_turn] runs its upkeep and
## kicks its controller, then [signal turn_started] tells everyone else.
func start_turn(entity: Entity) -> void:
	assert(entity != null, "TurnManager.start_turn(null)")
	assert(current_entity == null, "Already in a turn: %s" % current_entity)
	# Consume readiness: the entity must climb to its cap again for the next turn.
	entity.remove_from_group(Entity.READY_GROUP)
	_current_entity = entity
	turns_taken += 1
	if not _round_open:
		_open_round()
	entity.begin_turn()
	turn_started.emit(entity)
	real_turn_started.emit(entity)
	forecast_changed.emit()


## Take the authority's cursor as given (#756) — the resync half of "the mirror
## never starts a turn on its own".
##
## [method start_turn] is a DECISION: it consumes readiness, tallies a turn and
## fires the upkeep that turning gives you. This is the same cursor arriving as
## a RESULT, from [method EntitySnapshot.restore_turn_cursor], on a peer that has
## just had its whole world overwritten by the authority's. So it sets what
## `start_turn` sets and runs none of what `start_turn` runs — no
## [method Entity.begin_turn], only [method Entity.mark_turn_adopted] — because the payload it came with is the world AFTER
## all of that already happened.
##
## [param total_turns_taken] is the authority's [member turns_taken], adopted
## outright: it is what [member RunOutcome.turn_count] reports, and a repaired
## mirror counting its own was #756's second symptom (host 48, client 38).
##
## [b]No [signal turn_ended] for the entity being displaced.[/b] That signal
## MUTATES ([method Entity.finish_turn] moves unused AP into next turn's
## surplus), and the surplus this repair should end with is already in the board
## the snapshot just restored. A repair has no presentation semantics and must
## never acquire any (#521 D1); this is the same rule one level down.
##
## A no-op when the cursor already agrees, which is the ordinary case for a
## mid-run repair — and what keeps this idempotent, like every other step of a
## resync decode.
##
## [param rounds], [param round_open] and [param waiting] are the authority's
## round state ([member rounds_completed], whether a round is open, and
## [method round_waiting]), adopted outright for the same reason as the tally —
## a mirror that counted its own would end a turn-limited run on a different
## turn. [param rounds] `< 0` leaves the round state untouched (a caller with
## only a cursor to set). Never emits [signal round_completed].
func adopt_turn(
	entity: Entity, total_turns_taken: int, rounds: int = -1,
	round_open: bool = false, waiting: Array[Entity] = []
) -> void:
	turns_taken = total_turns_taken
	if rounds >= 0:
		rounds_completed = rounds
		_round_open = round_open
		_round_waiting = waiting.duplicate()
	if current_entity == entity:
		return
	# The displaced entity's turn is over in the authority's world; only its
	# flag follows — no finish_turn, see above.
	if current_entity != null and is_instance_valid(current_entity):
		current_entity.is_taking_turn = false
	_current_entity = entity
	if entity == null:
		return
	# The authority's acting entity has spent its readiness; a mirror that left
	# it in the group would serve it again on the next `_tick_until_ready`.
	entity.remove_from_group(Entity.READY_GROUP)
	entity.mark_turn_adopted()
	turn_started.emit(entity)
	forecast_changed.emit()


## End the current turn, then auto-tick until the next entity is ready and
## starts their turn. The acting entity's initiative was already deducted at
## fill time (CyclicPoolStatDef carries the overshoot forward), so there is no
## deduction here.
##
## The ending entity's statuses tick here ([method Entity.resolve_turn_end]),
## after the cursor is nulled and before [method Entity.finish_turn] — only a
## played-out turn ticks. The order is load-bearing: a DoT that kills the actor
## reaches [method abandon_turn] through the death path with the cursor already
## null, so that call is a no-op and this method still finishes the handoff.
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	_current_entity = null
	entity.resolve_turn_end()
	entity.finish_turn()
	turn_ended.emit(entity)
	_note_turn_over(entity)
	forecast_changed.emit()
	_tick_until_ready(entity)


## The acting entity died mid-turn — end its turn without handing the clock on.
## [GameRoot._pull_from_turn_loop] is the caller; a corpse must not hold the
## turn, and until this existed the field was simply nulled from the outside, so
## [signal turn_ended] never fired for a turn that ended by death. The only
## guard on that invariant was [method start_turn]'s `assert`, which is compiled
## out of a release build — the listeners that go stale are real ones
## ([ActionCluster] leaves the End Turn button live, the initiative bar keeps
## the acting tint, [PlayerInputController]'s act-gate never re-emits).
##
## [b]Deliberately does NOT tick on to the next entity[/b], unlike
## [method end_turn]. The handoff is command-ordered: [EndTurnCommand] exists
## precisely so `_tick_until_ready`'s group-order tiebreak runs at the same
## point of the command stream on every peer, and a clock advanced locally out
## of a death handler is that hazard reopened. One death reaches this path with
## the actor's own entity: a status tick killing it at its own turn end — but
## that tick runs inside [method end_turn] after the cursor is nulled, so the
## call is a no-op and `end_turn` does the handoff. Chip damage and core
## overflow kill the DEFENDER during the attacker's turn; a mid-turn death of
## the actor (thorns / counter-damage, named at `LootSystem`'s
## killer-attribution note) is still the unbuilt case this guards.
##
## [b]Never ticks statuses[/b]: an abandoned turn (a death, the status
## sandbox's `disarm`) was not played out — see [method Entity.resolve_turn_end].
##
## No-op unless `entity` is the one actually holding the turn: death fires for
## bystanders too, and `Entity.die()` is re-entrant from inside a forced-dealloc
## cascade, so a second arrival must not emit a second [signal turn_ended].
##
## This does put a side-effect-bearing emit inside the `entity_died` phase —
## [method Entity.finish_turn] runs on the CORPSE, transferring its unused
## AP into a DP/MP surplus and dispatching `_on_turn_end`. Whether that lands
## before or after AllocationSystem's strip is decided by child order in
## `game_root.tscn`, which is scene-authored and therefore identical on every
## peer — deterministic, not a sync hazard — and the surplus itself is written
## to an entity that will never take another turn.
func abandon_turn(entity: Entity) -> void:
	if entity == null or current_entity != entity:
		return
	_current_entity = null
	entity.finish_turn()
	turn_ended.emit(entity)
	_note_turn_over(entity)
	forecast_changed.emit()


## Round bookkeeping at a turn-end site: [param entity]'s turn is over, so it
## leaves the waiting roster; corpses are pruned as a backstop to
## [method _on_entity_died_rebind]. The round closes when nobody living still
## waits — which also closes it at the end of the turn in which its last
## waiting member died off-turn.
func _note_turn_over(entity: Entity) -> void:
	if not _round_open:
		return
	_round_waiting.erase(entity)
	_round_waiting = _round_waiting.filter(
		func(e: Entity) -> bool: return is_instance_valid(e) and not e.is_dead)
	if not _round_waiting.is_empty():
		return
	rounds_completed += 1
	_open_round()
	round_completed.emit(rounds_completed)


## A fresh roster: every living initiative carrier this clock serves.
func _open_round() -> void:
	_round_open = true
	_round_waiting = _initiative_carriers().filter(
		func(e: Entity) -> bool: return not e.is_dead)


## Tick the initiative clock by one unit. Replenishes every entity's `initiative`
## pool by its initiative_speed; a pool that crosses its cap fires `replenished`,
## which the entity handles by joining Entity.READY_GROUP (and the cyclic def
## carries the overshoot into the next cycle).
func tick() -> void:
	ticked.emit()
	for node in _in_scope(Entity.GROUP):
		var e := node as Entity
		if e == null or e.stat_board == null:
			continue
		if e.stat_board.initiative == null or e.stat_board.initiative_speed == null:
			continue
		e.stat_board.initiative.replenish(float(e.stat_board.initiative_speed.value))


## Serve the next ready entity, or tick until one becomes ready.
## Checks BEFORE ticking so entities that crossed the cap in the same cycle are
## each served before the clock advances again. Ready entities are those in
## Entity.READY_GROUP; the tie-break among them is [method order_ready]'s
## three-level key (carried `current` desc → `last` goes last → spawn order).
func _tick_until_ready(last: Entity = null, max_ticks: int = 1000) -> void:
	var last_key: int = last.entity_id if last != null else NO_LAST_KEY
	for _i in max_ticks:
		var ready_entities: Array[Entity] = []
		var by_key: Dictionary = {}
		for node in _in_scope(Entity.READY_GROUP):
			var e := node as Entity
			if e != null:
				_warn_if_unminted(e)
				ready_entities.append(e)
				by_key[e.entity_id] = e
		if not ready_entities.is_empty():
			var entries: Array[Dictionary] = []
			for e in ready_entities:
				var cur := e.stat_board.initiative.current if e.stat_board != null and e.stat_board.initiative != null else 0.0
				entries.append({"key": e.entity_id, "current": cur})
			var ordered := order_ready(entries, last_key)
			start_turn(by_key[ordered[0].key])
			return
		tick()
	push_warning("TurnManager: no entity reached its initiative cap in %d ticks" % max_ticks)


## Sentinel [param last_key] for "no just-acted entity" — [member Entity.entity_id]
## is minted starting at 1 ([method Graph._mint_entity_id]), so 0 never
## collides with a real one.
const NO_LAST_KEY := 0

## Entities already warned by [method _warn_if_unminted], keyed by instance id
## — a `push_warning` per occurrence would spam every tick of a broken fixture.
var _warned_unminted: Dictionary = {}


## `entity_id == 0` means never minted — [method Graph._mint_entity_id] is the
## only minter, on entry to `entities_container`. Production always has a
## Graph; a hand-built fixture without one collapses every unminted entity
## onto the same [code]order_ready[/code] key (0), which also happens to be
## [constant NO_LAST_KEY] (so every such entity reads as "the last actor" for
## the tie-break, and [code]by_key[0][/code] / [code]copies[0][/code] silently
## keeps only the last one seen) — surprising ordering with no error. One
## warning per entity instance names the real cause.
## [param group]'s members under [member entity_root] — every walk of the
## entity groups goes through here, so the clock, readiness and the forecast
## agree on one scope.
func _in_scope(group: StringName) -> Array[Node]:
	var all := get_tree().get_nodes_in_group(group)
	if entity_root == null:
		return all
	return all.filter(func(n: Node) -> bool: return entity_root.is_ancestor_of(n))


## Every initiative-carrying entity this manager's clock serves, in tree order
## — the same scope [method tick] uses ([method _in_scope] over
## [constant Entity.GROUP], which SceneTree sorts in tree order on read, i.e.
## spawn order for appended children: the order `_tick_until_ready`'s tiebreak
## already relies on). Blockers (no `initiative` pool) are skipped.
func _initiative_carriers() -> Array[Entity]:
	var out: Array[Entity] = []
	for node in _in_scope(Entity.GROUP):
		var e := node as Entity
		if e != null and e.stat_board != null and e.stat_board.initiative != null:
			out.append(e)
	return out


## Rescale every initiative carrier's opening clock across (0, cap] so the first
## cycle interleaves turns instead of every entity opening at 0 and the
## tie-break deciding the whole order every cycle (#911). Whether a run
## staggers at all is the caller's call ([member RunConfig.stagger_initiative]).
##
## Runs BEFORE the opening turn, on EVERY peer — never gated on authority: a
## pure function of shared data (spawn order), so every peer reaches the same
## clocks independently, exactly like world generation. The opening
## [StartTurnCommand]'s validator does not look at initiative, so this only
## reshapes who acts SECOND onward, never who opens turn 1.
##
## [b]Index 0 is already [method opening_entity][/b] — spawn order heads roster
## order (#923, owner call on #911: "spawn order. which should be identical to
## roster order (player1, player2, ..., AI1, AI2, ...)"):
## [method ProcgenPlaySandbox._camp_grouped_participants] spawns camp-bucketed,
## in [method ParticipantRoster.camps]' first-appearance order, so roster[0]'s
## camp is bucket 0 and roster[0] heads it. No reordering needed.
func stagger_opening_clocks() -> void:
	TurnManager.apply_initiative_stagger(_initiative_carriers())


## The entity the opening [StartTurnCommand] names: the first initiative carrier
## in [method _initiative_carriers]' order (#923, owner call on #911 — spawn
## order heads roster order, offline, couch and remote alike). No peer-id
## lookup: deriving the same "who opens" fact a second way, off a peer id rather
## than spawn order, is exactly what #923 retired. Null when nothing carries a
## clock.
func opening_entity() -> Entity:
	var carriers := _initiative_carriers()
	return carriers[0] if not carriers.is_empty() else null


## The pure half of [method stagger_opening_clocks] — testable against
## hand-built entities with no tree scan. `carriers` is spawn-ordered (index 0 =
## first spawned); index `i` of `n` opens at `floor(cap * (n - i) / n)` — first
## = cap (ready at once, no initial tick race to win), last = `cap / n`, never
## 0. Written through [method PoolStat.set_current] (never `base_value` — this
## is a `current` write, not a redefinition of the pool).
static func apply_initiative_stagger(carriers: Array[Entity]) -> void:
	var n := carriers.size()
	if n == 0:
		return
	for i in n:
		var pool := carriers[i].stat_board.initiative
		var cap := float(pool.get_value())
		pool.set_current(floor(cap * float(n - i) / float(n)))


func _warn_if_unminted(e: Entity) -> void:
	if e.entity_id != 0:
		return
	var id := e.get_instance_id()
	if _warned_unminted.has(id):
		return
	_warned_unminted[id] = true
	push_warning("TurnManager: entity %s has no minted entity_id — ordering is undefined without a Graph" % e.name)


## The ONE pure ordering step both the live path ([method _tick_until_ready])
## and [method forecast] call — never two comparators (no-parallel-mirrors).
## Operates on plain records rather than [Entity] because [method forecast]
## simulates future `current` on copies and cannot hand it an Entity-reading
## comparator (owner correction, 2026-09-16).
##
## [param entries]: `{key: int (entity_id), current: float}` per ready entity.
## [param last_key]: the just-acted entity's key, or [constant NO_LAST_KEY].
##
## Tie-break, in order: `current` desc → the entry whose key is `last_key`
## goes last → `key` (spawn order) asc. Does not mutate [param entries].
static func order_ready(entries: Array[Dictionary], last_key: int) -> Array[Dictionary]:
	var ordered := entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac: float = a["current"]
		var bc: float = b["current"]
		if ac != bc:
			return ac > bc
		var a_last: bool = a["key"] == last_key
		var b_last: bool = b["key"] == last_key
		if a_last != b_last:
			return b_last  # a sorts first iff b is the just-acted entity
		return int(a["key"]) < int(b["key"])
	)
	return ordered


## Dry-runs the tick + [method order_ready] loop over copies of every live
## entity's `(current, cap, speed)`, starting from the live pools and
## `current_entity` as the first `last`. Returns the next [param n] actors —
## an entity may repeat. Never calls [method tick]; mutates no pool (a copy,
## never the real [PoolStat]) — the HUD forecast strip (#910) must never see,
## let alone cause, a side effect.
func forecast(n: int) -> Array[Entity]:
	var result: Array[Entity] = []
	if n <= 0:
		return result
	var copies: Dictionary = {}  # entity_id -> {entity, current, cap, speed, ready}
	for node in _in_scope(Entity.GROUP):
		var e := node as Entity
		if e == null or e.stat_board == null:
			continue
		if e.stat_board.initiative == null or e.stat_board.initiative_speed == null:
			continue
		_warn_if_unminted(e)
		copies[e.entity_id] = {
			"entity": e,
			"current": e.stat_board.initiative.current,
			"cap": float(e.stat_board.initiative.get_value()),
			"speed": float(e.stat_board.initiative_speed.value),
			"ready": e.is_in_group(Entity.READY_GROUP),
		}
	var last_key: int = current_entity.entity_id if current_entity != null else NO_LAST_KEY
	var max_ticks := 100000  # generous safety bound, mirrors _tick_until_ready's guard
	var ticks := 0
	while result.size() < n and ticks < max_ticks:
		var entries: Array[Dictionary] = []
		for key in copies:
			var c: Dictionary = copies[key]
			if c["ready"]:
				entries.append({"key": key, "current": c["current"]})
		if not entries.is_empty():
			var ordered := order_ready(entries, last_key)
			var picked_key: int = ordered[0]["key"]
			var picked: Dictionary = copies[picked_key]
			result.append(picked["entity"])
			picked["ready"] = false
			last_key = picked_key
			continue
		for key in copies:
			var c: Dictionary = copies[key]
			if c["ready"]:
				continue
			c["current"] += c["speed"]
			if c["cap"] > 0.0 and c["current"] >= c["cap"]:
				c["current"] -= c["cap"]
				c["ready"] = true
		ticks += 1
	return result
