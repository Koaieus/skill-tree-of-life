class_name LootPickRequest
extends RefCounted

## A pick-N-from-M loot choice, passed over `Events.loot_pick_requested` (#173).
## Same request/response-over-the-bus idiom as [SpellCancellation], but with a
## response: the emitter ([SkillDustAddon]) hands over `candidates` (M) + how
## many to keep (`pick_count`, N) and a resolver callback, then waits to see if
## anyone claimed the pick.
##
## THE HANDSHAKE (load-bearing): `emit()` is synchronous. A UI consumer that
## intends to present the choice sets `handled = true` inside its handler —
## before emit() returns. The emitter checks `handled` right after emit(); if
## still false, it auto-resolves a RANDOM pick. That single rule keeps NPCs,
## headless tests, and the "no HUD mounted" path all on the auto-resolve branch,
## which is therefore the default the test suite exercises. Only the human
## player's relic gets `handled = true` (the HUD filters on `collector`).
##
## `resolve(chosen)` is idempotent and fires the resolver once — the picker calls
## it on confirm (async, possibly seconds later), so the resolver must re-check
## that its collector is still valid.

## Process-unique id, minted here rather than by any one emitter — the
## request is raised by [SkillDustAddon] today and the issue that asked for
## this (#509) guessed [LootSystem], so minting in `_init` covers whoever
## raises it next. Correlates a [PickLootCommand] back to the request that
## asked, since several can be queued at once (`ui/hud/hud_root.gd`
## `_enqueue_pick`). Never reused; 1-based, so 0 means "no request".
static var _next_request_id: int = 1
var request_id: int = 0

## The entity claiming the relic — whose core the chosen mods will land on.
var collector: Entity = null

## The M drawn node-mod candidates offered for the choice.
var candidates: Array[StatModifier] = []

## The N the collector keeps (N < M when there's a real choice; the emitter
## only routes here when candidates.size() > pick_count).
var pick_count: int = 0

## Set true SYNCHRONOUSLY by a consumer that takes over the pick (the player
## picker). Left false by everyone else → emitter auto-resolves.
var handled: bool = false

var _resolver: Callable
var _resolved: bool = false


func _init(collector_: Entity, candidates_: Array[StatModifier], pick_count_: int, resolver: Callable) -> void:
	request_id = _next_request_id
	_next_request_id += 1
	collector = collector_
	candidates = candidates_
	pick_count = pick_count_
	_resolver = resolver


## Grant the chosen subset. Idempotent — a second call is a no-op, so a picker
## that fires on both "confirm" and a "closed" fallback can't double-grant.
func resolve(chosen: Array[StatModifier]) -> void:
	if _resolved:
		return
	_resolved = true
	if _resolver.is_valid():
		_resolver.call(chosen)


func is_resolved() -> bool:
	return _resolved
