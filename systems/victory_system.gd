class_name VictorySystem
extends Node

## Decides when a run is over, exactly once (#460). The single definition of
## "the run ended" — nothing else may declare it, or the codebase grows two
## answers to the same question.
##
## It owns the *when* and the *once*; the [VictoryCondition] resource owns the
## *what*. That split is what makes the condition swappable per mode without
## every mode re-deriving latching and signal timing.
##
## **Evaluate on death, not per frame** (owner call): the only thing that can
## change last-camp-standing's answer is an entity dying. Reacting to
## [signal Events.entity_death_shown] — the last of the three death phases —
## keeps the terminal announcement behind [AllocationSystem]'s node strip and
## [GameRoot]'s despawn, so nothing observes a half-cleaned world.
##
## The evaluation is **coalesced to one per frame** via a deferred call. That
## is not an optimisation: it is what makes a DRAW reachable at all. Deaths
## arrive one signal at a time, so evaluating inline would see the
## second-to-last death leave one camp standing and declare a WIN before the
## last death ever fired. Coalescing lets a mutual wipe inside a single
## mutation batch be judged as the one event it is. It does not *frame-order a
## mutation* (`.claude/rules/multiplayer-sync.md`) — VictorySystem mutates
## nothing; it reads a world the mutation loop has already settled.

## Emitted alongside [signal Events.run_ended], for a listener that has this
## node and does not want the bus. Fires at most once per run.
signal run_ended(outcome: RunOutcome)

@export var graph: Graph
@export var turn_manager: TurnManager
## The rule in force. Authored here so a hand-built level scene can swap it;
## [GameRoot] overrides it from [member RunConfig.victory_condition] when a run
## carries one — that RunConfig comes off the `GameSession` autoload (#457).
## Defaults to the mode-agnostic baseline for a level with no live run.
@export var condition: VictoryCondition = LastCampStandingCondition.new()

## The latch. `emits once` in the acceptance is this: every subsequent death
## still fires the death signal, and every one of them must be ignored.
var outcome: RunOutcome = null

var _pending: bool = false


func _ready() -> void:
	Events.entity_death_shown.connect(_on_entity_death_shown)


func _on_entity_death_shown(_entity: Entity) -> void:
	if outcome != null or _pending:
		return
	_pending = true
	_evaluate.call_deferred()


## Build a snapshot and ask the condition. Public so a test (or a future
## non-death trigger, e.g. a survive-N-turns condition ticking off
## `turn_ended`) can drive an evaluation without faking a death.
func evaluate_now() -> void:
	_evaluate()


func build_context() -> VictoryContext:
	var ctx := VictoryContext.new()
	ctx.graph = graph
	ctx.turn_count = turn_manager.turns_taken if turn_manager != null else 0
	# One enumeration, always [constant Entity.GROUP] — contest membership is a
	# FILTER the condition applies (#517), never a second group to walk. A
	# rival enumeration would silently drop every `Entity.new()` fixture and
	# sandbox entity out of victory evaluation.
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var ent := node as Entity
		if ent != null:
			ctx.entities.append(ent)
	return ctx


func _evaluate() -> void:
	_pending = false
	if outcome != null or condition == null:
		return
	var result := condition.evaluate(build_context())
	if result == null:
		return
	outcome = result
	# The bus carries it to whoever presents/routes, and to the `GameSession`
	# autoload, which records it as the run's terminal state (#457).
	run_ended.emit(outcome)
	Events.run_ended.emit(outcome)
