class_name SpellLootRequest
extends RefCounted

## A pick-N-from-M spell draft, passed over `Events.spell_loot_requested` (#204).
## Sibling of [LootPickRequest] — same request/response-over-the-bus idiom, same
## synchronous handshake — with [SpellDef] candidates instead of [StatModifier].
## NOT a generic-widened [LootPickRequest]: Godot has no generics, and folding
## the payload types together would risk disturbing the working stat picker.
##
## THE HANDSHAKE (load-bearing): `emit()` is synchronous. A UI consumer that
## intends to present the draft sets [member claim] to `LOCAL` inside its
## handler — before emit() returns. The emitter checks it right after emit(); if
## still `UNCLAIMED` it auto-resolves a RANDOM pick. That single rule keeps NPCs,
## headless tests, and the "no HUD mounted" path all on the auto-resolve branch,
## which is therefore the default the test suite exercises. Only the human
## player's draft gets `LOCAL` (the HUD filters on `collector`).
##
## [b]It now carries a `request_id` too (#522).[/b] It had none, which is why
## the issue that wired loot to the wire recorded "a spell round cannot be
## correlated by a [PickLootCommand] as written" as its last open item. The fix
## was not a second static counter here — it was moving the minting to
## [LootPickRegistry], so both request kinds draw from ONE host-authoritative id
## space and [PickLootCommand] addresses either with the field it already has.
## The two classes still are not folded together (see the note above); this is
## a plain field the registry fills.
##
## `resolve(chosen)` is idempotent and fires the resolver once — the picker calls
## it on confirm (async, possibly seconds later), so the resolver must re-check
## that its collector is still valid.

## Which peer is answering. Same tri-state as [LootPickRequest]; see there for
## why a bool could not express "a REMOTE human is picking".
enum Claim { UNCLAIMED, LOCAL, REMOTE }

## Set by [LootPickRegistry] when this request is parked for a remote picker.
## 0 means "not registered" — see [member LootPickRequest.request_id].
var request_id: int = 0

## The entity claiming the draft — whose core the chosen spell will land on.
var collector: Entity = null

## The M drawn spell candidates offered for the choice. Always a pick-ONE —
## see [LootPickRequest] for why there is no pick count on either request.
var candidates: Array[SpellDef] = []

## Set SYNCHRONOUSLY by a consumer that takes over the pick (the player
## picker). Left `UNCLAIMED` by everyone else → emitter auto-resolves.
var claim: Claim = Claim.UNCLAIMED

## Emitted once from [method resolve], before the resolver callback — the
## `await`-able face of the same event. See [signal LootPickRequest.settled].
signal settled(chosen: Array)

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
	settled.emit(chosen)
	if _resolver.is_valid():
		_resolver.call(chosen)


func is_resolved() -> bool:
	return _resolved
