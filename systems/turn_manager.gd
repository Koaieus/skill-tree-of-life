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
signal turn_ended(entity: Entity)

## Fires whenever [method forecast]'s answer could have changed: after
## `turn_started`, after `turn_ended`, and whenever any live entity's
## `initiative` pool or `initiative_speed` stat changes value. The HUD strip
## (#910) subscribes to this ONE signal and nothing else — never
## `initiative.current_changed` / `initiative_speed.value_changed` per entity,
## which would mean re-wiring on every spawn/death itself.
signal forecast_changed

## The entity currently taking its turn; null between turns.
var current_entity: Entity = null

## Turns served since the level started — every [method start_turn], across all
## entities, not rounds. [RunOutcome.turn_count] reports it (#460).
var turns_taken: int = 0


## True only for the duration of [method adopt_turn]'s [signal turn_started]
## emit. It is what tells [method Entity._on_turn_started] that this particular
## turn start is a REPAIR and not a beginning: the snapshot it arrived with
## already carries the results of that turn's upkeep (every pool's `current`,
## every node's HP and regen stacks, [member Entity.turns_taken] itself), so
## running the upkeep again would apply it twice.
##
## [b]A flag rather than a second signal.[/b] `turn_started` has seven listeners
## and six of them are presentation or dispatch — the HUD banner, the initiative
## bar, the action cluster, the seat handover, the harness announcements,
## [BattleSystem]'s plan invalidation — and every one of them wants to hear an
## adopted cursor exactly as it hears an ordinary one. Only ONE listener mutates
## the world, and it is the one the snapshot has already spoken for. A parallel
## `turn_adopted` signal would mean re-wiring all six to hear both and would put
## two spellings of "the turn is now this entity's" in the tree
## (`.claude/rules/…` — one implementation over swappable state).
var is_adopting: bool = false


## Group used by Entity to discover the level's TurnManager without coupling
## to scene-tree depth. Single instance per level.
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


func _on_entity_died_rebind(_entity: Entity) -> void:
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
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var e := node as Entity
		if e == null or e.stat_board == null:
			continue
		if e.stat_board.initiative != null:
			e.stat_board.initiative.current_changed.connect(_on_forecast_pool_changed)
			_bound_initiative_pools.append(e.stat_board.initiative)
		if e.stat_board.initiative_speed != null:
			e.stat_board.initiative_speed.value_changed.connect(_on_forecast_speed_changed)
			_bound_initiative_speeds.append(e.stat_board.initiative_speed)


func _on_forecast_pool_changed(_new_current) -> void:
	forecast_changed.emit()


func _on_forecast_speed_changed() -> void:
	forecast_changed.emit()


## Hand the turn to `entity`. Turn-start upkeep (budget replenish) runs in
## Entity._on_turn_started, subscribed to `turn_started`.
func start_turn(entity: Entity) -> void:
	assert(entity != null, "TurnManager.start_turn(null)")
	assert(current_entity == null, "Already in a turn: %s" % current_entity)
	# Consume readiness: the entity must climb to its cap again for the next turn.
	entity.remove_from_group(Entity.READY_GROUP)
	current_entity = entity
	turns_taken += 1
	turn_started.emit(entity)
	# Sparse status-tick channel (#879): emitted AFTER `turn_started` above
	# returns, so Entity._on_turn_started's upkeep (regen included) has
	# already run — never from `adopt_turn`, which is a resync repair, not a
	# real turn begin.
	Events.turn_started.emit(entity)
	forecast_changed.emit()


## Take the authority's cursor as given (#756) — the resync half of "the mirror
## never starts a turn on its own".
##
## [method start_turn] is a DECISION: it consumes readiness, tallies a turn and
## fires the upkeep that turning gives you. This is the same cursor arriving as
## a RESULT, from [method EntitySnapshot.restore_turn_cursor], on a peer that has
## just had its whole world overwritten by the authority's. So it sets what
## `start_turn` sets and runs none of what `start_turn` runs — see
## [member is_adopting] — because the payload it came with is the world AFTER
## all of that already happened.
##
## [param total_turns_taken] is the authority's [member turns_taken], adopted
## outright: it is what [member RunOutcome.turn_count] reports, and a repaired
## mirror counting its own was #756's second symptom (host 48, client 38).
##
## [b]No [signal turn_ended] for the entity being displaced.[/b] That signal
## MUTATES ([method Entity._on_turn_ended] moves unused AP into next turn's
## surplus), and the surplus this repair should end with is already in the board
## the snapshot just restored. A repair has no presentation semantics and must
## never acquire any (#521 D1); this is the same rule one level down.
##
## A no-op when the cursor already agrees, which is the ordinary case for a
## mid-run repair — and what keeps this idempotent, like every other step of a
## resync decode.
func adopt_turn(entity: Entity, total_turns_taken: int) -> void:
	turns_taken = total_turns_taken
	if current_entity == entity:
		return
	current_entity = entity
	if entity == null:
		return
	# The authority's acting entity has spent its readiness; a mirror that left
	# it in the group would serve it again on the next `_tick_until_ready`.
	entity.remove_from_group(Entity.READY_GROUP)
	is_adopting = true
	turn_started.emit(entity)
	is_adopting = false
	forecast_changed.emit()


## End the current turn, then auto-tick until the next entity is ready and
## starts their turn. The acting entity's initiative was already deducted at
## fill time (CyclicPoolStatDef carries the overshoot forward), so there is no
## deduction here.
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	current_entity = null
	turn_ended.emit(entity)
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
## of a death handler is that hazard reopened. Nothing reaches this path today —
## chip damage and core overflow both kill the DEFENDER during the attacker's
## turn — so the handoff has no reachable caller to design against; the
## mechanic that would create one is named at `LootSystem`'s killer-attribution
## note ("Thorns / counter-damage would kill on the defender's turn — when those
## land this needs real source-threading"), and that is where it belongs.
##
## No-op unless `entity` is the one actually holding the turn: death fires for
## bystanders too, and `Entity.die()` is re-entrant from inside a forced-dealloc
## cascade, so a second arrival must not emit a second [signal turn_ended].
##
## This does put a side-effect-bearing emit inside the `entity_died` phase —
## [method Entity._on_turn_ended] fires on the CORPSE, transferring its unused
## AP into a DP/MP surplus and dispatching `_on_turn_end`. Whether that lands
## before or after AllocationSystem's strip is decided by child order in
## `game_root.tscn`, which is scene-authored and therefore identical on every
## peer — deterministic, not a sync hazard — and the surplus itself is written
## to an entity that will never take another turn.
func abandon_turn(entity: Entity) -> void:
	if entity == null or current_entity != entity:
		return
	current_entity = null
	turn_ended.emit(entity)
	forecast_changed.emit()


## Tick the initiative clock by one unit. Replenishes every entity's `initiative`
## pool by its initiative_speed; a pool that crosses its cap fires `replenished`,
## which the entity handles by joining Entity.READY_GROUP (and the cyclic def
## carries the overshoot into the next cycle).
func tick() -> void:
	ticked.emit()
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
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
		for node in get_tree().get_nodes_in_group(Entity.READY_GROUP):
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
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
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
