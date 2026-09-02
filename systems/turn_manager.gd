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

## The entity currently taking its turn; null between turns.
var current_entity: Entity = null

## Turns served since the level started — every [method start_turn], across all
## entities, not rounds. [RunOutcome.turn_count] reports it (#460).
var turns_taken: int = 0


## Group used by Entity to discover the level's TurnManager without coupling
## to scene-tree depth. Single instance per level.
const GROUP := &"turn_manager"


func _enter_tree() -> void:
	add_to_group(GROUP)


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
## Entity.READY_GROUP; ties break by carried initiative (more overshoot first),
## then `last` (the just-acted entity) is deprioritised so it can't immediately
## win its own tie.
func _tick_until_ready(last: Entity = null, max_ticks: int = 1000) -> void:
	for _i in max_ticks:
		var ready_entities: Array[Entity] = []
		for node in get_tree().get_nodes_in_group(Entity.READY_GROUP):
			var e := node as Entity
			if e != null:
				ready_entities.append(e)
		if not ready_entities.is_empty():
			ready_entities.sort_custom(func(a: Entity, b: Entity) -> bool:
				var ai := a.stat_board.initiative.current if a.stat_board != null and a.stat_board.initiative != null else 0.0
				var bi := b.stat_board.initiative.current if b.stat_board != null and b.stat_board.initiative != null else 0.0
				if ai != bi:
					return ai > bi
				return b == last  # tiebreak: just-acted entity goes last
			)
			start_turn(ready_entities[0])
			return
		tick()
	push_warning("TurnManager: no entity reached its initiative cap in %d ticks" % max_ticks)
