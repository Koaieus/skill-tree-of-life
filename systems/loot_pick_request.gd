class_name LootPickRequest
extends RefCounted

## A pick-ONE-from-M loot choice, passed over `Events.loot_pick_requested`
## (#173). Same request/response-over-the-bus idiom as [SpellCancellation], but
## with a response: the emitter ([SkillDustAddon]) hands over `candidates` (M)
## and a resolver callback, then waits to see if anyone claimed the pick.
##
## [b]There is no pick count.[/b] The loot shape is "pick 1 out of M, N times" —
## N is [member SkillDustAddon.rounds], and each round raises one of these. A
## `pick_count` field lived here until 2026-08-22 and was always constructed
## with 1; it existed because "pick 1 of M, N times" kept getting written up as
## "pick N of M" (owner's words: *"for the longest time i said 'pick 1 out of N,
## M times' and agents wrote up 'pick M from N'"*). Do not reintroduce it —
## multi-select per draw is not a thing.
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

## The M drawn node-mod candidates offered for the choice. The emitter only
## routes here when there are at least 2 — one survivor is auto-granted rather
## than presented as a choice of one.
var candidates: Array[StatModifier] = []

## Set true SYNCHRONOUSLY by a consumer that takes over the pick (the player
## picker). Left false by everyone else → emitter auto-resolves.
var handled: bool = false

var _resolver: Callable
var _resolved: bool = false


func _init(collector_: Entity, candidates_: Array[StatModifier], resolver: Callable) -> void:
	request_id = _next_request_id
	_next_request_id += 1
	collector = collector_
	candidates = candidates_
	_resolver = resolver


## Grant the chosen modifier. Takes an Array rather than a single [StatModifier]
## because an empty one means "forfeited this round" — the resolver's own
## documented branch. Idempotent: a second call is a no-op, so a picker that
## fires on both "confirm" and a "closed" fallback can't double-grant.
func resolve(chosen: Array[StatModifier]) -> void:
	if _resolved:
		return
	_resolved = true
	if _resolver.is_valid():
		_resolver.call(chosen)


func is_resolved() -> bool:
	return _resolved
