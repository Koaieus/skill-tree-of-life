class_name SpellLootRequest
extends RefCounted

## A pick-N-from-M spell draft, passed over `Events.spell_loot_requested` (#204).
## Sibling of [LootPickRequest] — same request/response-over-the-bus idiom, same
## synchronous handshake — with [SpellDef] candidates instead of [StatModifier].
## NOT a generic-widened [LootPickRequest]: Godot has no generics, and folding
## the payload types together would risk disturbing the working stat picker.
##
## THE HANDSHAKE (load-bearing): `emit()` is synchronous. A UI consumer that
## intends to present the draft sets `handled = true` inside its handler —
## before emit() returns. The emitter checks `handled` right after emit(); if
## still false, it auto-resolves a RANDOM pick. That single rule keeps NPCs,
## headless tests, and the "no HUD mounted" path all on the auto-resolve branch,
## which is therefore the default the test suite exercises. Only the human
## player's draft gets `handled = true` (the HUD filters on `collector`).
##
## `resolve(chosen)` is idempotent and fires the resolver once — the picker calls
## it on confirm (async, possibly seconds later), so the resolver must re-check
## that its collector is still valid.

## The entity claiming the draft — whose core the chosen spell will land on.
var collector: Entity = null

## The M drawn spell candidates offered for the choice. Always a pick-ONE —
## see [LootPickRequest] for why there is no pick count on either request.
var candidates: Array[SpellDef] = []

## Set true SYNCHRONOUSLY by a consumer that takes over the pick (the player
## picker). Left false by everyone else → emitter auto-resolves.
var handled: bool = false

var _resolver: Callable
var _resolved: bool = false


func _init(collector_: Entity, candidates_: Array[SpellDef], resolver: Callable) -> void:
	collector = collector_
	candidates = candidates_
	_resolver = resolver


## Grant the chosen subset. Idempotent — a second call is a no-op, so a picker
## that fires on both "confirm" and a "closed" fallback can't double-learn.
func resolve(chosen: Array[SpellDef]) -> void:
	if _resolved:
		return
	_resolved = true
	if _resolver.is_valid():
		_resolver.call(chosen)


func is_resolved() -> bool:
	return _resolved
